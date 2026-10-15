import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct TokenOutputSpeedSchedulingTests {
    private actor ScanGate {
        private(set) var scopes: [String?] = []
        private var waiters: [CheckedContinuation<Void, Never>] = []

        /// Returns the 1-based number of this scan once it is released.
        func enter(scope: String?) async -> Int {
            self.scopes.append(scope)
            let number = self.scopes.count
            await withCheckedContinuation { self.waiters.append($0) }
            return number
        }

        func releaseNext() {
            guard !self.waiters.isEmpty else { return }
            self.waiters.removeFirst().resume()
        }

        var startedCount: Int {
            self.scopes.count
        }
    }

    private let end = Date(timeIntervalSince1970: 1_700_000_000)

    private func speed(tokens: Int) -> TokenOutputSpeedSnapshot {
        TokenOutputSpeedSnapshot(
            samples: [TokenOutputSpeedSample(
                model: "gpt-5",
                outputTokens: tokens,
                startedAt: self.end.addingTimeInterval(-10),
                completedAt: self.end)],
            now: self.end)
    }

    private func makeStore() -> UsageStore {
        let settings = testSettingsStore(
            suiteName: "TokenOutputSpeedSchedulingTests", userDefaults: InMemoryUserDefaults())
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        store.tokenOutputSpeedMinInterval = 0.05
        return store
    }

    private func waitUntil(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<300 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    @Test
    func `a request during a running scan triggers one trailing scan`() async {
        let store = self.makeStore()
        let gate = ScanGate()
        let results = [self.speed(tokens: 500), self.speed(tokens: 900)]
        store._test_tokenOutputSpeedScan = { _, scope in
            let number = await gate.enter(scope: scope)
            return results[number - 1]
        }
        let id = UsageProvider.codex.instanceID

        store.scheduleTokenOutputSpeedRefresh(for: .codex)
        #expect(await self.waitUntil { await gate.startedCount == 1 })
        store.scheduleTokenOutputSpeedRefresh(for: .codex)
        store.scheduleTokenOutputSpeedRefresh(for: .codex)
        await gate.releaseNext()

        // Both requests collapse into exactly one more scan, which waits out the interval floor.
        #expect(await self.waitUntil { await gate.startedCount == 2 })
        await gate.releaseNext()
        #expect(await self.waitUntil { store.tokenOutputSpeedScanTasks[id] == nil })
        #expect(await gate.startedCount == 2)
        #expect(store.tokenOutputSpeeds[id]?.models.first?.outputTokens == 900)
    }

    @Test
    func `a result for a scope that is no longer active is discarded`() async {
        let store = self.makeStore()
        let gate = ScanGate()
        var home: String? = "/homes/a"
        store._test_tokenOutputSpeedCodexHomePath = { _ in home }
        let (first, second) = (self.speed(tokens: 500), self.speed(tokens: 900))
        store._test_tokenOutputSpeedScan = { _, scope in
            _ = await gate.enter(scope: scope)
            return scope == "/homes/a" ? first : second
        }
        let id = UsageProvider.codex.instanceID

        store.scheduleTokenOutputSpeedRefresh(for: .codex)
        #expect(await self.waitUntil { await gate.startedCount == 1 })
        home = "/homes/b"
        store.scheduleTokenOutputSpeedRefresh(for: .codex)
        await gate.releaseNext()

        // The first scan finished for the old home: nothing may be published from it.
        #expect(await self.waitUntil { await gate.startedCount == 2 })
        #expect(store.tokenOutputSpeeds[id] == nil)
        await gate.releaseNext()
        #expect(await self.waitUntil { store.tokenOutputSpeedScanTasks[id] == nil })
        #expect(await gate.scopes == ["/homes/a", "/homes/b"])
        #expect(store.tokenOutputSpeeds[id]?.models.first?.outputTokens == 900)
    }
}
