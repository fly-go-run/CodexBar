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
/// Only files modified inside the window are read, and parsed samples are cached per file
/// (keyed by size + mtime), so steady-state refreshes only re-read the sessions being written.
public final class TokenOutputSpeedScanner: @unchecked Sendable {
    public static let shared = TokenOutputSpeedScanner()

    private struct CachedFile {
        let size: Int
        let modifiedAt: Date
        let samples: [TokenOutputSpeedSample]
    }

    private let lock = NSLock()
    private var cache: [String: CachedFile] = [:]

    public init() {}

    public func snapshot(
        provider: UsageProvider,
        codexHomePath: String? = nil,
        claudeProjectsRoots: [URL]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date(),
        windowSeconds: TimeInterval = 24 * 60 * 60) -> TokenOutputSpeedSnapshot?
    {
        let roots: [URL]
        let parse: (Data) -> [TokenOutputSpeedSample]
        switch provider {
        case .claude:
            roots = claudeProjectsRoots ?? Self.claudeProjectsRoots(environment: environment)
            parse = Self.parseClaudeSession
        case .codex:
            roots = Self.codexSessionsRoots(codexHomePath: codexHomePath, environment: environment)
            parse = Self.parseCodexSession
        default:
            return nil
        }

        let cutoff = now.addingTimeInterval(-windowSeconds)
        var samples: [TokenOutputSpeedSample] = []
        for file in Self.recentJSONLFiles(roots: roots, modifiedSince: cutoff) {
            samples.append(contentsOf: self.samples(for: file, parse: parse))
        }
        let snapshot = TokenOutputSpeedSnapshot(samples: samples, now: now, windowSeconds: windowSeconds)
        return snapshot.isEmpty ? nil : snapshot
    }

    private func samples(
        for file: (url: URL, size: Int, modifiedAt: Date),
        parse: (Data) -> [TokenOutputSpeedSample]) -> [TokenOutputSpeedSample]
    {
        let key = file.url.path
        self.lock.lock()
        let cached = self.cache[key]
        self.lock.unlock()
        if let cached, cached.size == file.size, cached.modifiedAt == file.modifiedAt {
            return cached.samples
        }
        guard let data = try? Data(contentsOf: file.url, options: .mappedIfSafe) else { return [] }
        let samples = parse(data)
        self.lock.lock()
        self.cache[key] = CachedFile(size: file.size, modifiedAt: file.modifiedAt, samples: samples)
        self.lock.unlock()
        return samples
    }

    // MARK: - Roots

