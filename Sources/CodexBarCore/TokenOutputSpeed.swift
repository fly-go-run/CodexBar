import Foundation

/// One model API request reconstructed from local session logs.
///
/// `startedAt` is when the request was sent (the log entry that triggered it) and `completedAt`
/// is when the last content block of the response was written, so the duration includes
/// time-to-first-token. The derived rate is end-to-end output throughput, not pure decode speed.
public struct TokenOutputSpeedSample: Sendable, Equatable {
    public let model: String
    public let outputTokens: Int
    public let startedAt: Date
    public let completedAt: Date

    public init(model: String, outputTokens: Int, startedAt: Date, completedAt: Date) {
        self.model = model
        self.outputTokens = outputTokens
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    public var durationSeconds: TimeInterval {
        self.completedAt.timeIntervalSince(self.startedAt)
    }

    /// Tiny responses are dominated by latency and stalled requests by retries; neither says
    /// anything useful about generation speed.
    var isMeasurable: Bool {
        self.outputTokens >= TokenOutputSpeedSnapshot.minimumOutputTokens
            && self.durationSeconds >= 0.2
            && self.durationSeconds <= 600
    }
}

public struct TokenOutputSpeedSnapshot: Sendable, Equatable {
    public struct Bucket: Sendable, Equatable {
        public let model: String?
        public let requestCount: Int
        public let outputTokens: Int
        public let seconds: TimeInterval

        /// Duration-weighted, so long responses count proportionally to the time they took.
        public var tokensPerSecond: Double {
            self.seconds > 0 ? Double(self.outputTokens) / self.seconds : 0
        }
    }

    static let minimumOutputTokens = 20

    public let windowSeconds: TimeInterval
    /// Per-model buckets over the whole window, largest output first.
    public let models: [Bucket]
    /// All models over the trailing hour; nil when there were no measurable requests.
    public let lastHour: Bucket?
    public let updatedAt: Date

    public init(samples: [TokenOutputSpeedSample], now: Date, windowSeconds: TimeInterval = 24 * 60 * 60) {
        let measurable = samples.filter {
            $0.isMeasurable && $0.completedAt <= now && now.timeIntervalSince($0.completedAt) <= windowSeconds
        }
        self.windowSeconds = windowSeconds
        self.updatedAt = now
        self.models = Dictionary(grouping: measurable, by: \.model)
            .map { Self.bucket(model: $0.key, samples: $0.value) }
            .sorted { lhs, rhs in
                lhs.outputTokens != rhs.outputTokens ? lhs.outputTokens > rhs.outputTokens : lhs.model! < rhs.model!
            }
        let recent = measurable.filter { now.timeIntervalSince($0.completedAt) <= 60 * 60 }
        self.lastHour = recent.isEmpty ? nil : Self.bucket(model: nil, samples: recent)
    }

    public var isEmpty: Bool {
        self.models.isEmpty
    }

    private static func bucket(model: String?, samples: [TokenOutputSpeedSample]) -> Bucket {
        Bucket(
            model: model,
            requestCount: samples.count,
            outputTokens: samples.reduce(0) { $0 + $1.outputTokens },
            seconds: samples.reduce(0) { $0 + $1.durationSeconds })
    }
}

/// Scans recent Claude Code / Codex session logs for per-request output speed.
///
/// Only files modified inside the window are read. Each file keeps its parser state and the byte
/// offset it has been parsed up to, so a refresh only parses what was appended to the sessions being
/// written (a shrunk, replaced or rewritten file is parsed again from the start).
public final class TokenOutputSpeedScanner: @unchecked Sendable {
    public static let shared = TokenOutputSpeedScanner()

    /// Only the parser for the file's provider is ever used; the other stays empty.
    private struct ParserState {
        var claude = ClaudeSessionParser()
        var codex = CodexSessionParser()

        func samples(for provider: UsageProvider) -> [TokenOutputSpeedSample] {
            provider == .codex ? self.codex.samples : self.claude.samples
        }
    }

    private struct CachedFile {
        let fileID: String
        let size: Int
        let modifiedAt: Date
        /// End of the last complete line that was parsed; a half-written tail is retried next time.
        let committedOffset: Int64
        /// The last bytes before `committedOffset`: proof, before resuming, that what was parsed is still there.
        let tailFingerprint: Data
        let parser: ParserState
    }

