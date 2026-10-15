// SwiftBuild also compiles this test-support target for `swift build -c release`,
// where CodexBarCore is not built for testing.
#if DEBUG
import Foundation
import Testing
@testable import CodexBarCore

struct ReadWorkFixture {
    static let day = "2026-08-01"
    static let model = "gpt-5.4"
    let env: CostUsageTestEnvironment
    let calendar: Calendar
    let now: Date
    let options: CostUsageScanner.Options
    let store: CostUsageStore
    let canonical: CostUsageCache
    let fileCount: Int
    let rowCount: Int
    let incomplete: Bool

    init(fileCount: Int, rowsPerFile: Int, incomplete: Bool = false) throws {
        let env = try CostUsageTestEnvironment()
        do {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
            let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
            let trace = env.root.appendingPathComponent("missing-trace.sqlite")
            let options = CostUsageScanner.Options(
                codexSessionsRoot: env.codexSessionsRoot,
                claudeProjectsRoots: [env.claudeProjectsRoot],
                cacheRoot: env.cacheRoot,
                codexTraceDatabaseURL: trace,
                calendar: calendar)
            let range = CostUsageScanner.CostUsageDayRange(since: now, until: now, calendar: calendar)
            var cache = CostUsageCache()
            cache.scanSinceKey = range.scanSinceKey
            cache.scanUntilKey = range.scanUntilKey
            cache.timeZoneIdentifier = calendar.timeZone.identifier
            cache.lastScanUnixMs = Int64(now.timeIntervalSince1970 * 1000)
            cache.roots = CostUsageScanner.codexRootsFingerprint(options: options)
            cache.codexPricingKey = CostUsageScanner.codexPricingKey(modelsDevArtifact: nil)
            cache.codexPriorityMetadataKey = "missing:\(trace.standardizedFileURL.path)"
            cache.codexProjectMetadataVersion = CostUsageScanner.codexProjectMetadataVersion
            for index in 0..<fileCount {
                let url = env.codexSessionsRoot.appendingPathComponent("fixture-\(index).jsonl")
                cache.files[url.path] = try Self.usage(
                    url: url, index: index, rowCount: rowsPerFile, incomplete: incomplete && index == 0)
            }
            cache.days = [Self.day: [Self.model: [
                fileCount * rowsPerFile * 10,
                fileCount * rowsPerFile * 2,
                fileCount * rowsPerFile * 3,
            ]]]
            cache.codexScanCatchUpPending = incomplete
            cache.codexScanCompletedFiles = fileCount - (incomplete ? 1 : 0)
            cache.codexScanTotalFiles = fileCount
            cache.codexScanProcessedBytes = cache.files.values.reduce(0) { $0 + ($1.parsedBytes ?? 0) }
            cache.codexScanTotalBytes = cache.files.values.reduce(0) { $0 + $1.size }
            cache.codexScanInventoryPaths = cache.files.keys.sorted()
            let store = CostUsageStore(cacheRoot: env.cacheRoot)
            let saved = store.syncSaveCodexCache(
                cache,
                calendar: calendar,
                requestedScanWindow: (sinceKey: range.scanSinceKey, untilKey: range.scanUntilKey))
            try #require(!saved.catchUpRequired)
            self.env = env
            self.calendar = calendar
            self.now = now
            self.options = options
            self.store = store
            self.canonical = store.syncLoadCodexCache(calendar: calendar)
            self.fileCount = fileCount
            self.rowCount = fileCount * rowsPerFile
            self.incomplete = incomplete
            #expect(self.canonical.files.count == fileCount)
            #expect(self.canonical.files.values.reduce(0) { $0 + ($1.codexRows?.count ?? 0) } == self.rowCount)
            #expect(self.canonical.files.values.allSatisfy { !CostUsageScanner.needsCodexPricingMetadata($0) })
        } catch {
            env.cleanup()
            throw error
        }
    }

    func save(_ cache: CostUsageCache) -> CostUsageStoreBudgetResult {
        self.store.syncSaveCodexCache(
            cache,
            calendar: self.calendar,
            requestedScanWindow: (sinceKey: self.canonical.scanSinceKey!, untilKey: self.canonical.scanUntilKey!),
            skipIdenticalContent: true)
    }

