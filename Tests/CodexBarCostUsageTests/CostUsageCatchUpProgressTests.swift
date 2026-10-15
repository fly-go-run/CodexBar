import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarTestSupport

struct CostUsageCatchUpProgressTests {
    @Test
    func `pending queue rotation alone is not progress`() {
        var cache = CostUsageCache()
        cache.codexActiveLookbackState = CostUsageCodexActiveLookbackState(
            scanSinceKey: "2026-05-10",
            rootPaths: ["/sessions"],
            pendingFilePaths: ["/sessions/a.jsonl", "/sessions/b.jsonl", "/sessions/c.jsonl"])
        let before = CostUsageFetcher.codexScanProgressKey(cache: cache, scopedFiles: [:])
        cache.codexActiveLookbackState?.pendingFilePaths = [
            "/sessions/b.jsonl",
            "/sessions/c.jsonl",
            "/sessions/a.jsonl",
        ]
        #expect(CostUsageFetcher.codexScanProgressKey(cache: cache, scopedFiles: [:]) == before)
    }

    @Test
    func `progress key includes semantic discovery cursor progress`() {
        var cache = CostUsageCache()
        cache.codexSessionDiscovery = CostUsageCodexSessionDiscovery(
            roots: ["/sessions"],
            generation: "generation-1",
            directoryStamps: [:],
            directoryPaths: ["/sessions/2026", "/sessions/2026/08"],
            nextDirectoryIndex: 2,
            filePaths: [],
            nextFileIndex: 0,
            fileStamps: [:],
            headScan: nil,
            filePathBySessionId: [:],
            missingSessionIds: ["missing-parent"],
            pendingSessionIds: [],
            validationDirectoryIndex: 0,
            isComplete: true)

        let initial = CostUsageFetcher.codexScanProgressKey(cache: cache, scopedFiles: [:])
        cache.codexSessionDiscovery?.validationDirectoryIndex = 1
        let advanced = CostUsageFetcher.codexScanProgressKey(cache: cache, scopedFiles: [:])

        #expect(advanced != initial)
    }

    @Test
    func `progress tracks stable membership but ignores complete live appends`() {
        let path = "/sessions/live.jsonl"
        let complete = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1,
            size: 100,
            days: [:],
            parsedBytes: 100,
            codexScanFileId: "1:1",
            codexScanComplete: true)
        let empty = CostUsageFetcher.codexScanProgressKey(
            cache: CostUsageCache(),
            scopedFiles: [:])
        let initial = CostUsageFetcher.codexScanProgressKey(
            cache: CostUsageCache(),
            scopedFiles: [path: complete])
        var appended = complete
        appended.size = 125
        appended.parsedBytes = 125
        let afterLiveAppend = CostUsageFetcher.codexScanProgressKey(
            cache: CostUsageCache(),
            scopedFiles: [path: appended])

