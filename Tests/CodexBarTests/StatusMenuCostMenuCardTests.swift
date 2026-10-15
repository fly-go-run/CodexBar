import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct StatusMenuCostMenuCardTests {
    @Test
    func `cost menu omits detail text beside a history submenu`() {
        let tokenUsage = UsageMenuCardView.Model.TokenUsageSection(
            sessionLine: "Today: $74.83 - 87M tokens",
            monthLine: "Last 30 days: $4,279.64 - 5.7B tokens",
            hintLine: "Costs are estimated from local usage.",
            errorLine: "Cost refresh failed.",
            errorCopyText: nil)

        let visibleLines = StatusItemController.costMenuVisibleDetailLines(
            provider: .codex,
            tokenUsage: tokenUsage,
            hasSubmenu: true)
        #expect(visibleLines == [])
        #expect(StatusItemController.costMenuVisibleDetailLines(
            provider: .claude,
            tokenUsage: tokenUsage,
            hasSubmenu: true) == [])

        let fallbackTitle = StatusItemController.costMenuFallbackAttributedTitle(
            title: "Cost",
            visibleDetailLines: visibleLines)
        #expect(fallbackTitle.string == "Cost")
    }

    @Test
    func `cost menu preserves summary lines without history submenu`() {
        let tokenUsage = UsageMenuCardView.Model.TokenUsageSection(
            sessionLine: "Today: $74.83 - 87M tokens",
            monthLine: "Last 30 days: $4,279.64 - 5.7B tokens",
            hintLine: "Costs are estimated from local usage.",
            errorLine: "Cost refresh failed.",
            errorCopyText: nil)

        let visibleLines = StatusItemController.costMenuVisibleDetailLines(
            provider: .codex,
            tokenUsage: tokenUsage,
            hasSubmenu: false)
        #expect(visibleLines == [
            "Today: $74.83 - 87M tokens",
            "Last 30 days: $4,279.64 - 5.7B tokens",
            "Costs are estimated from local usage.",
            "Cost refresh failed.",
        ])

        let fallbackTitle = StatusItemController.costMenuFallbackAttributedTitle(
            title: "Cost",
            visibleDetailLines: visibleLines)
        #expect(fallbackTitle.string.contains("Today: $74.83 - 87M tokens"))
        #expect(fallbackTitle.string.contains("Last 30 days: $4,279.64 - 5.7B tokens"))
        #expect(fallbackTitle.string.contains("Costs are estimated from local usage."))
        #expect(fallbackTitle.string.contains("Cost refresh failed."))
    }

    @Test
    func `cost menu tooltip preserves hint and error details`() {
        let tokenUsage = UsageMenuCardView.Model.TokenUsageSection(
            sessionLine: "Today: $1.00",
            monthLine: "Last 30 days: $9.00",
            hintLine: "Costs are estimated from local usage.",
            errorLine: "Cost refresh failed.",
            errorCopyText: nil)

        #expect(StatusItemController.costMenuTooltipLines(provider: .codex, tokenUsage: tokenUsage) == [
            "Today: $1.00",
            "Last 30 days: $9.00",
            "Costs are estimated from local usage.",
            "Cost refresh failed.",
        ])
        #expect(StatusItemController.costMenuTooltipLines(provider: .claude, tokenUsage: tokenUsage) == [
            "Today: $1.00",
            "Last 30 days: $9.00",
            "Costs are estimated from local usage.",
            "Cost refresh failed.",
        ])
    }

    private func makeSettings() -> SettingsStore {
        let suite = "StatusMenuCostMenuCardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite))
    }
}