    func cachedSnapshot(
        options: CostUsageScanner.Options? = nil,
        historyDays: Int = 1,
        details: Bool = false) async -> CostUsageFetcher.CachedCodexTokenSnapshotResult?
    {
        if details {
            return await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
                now: self.now,
                historyDays: historyDays,
                scannerOptions: options ?? self.options)
        }
        return await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: self.now,
            historyDays: historyDays,
            includeProjectAndSessionBreakdowns: false,
            scannerOptions: options ?? self.options)
    }

    func expectStatus(_ status: CostUsageFetcher.CodexScanCatchUpStatus) {
        #expect(status.pending == self.incomplete)
        #expect(status.totalFiles == self.fileCount)
        #expect(status.completedFiles == self.fileCount - (self.incomplete ? 1 : 0))
        #expect(status.processedBytes == self.canonical.codexScanProcessedBytes)
        #expect(status.totalBytes == self.canonical.codexScanTotalBytes)
        #expect(status.progressKey == CostUsageFetcher.codexScanProgressKey(
            cache: self.canonical, scopedFiles: self.canonical.files))
    }

    func expectSnapshot(_ result: CostUsageFetcher.CachedCodexTokenSnapshotResult?, details: Bool = false) throws {
        let result = try #require(result)
        #expect(result.snapshot.historyCoverageIsEstablished == !self.incomplete)
        #expect(result.snapshot.detailsAreComplete == (details && !self.incomplete))
        #expect(result.snapshot.last30DaysTokens == self.rowCount * 13)
        #expect(result.snapshot.sessionTokens == self.rowCount * 13)
        #expect(result.snapshot.daily.count == 1)
        let cost = try #require(result.snapshot.last30DaysCostUSD)
        #expect(abs(cost - Double(self.rowCount) * 0.001) < 0.000000001)
        if details {
            let range = CostUsageScanner.CostUsageDayRange(since: self.now, until: self.now, calendar: self.calendar)
            #expect(result.snapshot.projects == self.fullCachedSnapshot(cache: self.canonical).projects)
            #expect(result.snapshot.sessions == CostUsageScanner.buildCodexSessionBreakdownsFromCache(
                cache: self.canonical,
                range: range,
                modelsDevCacheRoot: self.env.cacheRoot,
                sessionRoots: CostUsageScanner.codexSessionsRoots(options: self.options)))
            #expect(result.snapshot.projects.count == 1)
            #expect(result.snapshot.sessions.count == self.fileCount)
            #expect(result.snapshot.projects.first?.totalTokens == self.rowCount * 13)
            #expect(result.snapshot.sessions.allSatisfy { $0.totalTokens == self.rowCount / self.fileCount * 13 })
        } else {
            #expect(result.snapshot.projects.isEmpty)
            #expect(result.snapshot.sessions.isEmpty)
        }
        #expect(result.lastRefreshAt == self.now)
        #expect(result.snapshot.updatedAt == self.now)
    }

    func remove() {
        self.env.cleanup()
    }

    private static func usage(
        url: URL,
        index: Int,
        rowCount: Int,
        incomplete: Bool) throws -> CostUsageFileUsage
    {
        let timestamp = "2026-08-01T12:00:00Z"
        let tokenLine = """
        {"type":"event_msg","timestamp":"\(timestamp)","payload":{"type":"token_count",\
        "info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3}}}}
        """
        let contents = Array(repeating: tokenLine, count: rowCount).joined(separator: "\n") + "\n"
        try Data(contents.utf8).write(to: url)
        let metadata = CostUsageScanner.codexFileMetadata(fileURL: url)
        var usage = CostUsageFileUsage(
            mtimeUnixMs: metadata.mtimeUnixMs,
            size: metadata.size,
            days: [Self.day: [Self.model: [rowCount * 10, rowCount * 2, rowCount * 3]]])
        usage.parsedBytes = metadata.size
        usage.codexScanFileId = metadata.fileId
        usage.codexScanTargetSize = metadata.size
        usage.codexScanComplete = !incomplete
        usage.sessionId = "fixture-session-\(index)"
        usage.projectPath = url.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("owned-project").path
        usage.canonicalProjectPath = usage.projectPath
        usage.codexSession = .init(sessionId: usage.sessionId, cwd: usage.projectPath, title: "Fixture \(index)")
        usage.lastCountedTotals = .init(input: rowCount * 10, cached: rowCount * 2, output: rowCount * 3)
        usage.codexCostCacheComplete = true
        usage.codexStandardTokens = [Self.day: [Self.model: rowCount * 13]]
        usage.codexTokenTimestampsMonotonic = true
        usage.codexRows = (0..<rowCount).map { event in
            CostUsageScanner.CodexUsageRow(
                day: Self.day,
                model: Self.model,
                turnID: "fixture-\(index)-\(event)",
                eventIndex: event,
                input: 10,
                cached: 2,
                output: 3,
                knownCostNanos: 1_000_000,
                pricingModel: Self.model,
                pricingMode: "standard")
        }
        usage.codexTurnIDs = CostUsageScanner.codexTurnIDs(rows: usage.codexRows ?? [])
        usage.codexTokenSnapshots = (0..<rowCount).map { event in
            CostUsageCodexTokenSnapshot(
                timestamp: timestamp,
                last: CostUsageCodexTotals(input: 10, cached: 2, output: 3),
                total: nil,
                endOffset: Int64((event + 1) * (tokenLine.utf8.count + 1)))
        }
        if incomplete {
            usage.codexBufferedUnresolvedForkLines = [CostUsageScanner.CodexBufferedFastLine(
                lineIndex: rowCount,
                ordinal: rowCount,
                endOffset: metadata.size,
                line: .taskStarted(turnID: "fixture-replay"))]
        }
        return usage
    }
}

