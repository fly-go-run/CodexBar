import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarTestSupport

extension CostUsageStoreReadWorkTests {
    @Test(arguments: [
        CodexCurrentWindowFixture.Kind.unresolved, .subagent, .missingParent, .incompleteCost, .unknownCost,
        .unparsedSuffix, .staleParser,
    ])
    func `old started incomplete sources cannot establish a current window`(
        _ kind: CodexCurrentWindowFixture.Kind) async throws
    {
        let fixture = try CodexCurrentWindowFixture(kind: kind)
        defer { fixture.base.remove() }
        let before = await fixture.base.store.readSnapshot()
        let bytes = try Data(contentsOf: fixture.pendingURL)
        let roots = CostUsageScanner.codexRootsFingerprint(options: fixture.base.options)
        for purpose in [CostUsageStoreReadPurpose.activity, .report] {
            let view = fixture.base.store.syncLoadCodexReadView(calendar: fixture.base.calendar, purpose: purpose)
            #expect(!view.historyCoverageIsEstablished(range: fixture.base.range, rootsFingerprint: roots))
        }
        let cached = try #require(await fixture.base.cachedSnapshot())
        #expect(cached.snapshot.last30DaysTokens == 13)
        #expect(cached.snapshot.updatedAt == fixture.previousTime)
        #expect(cached.staleSnapshotUpdatedAt == fixture.previousTime)
        #expect(await fixture.strictSnapshot() == nil)
        #expect(await fixture.base.store.readSnapshot() == before)
        #expect(try Data(contentsOf: fixture.pendingURL) == bytes)
    }

    @Test
    func `historical bookkeeping permits a measured current window without completing the scan`() async throws {
        let fixture = try CodexCurrentWindowFixture(kind: .historical)
        defer { fixture.base.remove() }
        let cached = try #require(await fixture.strictSnapshot())
        #expect(cached.snapshot.last30DaysTokens == 52)
        #expect(cached.snapshot.updatedAt == fixture.base.now)
        #expect(cached.lastRefreshAt == fixture.base.now)
        #expect(cached.staleSnapshotUpdatedAt == nil)
        let status = await CostUsageFetcher(scannerOptions: fixture.base.options).codexScanCatchUpStatus()
        #expect(status.pending)
    }

    @Test(arguments: ["session", "head", "idle"])
    func `pending session discovery blocks publication while an idle index permits it`(work: String) async throws {
        let fixture = try CodexCurrentWindowFixture(kind: .historical)
        defer { fixture.base.remove() }
        #expect(await fixture.strictSnapshot() != nil)
        var cache = CostUsageStoreAccess.read(
            cacheRoot: fixture.base.env.cacheRoot, calendar: fixture.base.calendar)
        let roots = try #require(cache.roots).keys.sorted()
        cache.codexSessionDiscovery = .init(
            roots: roots,
            directoryStamps: [:],
            directoryPaths: roots,
            nextDirectoryIndex: 0,
            filePaths: [fixture.pendingURL.path],
            nextFileIndex: 0,
            fileStamps: [:],
            headScan: work == "head" ? .init(path: fixture.pendingURL.path, offset: 0) : nil,
            filePathBySessionId: [:],
            missingSessionIds: ["confirmed-missing-parent"],
            pendingSessionIds: work == "session" ? ["pending-fixture-parent"] : [],
            validationDirectoryIndex: 0,
            isComplete: false)
        CostUsageStoreAccess.replace(
            cacheRoot: fixture.base.env.cacheRoot, cache: cache, calendar: fixture.base.calendar)
        let before = await fixture.base.store.readSnapshot()
        let bytes = try Data(contentsOf: fixture.pendingURL)
        let strict = await fixture.strictSnapshot()
        if work == "idle" {
            #expect(strict?.snapshot.last30DaysTokens == 52)
        } else {
            #expect(strict == nil)
            let retained = try #require(await fixture.base.cachedSnapshot())
            #expect(retained.snapshot.last30DaysTokens == 13)
            #expect(retained.staleSnapshotUpdatedAt == fixture.previousTime)
        }
        #expect(await fixture.base.store.readSnapshot() == before)
        #expect(try Data(contentsOf: fixture.pendingURL) == bytes)
        let status = await CostUsageFetcher(scannerOptions: fixture.base.options).codexScanCatchUpStatus()
        #expect(status.pending)
        cache.codexSessionDiscovery?.pendingSessionIds = []
        cache.codexSessionDiscovery?.headScan = nil
        CostUsageStoreAccess.replace(
            cacheRoot: fixture.base.env.cacheRoot, cache: cache, calendar: fixture.base.calendar)
        #expect(await fixture.strictSnapshot()?.snapshot.last30DaysTokens == 52)
    }