        #expect(initial != empty)
        #expect(afterLiveAppend == initial)
    }

    @Test
    func `progress tracks unfinished file bytes`() {
        let path = "/sessions/unfinished.jsonl"
        var unfinished = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1,
            size: 125,
            days: [:],
            parsedBytes: 110,
            codexScanFileId: "1:1",
            codexScanComplete: false)
        let unfinishedInitial = CostUsageFetcher.codexScanProgressKey(
            cache: CostUsageCache(),
            scopedFiles: [path: unfinished])
        unfinished.parsedBytes = 120
        let unfinishedAdvanced = CostUsageFetcher.codexScanProgressKey(
            cache: CostUsageCache(),
            scopedFiles: [path: unfinished])

        #expect(unfinishedAdvanced != unfinishedInitial)
    }

    @Test
    func `progress tracks a resumable generation target change`() {
        let path = "/sessions/unfinished.jsonl"
        var unfinished = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1,
            size: 200,
            days: [:],
            parsedBytes: 100,
            codexScanFileId: "1:1",
            codexScanTargetSize: 150,
            codexScanComplete: false)
        let initial = CostUsageFetcher.codexScanProgressKey(
            cache: CostUsageCache(),
            scopedFiles: [path: unfinished])
        unfinished.codexScanTargetSize = 175
        let retargeted = CostUsageFetcher.codexScanProgressKey(
            cache: CostUsageCache(),
            scopedFiles: [path: unfinished])

        #expect(retargeted != initial)
    }

    @Test
    func `progress tracks completed aggregate for existing file backlog`() {
        let path = "/sessions/existing.jsonl"
        let usage = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1,
            size: 125,
            days: [:],
            parsedBytes: 125,
            codexScanFileId: "1:1",
            codexScanComplete: true)
        var before = CostUsageCache()
        before.codexScanCompletedFiles = 0
        var after = before
        after.codexScanCompletedFiles = 1

        #expect(CostUsageFetcher.codexScanProgressKey(cache: after, scopedFiles: [path: usage])
            != CostUsageFetcher.codexScanProgressKey(cache: before, scopedFiles: [path: usage]))
    }

    @Test
    func `completed buffered appends do not hide a stalled dependency`() {
        let path = "/sessions/fork.jsonl"
        let line = CostUsageScanner.CodexBufferedFastLine(
            lineIndex: 1,
            ordinal: nil,
            line: .interAgentCommunication(triggerTurn: false))
        let buffered = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1,
            size: 100,
            days: [:],
            parsedBytes: 100,
            forkedFromId: "missing-parent",
            codexScanFileId: "1:1",
            codexScanComplete: true,
            codexBufferedUnresolvedForkLines: [line])
        let initial = CostUsageFetcher.codexScanProgressKey(
            cache: CostUsageCache(),
            scopedFiles: [path: buffered])

        var appended = buffered
        appended.size = 125
        appended.parsedBytes = 125
        appended.codexBufferedUnresolvedForkLines = [line, line]
        let afterAppend = CostUsageFetcher.codexScanProgressKey(
            cache: CostUsageCache(),
            scopedFiles: [path: appended])

        var dependencyResolved = appended
        dependencyResolved.forkBaselineDependencyKey = "parent:resolved"
        let afterDependencyChange = CostUsageFetcher.codexScanProgressKey(
            cache: CostUsageCache(),
            scopedFiles: [path: dependencyResolved])

        var replayed = dependencyResolved
        replayed.codexBufferedUnresolvedForkLines = nil
        let afterReplay = CostUsageFetcher.codexScanProgressKey(
            cache: CostUsageCache(),
            scopedFiles: [path: replayed])

        #expect(afterAppend == initial)
        #expect(afterDependencyChange != afterAppend)
        #expect(afterReplay != afterDependencyChange)
    }

    @Test
    func `progress key includes active lookback cursor and ignores dictionary insertion order`() {
        var initialCache = CostUsageCache()
        initialCache.codexActiveLookbackState = CostUsageCodexActiveLookbackState(
            scanSinceKey: "2026-07-01",
            rootPaths: ["/sessions", "/archived_sessions"],
            nextDayKeyByRoot: [
                "/sessions": "2026-07-02",
                "/archived_sessions": "2026-07-03",
            ])
        var advancedCache = initialCache
        advancedCache.codexActiveLookbackState?.nextDayKeyByRoot["/sessions"] = "2026-07-01"

        let first = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1,
            size: 10,
            days: [:],
            parsedBytes: 10,
            codexScanFileId: "1:1",
            codexScanComplete: true)
        let second = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: 1,
            size: 20,
            days: [:],
            parsedBytes: 10,
            codexScanFileId: "2:2",
            codexScanComplete: false)
        var forward: [String: CostUsageFileUsage] = [:]
        forward["/sessions/a.jsonl"] = first
        forward["/sessions/b.jsonl"] = second
        var reverse: [String: CostUsageFileUsage] = [:]
        reverse["/sessions/b.jsonl"] = second
        reverse["/sessions/a.jsonl"] = first

        let initial = CostUsageFetcher.codexScanProgressKey(cache: initialCache, scopedFiles: forward)
        let advanced = CostUsageFetcher.codexScanProgressKey(cache: advancedCache, scopedFiles: forward)
        let reordered = CostUsageFetcher.codexScanProgressKey(cache: initialCache, scopedFiles: reverse)

        #expect(advanced != initial)
        #expect(reordered == initial)
    }

    @Test
    func `progress key includes bounded current window directory cursor`() {
        var initialCache = CostUsageCache()
        initialCache.codexActiveLookbackState = CostUsageCodexActiveLookbackState(
            scanSinceKey: "2026-07-01",
            rootPaths: ["/sessions"],
            currentWindowDirectoryOffsetByRoot: ["/sessions": 512])
        var advancedCache = initialCache
        advancedCache.codexActiveLookbackState?.currentWindowDirectoryOffsetByRoot?["/sessions"] = 1024

        #expect(CostUsageFetcher.codexScanProgressKey(cache: advancedCache, scopedFiles: [:])
            != CostUsageFetcher.codexScanProgressKey(cache: initialCache, scopedFiles: [:]))
    }

    @Test
    func `progress key changes when exact proof inventory is installed`() {
        var beforeProof = CostUsageCache()
        beforeProof.codexScanCatchUpPending = true
        beforeProof.codexScanCompletedFiles = 1
        var afterProof = beforeProof
        afterProof.codexScanInventoryPaths = ["/sessions/complete.jsonl"]

        #expect(CostUsageFetcher.codexScanProgressKey(cache: afterProof, scopedFiles: [:])
            != CostUsageFetcher.codexScanProgressKey(cache: beforeProof, scopedFiles: [:]))
    }
}