extension ReadWorkFixture {
    /// The pre-projection full-load path, including the fetcher's existing merge normalization.
    /// Full details are complete only when this fixture's scan is complete.
    func fullCachedSnapshot(cache: CostUsageCache? = nil) -> CostUsageTokenSnapshot {
        let roots = CostUsageScanner.codexSessionsRoots(options: self.options)
        let full = CostUsageScanner.codexCache(
            cache ?? CostUsageStoreAccess.read(cacheRoot: self.env.cacheRoot, calendar: self.calendar), scopedTo: roots)
        return CostUsageFetcher.tokenSnapshot(
            from: .merged([self.fullReport(full)]),
            now: self.now,
            historyDays: 1,
            calendar: self.calendar,
            historyCoverageIsEstablished: !self.incomplete,
            costProvenance: .listPriceEstimate,
            projects: CostUsageFetcher.mergedProjectBreakdowns(
                CostUsageScanner.buildCodexProjectBreakdownsFromCache(
                    cache: full, range: self.range, modelsDevCacheRoot: self.env.cacheRoot)),
            sessions: CostUsageScanner.buildCodexSessionBreakdownsFromCache(
                cache: full, range: self.range, modelsDevCacheRoot: self.env.cacheRoot, sessionRoots: roots),
            detailsAreComplete: !self.incomplete,
            updatedAt: self.now)
    }

    var range: CostUsageScanner.CostUsageDayRange {
        .init(since: self.now, until: self.now, calendar: self.calendar)
    }

    func fullReport(_ cache: CostUsageCache) -> CostUsageDailyReport {
        CostUsageScanner.buildCodexReportFromCache(
            cache: cache,
            range: self.range,
            modelsDevCacheRoot: self.env.cacheRoot)
    }

    func expectProjectionParity(_ baseline: CostUsageCache) throws {
        let roots = CostUsageScanner.codexSessionsRoots(options: self.options)
        let fingerprint = CostUsageScanner.codexRootsFingerprint(options: self.options)
        let scoped = CostUsageScanner.codexCache(baseline, scopedTo: roots)
        let pending = baseline.codexScanCatchUpPending == true || scoped.files.values.contains {
            $0.codexScanComplete == false || $0.hasBufferedCodexForkRetryLines
        }
        let expectedStatus = CostUsageFetcher.CodexScanCatchUpStatus(
            pending: pending,
            progressKey: CostUsageFetcher.codexScanProgressKey(cache: baseline, scopedFiles: scoped.files),
            processedBytes: baseline.codexScanProcessedBytes ?? 0,
            totalBytes: baseline.codexScanTotalBytes ?? 0,
            completedFiles: baseline.codexScanCompletedFiles ?? 0,
            totalFiles: baseline.codexScanTotalFiles ?? 0,
            staleSnapshotUpdatedAt: pending ? baseline.codexPreviousReport?.updatedAt : nil)
        for purpose in [CostUsageStoreReadPurpose.status, .activity, .report] {
            let view = self.store.syncLoadCodexReadView(calendar: self.calendar, purpose: purpose)
            #expect(view.catchUpStatus(roots: roots, rootsFingerprint: fingerprint) == expectedStatus)
            #expect(view.previousReport(range: self.range, rootsFingerprint: fingerprint)
                == CostUsageScanner.codexPreviousReport(
                    cache: baseline,
                    range: self.range,
                    rootsFingerprint: fingerprint))
            if purpose == .activity {
                #expect(view.scoped(to: roots).days == scoped.days)
            }
            if purpose == .report {
                let report = view.scoped(to: roots).dailyReport(range: self.range, cacheRoot: self.env.cacheRoot)
                let full = self.fullReport(scoped)
                #expect(report.data == full.data)
                #expect(report.summary.map(CostUsageCodexPreviousReport.Summary.init)
                    == full.summary.map(CostUsageCodexPreviousReport.Summary.init))
                #expect(view.projects(range: self.range, cacheRoot: self.env.cacheRoot)
                    == CostUsageScanner.buildCodexProjectBreakdownsFromCache(
                        cache: baseline, range: self.range, modelsDevCacheRoot: self.env.cacheRoot))
                #expect(view.sessions(range: self.range, cacheRoot: self.env.cacheRoot, roots: roots)
                    == CostUsageScanner.buildCodexSessionBreakdownsFromCache(
                        cache: baseline,
                        range: self.range,
                        modelsDevCacheRoot: self.env.cacheRoot,
                        sessionRoots: roots))
            }
        }
    }
}
#endif
