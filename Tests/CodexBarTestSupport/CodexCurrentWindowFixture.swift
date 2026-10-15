// SwiftBuild also compiles this test-support target for `swift build -c release`,
// where CodexBarCore is not built for testing.
#if DEBUG
import Foundation
import Testing
@testable import CodexBarCore

struct CodexCurrentWindowFixture {
    enum Kind: Sendable {
        case historical, unresolved, subagent, missingParent, incompleteCost, unknownCost, unparsedSuffix
        case staleParser, currentMigration
    }

    let base: ReadWorkFixture
    let pendingURL: URL
    let previousTime: Date

    init(kind: Kind, retainedReport: Bool = true) throws {
        let base = try ReadWorkFixture(fileCount: 2, rowsPerFile: 4)
        do {
            var cache = base.canonical
            let path = try #require(cache.files.keys.max())
            let url = URL(fileURLWithPath: path)
            let oldDay = "2026-06-01"
            let hasCurrentEvents = [.unresolved, .subagent, .missingParent, .currentMigration].contains(kind)
            let eventDay = hasCurrentEvents ? ReadWorkFixture.day : oldDay
            let header = #"{"type":"session_meta","timestamp":"2026-06-01T12:00:00Z","# +
                #""payload":{"session_id":"fixture-session-1"}}"#
            let record = Self.tokenRecord(day: eventDay)
            let prefix = ([header] + Array(repeating: record, count: 4)).joined(separator: "\n") + "\n"
            let contents = kind == .unparsedSuffix ? prefix + Self.tokenRecord(day: ReadWorkFixture.day) + "\n" : prefix
            try Data(contents.utf8).write(to: url)
            let metadata = CostUsageScanner.codexFileMetadata(fileURL: url)
            var usage = try #require(cache.files[path])
            usage.size = metadata.size
            usage.mtimeUnixMs = metadata.mtimeUnixMs
            usage.codexScanFileId = metadata.fileId
            usage.codexScanTargetSize = metadata.size
            usage.parsedBytes = metadata.size
            let oldTime = try #require(base.calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 12)))
            usage.codexSession?.startedAtUnixMs = Int64(oldTime.timeIntervalSince1970 * 1000)
            usage.codexSession?.latestActivityUnixMs = hasCurrentEvents || kind == .unparsedSuffix
                ? cache.lastScanUnixMs : Int64(oldTime.timeIntervalSince1970 * 1000)
            usage.codexJSONLResumeState = nil
            usage.codexTokenIndexAnchor = nil
            let day = kind == .currentMigration ? ReadWorkFixture.day : oldDay
            usage.days = [day: [ReadWorkFixture.model: [40, 8, 12]]]
            usage.codexStandardTokens = [day: [ReadWorkFixture.model: 52]]
            usage.codexCostNanos = [day: [ReadWorkFixture.model: 4_000_000]]
            usage.codexStandardCostNanos = nil
            usage.codexPriorityCostNanos = nil
            usage.codexPrioritySurchargeNanos = nil
            usage.codexPriorityTokens = nil
            usage.codexRows = (0..<4).map { (index: Int) in
                .init(
                    day: day,
                    model: ReadWorkFixture.model,
                    turnID: "history-\(index)",
                    eventIndex: index,
                    input: 10,
                    cached: 2,
                    output: 3,
                    knownCostNanos: 1_000_000,
                    pricingModel: ReadWorkFixture.model,
                    pricingMode: "standard")
            }
            usage.codexTokenSnapshots = nil
            switch kind {
            case .unresolved, .subagent, .missingParent:
                usage.days = [:]
                usage.codexRows = []
                usage.codexStandardTokens = [:]
                usage.codexCostNanos = nil
                if kind != .subagent {
                    usage.forkedFromId = "missing-fixture-parent"
                    usage.forkBaselineDependencyKey = "missing|fixture-parent"
                }
                let buffered = CostUsageScanner.CodexBufferedFastLine(
                    lineIndex: 4,
                    ordinal: 4,
                    endOffset: metadata.size,
                    line: .tokenCount(.init(
                        timestamp: "2026-08-01T12:00:00Z",
                        model: ReadWorkFixture.model,
                        turnID: "fixture-owned-candidate",
                        last: .init(input: 10, cached: 2, output: 3),
                        total: .init(input: 110, cached: 22, output: 33))))
                if kind == .unresolved { usage.codexBufferedUnresolvedForkLines = [buffered] }
                if kind == .subagent { usage.codexBufferedSubagentLines = [buffered] }
            case .incompleteCost: usage.codexCostCacheComplete = false
            case .unknownCost: usage.codexCostCacheComplete = nil
            case .unparsedSuffix:
                usage.parsedBytes = Int64(prefix.utf8.count)
                usage.codexScanComplete = false
            case .staleParser: usage.codexParserRevision = nil
            case .historical, .currentMigration: break
            }
            cache.files[path] = usage
            cache.days = [:]
            for file in cache.files
                .values
            {
                CostUsageScanner.applyFileDays(cache: &cache, fileDays: file.days, sign: 1)
            }
            cache.codexScanCatchUpPending = true
            cache.codexScanInventoryPaths = nil
            let roots = CostUsageScanner.codexSessionsRoots(options: base.options)
                .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }.sorted()
            let queue = [.staleParser, .unparsedSuffix].contains(kind) ? [] : [path]
            cache.codexActiveLookbackState = .init(
                scanSinceKey: base.range.scanSinceKey,
                rootPaths: roots,
                completedRootPaths: roots,
                pendingFilePaths: queue,
                legacyRecursivePendingRootPaths: [],
                completedCurrentWindowRootPaths: roots,
                completedCurrentWindowFlatRootPaths: roots,
                cacheWideMigrationQueueActive: true)
            var previousCache = base.canonical
            previousCache.lastScanUnixMs -= 60000
            self.previousTime = Date(timeIntervalSince1970: Double(previousCache.lastScanUnixMs) / 1000)
            if retainedReport {
                cache.codexPreviousReport = CostUsageCodexPreviousReport(
                    report: .init(data: [.init(
                        date: ReadWorkFixture.day,
                        inputTokens: 10,
                        outputTokens: 3,
                        totalTokens: 13,
                        costUSD: nil,
                        modelsUsed: [ReadWorkFixture.model],
                        modelBreakdowns: nil)], summary: nil),
                    cache: previousCache,
                    reportSinceKey: base.range.sinceKey,
                    reportUntilKey: base.range.untilKey)
            }
            CostUsageStoreAccess.replace(cacheRoot: base.env.cacheRoot, cache: cache, calendar: base.calendar)
            self.base = base
            self.pendingURL = url
        } catch {
            base.remove()
            throw error
        }
    }

    private static func tokenRecord(day: String) -> String {
        """
        {"type":"event_msg","timestamp":"\(day)T12:00:00Z","payload":{"type":"token_count",\
        "info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3}}}}
        """
    }

    func strictSnapshot() async -> CostUsageFetcher.CachedCodexTokenSnapshotResult? {
        await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: self.base.now,
            historyDays: 1,
            requireCompleteHistory: true,
            scannerOptions: self.base.options)
    }
}
#endif
