import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct ClaudeScopedOnlyMetricTests {
    private static let now = Date(timeIntervalSince1970: 1_790_726_400)

    @Test
    func `scoped token ignores windows without measured usage`() {
        let unknown = NamedRateWindow(
            id: "claude-weekly-scoped-example",
            title: "Example only",
            window: RateWindow(usedPercent: 0, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            usageKnown: false)
        let snapshot = UsageSnapshot(primary: nil, secondary: nil, extraRateWindows: [unknown], updatedAt: Self.now)
        #expect(MenuBarLayoutSemanticWindowResolver.scopedWeeklyNamedWindow(snapshot: snapshot) == nil)
    }

    @Test(arguments: [MenuBarMetricPreference.automatic, .primaryAndSecondary], [false, true])
    func `scoped weekly payload supplies the only measured menu bar metric`(
        preference: MenuBarMetricPreference, withSpendLimit: Bool) throws
    {
        let snapshot = try Self.snapshot(withSpendLimit: withSpendLimit)
        let scoped = try #require(MenuBarLayoutSemanticWindowResolver.scopedWeeklyNamedWindow(snapshot: snapshot))
        #expect(scoped.window.usedPercent == 6)
        let selected = MenuBarMetricWindowResolver.rateWindow(
            preference: preference, provider: .claude, snapshot: snapshot, supportsAverage: false, now: Self.now)
        #expect(selected == scoped.window)
        #expect(MenuBarMetricWindowResolver.claudeSpendLimitWindow(snapshot: snapshot) == nil)
    }

    @MainActor
    private static func renderData(
        snapshot: UsageSnapshot,
        scoped: NamedRateWindow?,
        automatic: RateWindow?) -> MenuBarLayoutRenderData
    {
        MenuBarLayoutRenderData(
            provider: .claude,
            iconKey: "synthetic-claude-scoped",
            providerName: "Claude",
            accountLabel: nil,
            laneLabels: MenuBarLayoutLaneLabels(provider: .claude, snapshot: snapshot),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            session: nil,
            weekly: nil,
            scopedWeekly: MenuBarLayoutRenderWindow(scoped?.window),
            scopedWeeklyTitle: scoped?.title,
            automatic: MenuBarLayoutRenderWindow(automatic),
            automaticText: nil,
            sessionPace: nil,
            weeklyPace: nil,
            automaticPace: nil,
            runsOut: nil,
            balance: nil,
            costToday: nil,
            cost30d: nil,
            metrics: .unavailable)
    }

    private static func snapshot(withSpendLimit: Bool) throws -> UsageSnapshot {
        let data = Data(#"""
        {"five_hour": null, "seven_day": null, "limits": [
          {"kind": "weekly_scoped", "group": "weekly", "percent": 6,
           "resets_at": "2026-10-07T09:00:00Z",
           "scope": {"model": {"display_name": "Fable"}}, "is_active": true}
        ]}
        """#.utf8)
        let parsed = try ClaudeWebAPIFetcher._parseUsageResponseForTesting(data)
        let cost = ProviderCostSnapshot(
            used: 20,
            limit: 100,
            currencyCode: "USD",
            period: "Monthly",
            updatedAt: Self.now)
        return UsageSnapshot(
            primary: ClaudeUsageFetcher.webPrimaryWindow(from: parsed),
            secondary: nil,
            extraRateWindows: parsed.extraRateWindows,
            providerCost: withSpendLimit ? cost : nil,
            updatedAt: Self.now)
    }
}