    private struct SessionFile {
        let url: URL
        let size: Int
        let modifiedAt: Date
        let fileID: String
    }

    /// Lines past these caps are skipped, like the cost scanner does. Claude lines carry base64 images
    /// and tool output of a few MB; Codex lines only need the fields at the start of the line.
    static let defaultClaudeMaxLineBytes = 8 * 1024 * 1024
    static let defaultCodexMaxLineBytes = 1024 * 1024

    private let claudeMaxLineBytes: Int
    private let codexMaxLineBytes: Int
    private let lock = NSLock()
    private var caches: [UsageProvider: [String: CachedFile]] = [:]
    private var bytesParsed: Int64 = 0

    public init() {
        self.claudeMaxLineBytes = Self.defaultClaudeMaxLineBytes
        self.codexMaxLineBytes = Self.defaultCodexMaxLineBytes
    }

    init(claudeMaxLineBytes: Int, codexMaxLineBytes: Int) {
        self.claudeMaxLineBytes = claudeMaxLineBytes
        self.codexMaxLineBytes = codexMaxLineBytes
    }

    /// Throws `CancellationError` when the surrounding task is cancelled; a file that was being
    /// parsed at that moment is dropped from the cache rather than left half-updated.
    public func snapshot(
        provider: UsageProvider,
        codexHomePath: String? = nil,
        claudeProjectsRoots: [URL]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date(),
        windowSeconds: TimeInterval = 24 * 60 * 60) throws -> TokenOutputSpeedSnapshot?
    {
        let roots: [URL]
        switch provider {
        case .claude:
            roots = claudeProjectsRoots ?? ClaudeConfigPaths.costProjectsRoots(environment: environment)
        case .codex:
            roots = Self.codexSessionsRoots(codexHomePath: codexHomePath, environment: environment)
        default:
            return nil
        }

        let cutoff = now.addingTimeInterval(-windowSeconds)
        let files = try Self.recentJSONLFiles(roots: roots, modifiedSince: cutoff)
        self.evictFiles(for: provider, keeping: Set(files.map(\.url.path)))
        var samples: [TokenOutputSpeedSample] = []
        for file in files {
            try Task.checkCancellation()
            try samples.append(contentsOf: self.samples(for: file, provider: provider))
        }
        let snapshot = TokenOutputSpeedSnapshot(samples: samples, now: now, windowSeconds: windowSeconds)
        return snapshot.isEmpty ? nil : snapshot
    }

    /// Number of session files with retained parser state (for tests).
    func cachedFileCount(for provider: UsageProvider) -> Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.caches[provider]?.count ?? 0
    }

    /// Total bytes handed to the parsers since creation (for tests).
    var totalBytesParsed: Int64 {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.bytesParsed
    }

    private func evictFiles(for provider: UsageProvider, keeping paths: Set<String>) {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let cache = self.caches[provider] else { return }
        self.caches[provider] = cache.filter { paths.contains($0.key) }
    }

    private func samples(for file: SessionFile, provider: UsageProvider) throws -> [TokenOutputSpeedSample] {
        let key = file.url.path
        // Taken out of the cache while it is mutated so the parser state is not copied.
        self.lock.lock()
        let cached = self.caches[provider]?.removeValue(forKey: key)
        self.lock.unlock()

        if let cached, cached.fileID == file.fileID, cached.size == file.size, cached.modifiedAt == file.modifiedAt {
            self.store(cached, provider: provider, key: key)
            return cached.parser.samples(for: provider)
        }

        var parser: ParserState
        var offset: Int64 = 0
        if let cached, cached.fileID == file.fileID, file.size > cached.size, cached.committedOffset <= file.size,
           Self.tailFingerprint(of: file.url, endingAt: cached.committedOffset) == cached.tailFingerprint
        {
            parser = cached.parser
            offset = cached.committedOffset
        } else {
            parser = ParserState()
        }

        let isCodex = provider == .codex
        let maxLineBytes = isCodex ? self.codexMaxLineBytes : self.claudeMaxLineBytes
        let committed: Int64
        do {
            committed = try CostUsageJsonl.scan(
                fileURL: file.url,
                offset: offset,
                maxLineBytes: maxLineBytes,
                prefixBytes: maxLineBytes,
                checkCancellation: { try Task.checkCancellation() },
                onLine: { line in
                    guard !line.bytes.isEmpty else { return }
                    if isCodex {
                        parser.codex.consume(line: line.bytes, truncated: line.wasTruncated)
                    } else {
                        parser.claude.consume(line: line.bytes, truncated: line.wasTruncated)
                    }
                })
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return []
        }

        self.lock.lock()
        self.bytesParsed += max(0, committed - offset)
        self.lock.unlock()
        self.store(
            CachedFile(
                fileID: file.fileID,
                size: file.size,
                modifiedAt: file.modifiedAt,
                committedOffset: committed,
                tailFingerprint: Self.tailFingerprint(of: file.url, endingAt: committed) ?? Data(),
                parser: parser),
            provider: provider,
            key: key)
        return parser.samples(for: provider)
    }