    @Test
    func `a retained activity view keeps its day evidence when satisfying a status read`() throws {
        let fixture = try CodexCurrentWindowFixture(kind: .historical)
        defer { fixture.base.remove() }
        let roots = CostUsageScanner.codexRootsFingerprint(options: fixture.base.options)
        let cold = fixture.base.store.syncLoadCodexReadView(calendar: fixture.base.calendar, purpose: .status)
        #expect(!cold.historyCoverageIsEstablished(range: fixture.base.range, rootsFingerprint: roots))
        let activity = fixture.base.store.syncLoadCodexReadView(calendar: fixture.base.calendar, purpose: .activity)
        #expect(activity.historyCoverageIsEstablished(range: fixture.base.range, rootsFingerprint: roots))
        let retained = fixture.base.store.syncLoadCodexReadView(calendar: fixture.base.calendar, purpose: .status)
        #expect(retained.historyCoverageIsEstablished(range: fixture.base.range, rootsFingerprint: roots))
    }

    @Test
    func `unresolved work without a retained report stays explicitly incomplete`() async throws {
        let fixture = try CodexCurrentWindowFixture(kind: .unresolved, retainedReport: false)
        defer { fixture.base.remove() }
        let cached = try #require(await fixture.base.cachedSnapshot())
        #expect(cached.snapshot.last30DaysTokens == 52)
        #expect(!cached.snapshot.historyCoverageIsEstablished)
        #expect(await fixture.strictSnapshot() == nil)
    }

    @Test
    func `the final report rechecks readiness after activity evidence was accepted`() async throws {
        let fixture = try CodexCurrentWindowFixture(kind: .historical)
        defer { fixture.base.remove() }
        #expect(await fixture.strictSnapshot() != nil)
        let writer = try BaselineSQLiteConnection(url: fixture.base.store.databaseURL)
        let recorder = CostUsageStoreReadWorkRecorder(databaseURL: fixture.base.store.databaseURL)
        let writes = LockIsolated(0)
        let inTransaction = LockIsolated(-1)
        let failure = LockIsolated<String?>(nil)
        var recordingHooks = CostUsageStoreTestHooks.current
        recordingHooks.readWorkRecorder = recorder
        try await CostUsageStoreTestHooks.$current.withValue(recordingHooks) {
            var hooks = CostUsageStoreTestHooks.current
            hooks.codexCatchUpReconciliationVisit = {
                let work = recorder.snapshot()
                guard work.readViewConversions == 2, writes.value == 0 else { return }
                writes.setValue(1)
                inTransaction.setValue(work.readViewConversionsInTransaction)
                do {
                    try writer.execute("UPDATE files SET scan_complete = 0 WHERE session_id = 'fixture-session-0'")
                } catch {
                    failure.setValue(error.localizedDescription)
                }
            }

            let result = await CostUsageStoreTestHooks.$current.withValue(hooks) {
                await fixture.strictSnapshot()
            }
            let work = recorder.snapshot()
            var unrecordedHooks = CostUsageStoreTestHooks.current
            unrecordedHooks.readWorkRecorder = nil
            try await CostUsageStoreTestHooks.$current.withValue(unrecordedHooks) {
                #expect(result == nil)
                #expect(writes.value == 1)
                #expect(failure.value == nil)
                #expect(inTransaction.value == 0)
                #expect(work.readViewConversions == 3)
                #expect(work.readViewConversionsInTransaction == 0)
                #expect(work.usageRowDecodeAttempts > 0)
                #expect(work.tokenSnapshotRows == 0)
                #expect(work.bufferedLines == 0)
                #expect(work.bufferedPayloadBytes == 0)
                let retained = try #require(await fixture.base.cachedSnapshot())
                #expect(retained.snapshot.last30DaysTokens == 13)
                #expect(retained.staleSnapshotUpdatedAt == fixture.previousTime)
            }
        }
    }

    @Test
    func `status reads cannot infer current day absence from omitted aggregates`() throws {
        let fixture = try CodexCurrentWindowFixture(kind: .currentMigration)
        defer { fixture.base.remove() }
        let roots = CostUsageScanner.codexRootsFingerprint(options: fixture.base.options)
        for purpose in [CostUsageStoreReadPurpose.status, .activity, .report] {
            let view = fixture.base.store.syncLoadCodexReadView(calendar: fixture.base.calendar, purpose: purpose)
            #expect(!view.historyCoverageIsEstablished(range: fixture.base.range, rootsFingerprint: roots))
        }
    }
}