    static func claudeProjectsRoots(environment: [String: String]) -> [URL] {
        if let env = environment["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty
        {
            return env.split(separator: ",").compactMap { part in
                let raw = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { return nil }
                let url = URL(fileURLWithPath: raw)
                return url.lastPathComponent == "projects"
                    ? url
                    : url.appendingPathComponent("projects", isDirectory: true)
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".config/claude/projects", isDirectory: true),
            home.appendingPathComponent(".claude/projects", isDirectory: true),
        ]
    }

    static func codexSessionsRoots(codexHomePath: String?, environment: [String: String]) -> [URL] {
        let home: URL = if let path = codexHomePath?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !path.isEmpty
        {
            URL(fileURLWithPath: path, isDirectory: true)
        } else if let env = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !env.isEmpty
        {
            URL(fileURLWithPath: env, isDirectory: true)
        } else {
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        }
        return [
            home.appendingPathComponent("sessions", isDirectory: true),
            home.appendingPathComponent("archived_sessions", isDirectory: true),
        ]
    }

    private static func recentJSONLFiles(
        roots: [URL],
        modifiedSince cutoff: Date) -> [(url: URL, size: Int, modifiedAt: Date)]
    {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var files: [(url: URL, size: Int, modifiedAt: Date)] = []
        var seen: Set<String> = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles])
            else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modifiedAt = values.contentModificationDate,
                      modifiedAt >= cutoff,
                      seen.insert(url.resolvingSymlinksInPath().path).inserted
                else { continue }
                files.append((url, values.fileSize ?? 0, modifiedAt))
            }
        }
        return files
    }

    // MARK: - Parsing

    /// Claude Code writes one line per content block; lines of one response share `message.id`
    /// and carry the final `usage.output_tokens`. A response's first line points (`parentUuid`)
    /// at the entry that triggered the request — a prompt, tool result, or attachment.
    static func parseClaudeSession(_ data: Data) -> [TokenOutputSpeedSample] {
        struct Request {
            let model: String
            let startedAt: Date
            var completedAt: Date
            var outputTokens: Int
        }
        var entryTimes: [String: Date] = [:]
        var requests: [String: Request?] = [:]
        var order: [String] = []

        self.forEachJSONObject(in: data) { object in
            guard let timestamp = (object["timestamp"] as? String).flatMap(Self.parseTimestamp) else { return }
            if let uuid = object["uuid"] as? String {
                defer { entryTimes[uuid] = timestamp }
                guard object["type"] as? String == "assistant" else { return }
            } else {
                return
            }
            guard let message = object["message"] as? [String: Any],
                  let id = message["id"] as? String,
                  let model = message["model"] as? String,
                  model != "<synthetic>"
            else { return }
            let output = ((message["usage"] as? [String: Any])?["output_tokens"] as? NSNumber)?.intValue

            if let existing = requests[id] {
                guard var request = existing else { return }
                request.completedAt = max(request.completedAt, timestamp)
                if let output { request.outputTokens = max(request.outputTokens, output) }
                requests[id] = request
                return
            }
            order.append(id)
            guard let parent = object["parentUuid"] as? String,
                  let startedAt = entryTimes[parent],
                  startedAt <= timestamp
            else {
                requests[id] = .some(nil)
                return
            }
            requests[id] = Request(
                model: model,
                startedAt: startedAt,
                completedAt: timestamp,
                outputTokens: output ?? 0)
        }

        return order.compactMap { id in
            guard case let .some(request?) = requests[id] else { return nil }
            return TokenOutputSpeedSample(
                model: request.model,
                outputTokens: request.outputTokens,
                startedAt: request.startedAt,
                completedAt: request.completedAt)
        }
    }

    /// Codex rollouts: a request starts at the user message or tool output that precedes it,
    /// ends at the last model output item, and `token_count.info.last_token_usage` reports its
    /// output tokens (reasoning included). `token_count` is often logged after the tool output
    /// that already belongs to the next request, so that input is held until the count lands.
    static func parseCodexSession(_ data: Data) -> [TokenOutputSpeedSample] {
        var samples: [TokenOutputSpeedSample] = []
        var model: String?
        var startedAt: Date?
        var completedAt: Date?
        var nextStartedAt: Date?

        func input(_ timestamp: Date) {
            if completedAt == nil {
                startedAt = timestamp
            } else {
                nextStartedAt = timestamp
            }
        }

        func output(_ timestamp: Date) {
            if let next = nextStartedAt {
                // The previous request never reported tokens; start over from the newer input.
                startedAt = next
                nextStartedAt = nil
            }
            if startedAt != nil { completedAt = timestamp }
        }

        self.forEachJSONObject(in: data) { object in
            guard let timestamp = (object["timestamp"] as? String).flatMap(Self.parseTimestamp),
                  let payload = object["payload"] as? [String: Any]
            else { return }
            let payloadType = payload["type"] as? String
            switch (object["type"] as? String, payloadType) {
            case ("turn_context", _):
                if let value = payload["model"] as? String, !value.isEmpty { model = value }
            case ("response_item", "message"):
                switch payload["role"] as? String {
                case "assistant": output(timestamp)
                case "user": input(timestamp)
                default: break
                }
            case ("response_item", "function_call_output"), ("response_item", "custom_tool_call_output"):
                input(timestamp)
            case ("response_item", _):
                output(timestamp)
            case ("event_msg", "token_count"):
                guard let start = startedAt, let end = completedAt else { return }
                let info = payload["info"] as? [String: Any]
                let last = info?["last_token_usage"] as? [String: Any]
                guard let tokens = (last?["output_tokens"] as? NSNumber)?.intValue else { return }
                if let model {
                    samples.append(TokenOutputSpeedSample(
                        model: model,
                        outputTokens: tokens,
                        startedAt: start,
                        completedAt: end))
                }
                startedAt = nextStartedAt
                completedAt = nil
                nextStartedAt = nil
            default:
                break
            }
        }
        return samples
    }

    private static func forEachJSONObject(in data: Data, _ body: ([String: Any]) -> Void) {
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
                    let line = Data(
                        bytesNoCopy: UnsafeMutableRawPointer(mutating: base + lineStart),
                        count: lineEnd - lineStart,
                        deallocator: .none)
                    autoreleasepool {
                        if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                            body(object)
                        }
                    }
                }
                lineStart = lineEnd + 1
            }
        }
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        CostUsageScanner.dateFromTimestamp(raw)
    }
}