    private func store(_ file: CachedFile, provider: UsageProvider, key: String) {
        self.lock.lock()
        self.caches[provider, default: [:]][key] = file
        self.lock.unlock()
    }

    // MARK: - Roots

    static func codexSessionsRoots(codexHomePath: String?, environment: [String: String]) -> [URL] {
        let home = CodexHomeScope.normalizedHomePath(codexHomePath).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? CodexHomeScope.ambientHomeURL(env: environment)
        var options = CostUsageScanner.Options()
        options.codexSessionsRoot = CodexHomeScope.sessionsRoot(home: home)
        return CostUsageScanner.codexSessionsRoots(options: options)
    }

    private static func recentJSONLFiles(roots: [URL], modifiedSince cutoff: Date) throws -> [SessionFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var files: [SessionFile] = []
        var seen: Set<String> = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles])
            else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                try Task.checkCancellation()
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modifiedAt = values.contentModificationDate,
                      modifiedAt >= cutoff,
                      seen.insert(url.resolvingSymlinksInPath().path).inserted
                else { continue }
                files.append(SessionFile(
                    url: url,
                    size: values.fileSize ?? 0,
                    modifiedAt: modifiedAt,
                    fileID: Self.fileID(of: url)))
            }
        }
        return files
    }

    static let tailFingerprintLength = 256

    /// Up to 256 bytes ending at `offset`; nil when they cannot be read (the file shrank or vanished).
    /// A same-inode file that grew can still have been truncated and rewritten, which this exposes.
    private static func tailFingerprint(of url: URL, endingAt offset: Int64) -> Data? {
        guard offset > 0 else { return Data() }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let length = min(Int64(Self.tailFingerprintLength), offset)
        do {
            try handle.seek(toOffset: UInt64(offset - length))
            let data = try handle.read(upToCount: Int(length)) ?? Data()
            return data.count == Int(length) ? data : nil
        } catch {
            return nil
        }
    }

    /// Device + inode, so a log that was replaced by another file at the same path starts over.
    private static func fileID(of url: URL) -> String {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return "" }
        return "\(info.st_dev):\(info.st_ino)"
    }

    // MARK: - Whole-file parsing

    /// Parses a complete log held in memory; the incremental scanner feeds the same parsers line by line.
    static func parseClaudeSession(_ data: Data) -> [TokenOutputSpeedSample] {
        var parser = ClaudeSessionParser()
        self.forEachLine(in: data) { parser.consume(line: $0, truncated: false) }
        return parser.samples
    }

    static func parseCodexSession(_ data: Data) -> [TokenOutputSpeedSample] {
        var parser = CodexSessionParser()
        self.forEachLine(in: data) { parser.consume(line: $0, truncated: false) }
        return parser.samples
    }

    private static func forEachLine(in data: Data, _ body: (Data) -> Void) {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            var lineStart = 0
            let count = buffer.count
            while lineStart < count {
                let remaining = count - lineStart
                let lineEnd: Int = if let newline = memchr(base + lineStart, 0x0A, remaining) {
                    base.distance(to: UnsafeRawPointer(newline))
                } else {
                    count
                }
                if lineEnd > lineStart {
                    body(Data(
                        bytesNoCopy: UnsafeMutableRawPointer(mutating: base + lineStart),
                        count: lineEnd - lineStart,
                        deallocator: .none))
                }
                lineStart = lineEnd + 1
            }
        }
    }
}
