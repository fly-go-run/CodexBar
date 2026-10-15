import Foundation
import Observation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct WidgetSnapshotDedupeTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(left: Double) -> WidgetSnapshot.ProviderEntry {
        WidgetSnapshot.ProviderEntry(
            provider: .claude,
            updatedAt: self.date,
            primary: RateWindow(usedPercent: 100 - left, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
    }

    private func snapshot(left: Double, generatedAt: Date) -> WidgetSnapshot {
        WidgetSnapshot(entries: [self.entry(left: left)], generatedAt: generatedAt)
    }

    private func makeStore() -> UsageStore {
        let settings = testSettingsStore(
            suiteName: "WidgetSnapshotDedupeTests", userDefaults: InMemoryUserDefaults())
        settings.providerDetectionCompleted = true
        settings.setProviderEnabled(provider: .claude, metadata: ProviderDefaults.metadata[.claude]!, enabled: true)
        settings.setProviderEnabled(provider: .codex, metadata: ProviderDefaults.metadata[.codex]!, enabled: false)
        return UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
    }

    @Test
    func `fingerprint ignores the generation time but not the content`() throws {
        let first = try #require(UsageStore.widgetSnapshotFingerprint(self.snapshot(left: 40, generatedAt: self.date)))
        let later = try #require(UsageStore.widgetSnapshotFingerprint(
            self.snapshot(left: 40, generatedAt: self.date.addingTimeInterval(30))))
        let changed = try #require(UsageStore.widgetSnapshotFingerprint(
            self.snapshot(left: 39, generatedAt: self.date)))

        #expect(first == later)
        #expect(first != changed)
    }

    @Test
    func `unchanged snapshots are skipped until they age out`() {
        let fingerprint = Data("fingerprint".utf8)
        let previous = (fingerprint: fingerprint, queuedAt: self.date)
        let maxAge = UsageStore.widgetSnapshotMaximumSkipAge

        #expect(UsageStore.canSkipWidgetSnapshotWrite(
            fingerprint: fingerprint, previous: previous, now: self.date.addingTimeInterval(1)))
        #expect(!UsageStore.canSkipWidgetSnapshotWrite(
            fingerprint: Data("other".utf8), previous: previous, now: self.date.addingTimeInterval(1)))
        #expect(!UsageStore.canSkipWidgetSnapshotWrite(
            fingerprint: fingerprint, previous: previous, now: self.date.addingTimeInterval(maxAge)))
        #expect(!UsageStore.canSkipWidgetSnapshotWrite(
            fingerprint: fingerprint, previous: previous, now: self.date.addingTimeInterval(-1)))
        #expect(!UsageStore.canSkipWidgetSnapshotWrite(fingerprint: fingerprint, previous: nil, now: self.date))
        #expect(!UsageStore.canSkipWidgetSnapshotWrite(fingerprint: nil, previous: previous, now: self.date))
    }

    @Test
    func `repeated persists write once until the widget content changes`() async {
        let store = self.makeStore()
        var saved: [WidgetSnapshot] = []
        store._test_widgetSnapshotSaveOverride = { saved.append($0) }

        for reason in ["first", "second", "third"] {
            store.persistWidgetSnapshot(reason: reason)
            await store.widgetSnapshotPersistTask?.value
        }
        #expect(saved.count == 1)

        store.snapshots[.claude] = UsageSnapshot(
            primary: RateWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: self.date)
        store.persistWidgetSnapshot(reason: "usage changed")
        await store.widgetSnapshotPersistTask?.value
        #expect(saved.count == 2)

        store.persistWidgetSnapshot(reason: "usage unchanged")
        await store.widgetSnapshotPersistTask?.value
        #expect(saved.count == 2)
    }

    @Test
    func `a token output speed result invalidates the open menu`() {
        let store = self.makeStore()
        let invalidated = InvalidationFlag()
        withObservationTracking {
            _ = store.menuObservationToken
        } onChange: {
            invalidated.value = true
        }
        let end = self.date
        let sample = TokenOutputSpeedSample(
            model: "claude-sonnet-4-5",
            outputTokens: 500,
            startedAt: end.addingTimeInterval(-10),
            completedAt: end)

        store.tokenOutputSpeeds[.claude] = TokenOutputSpeedSnapshot(samples: [sample], now: end)

        #expect(invalidated.value)
    }
}

private final class InvalidationFlag: @unchecked Sendable {
    var value = false
}
