import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarWidget

struct ProviderPresentationPolicyCharacterizationTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func `missing secondary lane reservation is claude only`() {
        for provider in UsageProvider.allCases {
            let actual = ProviderDescriptorRegistry.descriptor(for: provider)
                .presentation.reservesMissingSecondaryIconLane
            #expect(actual == (provider == .claude), "Unexpected missing-lane policy for \(provider.rawValue)")
        }
    }

    private func snapshot(
        primary: RateWindow?,
        secondary: RateWindow? = nil,
        tertiary: RateWindow? = nil) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            updatedAt: self.now)
    }

    private func history(_ name: PlanUtilizationSeriesName, minutes: Int) -> PlanUtilizationSeriesHistory {
        PlanUtilizationSeriesHistory(
            name: name,
            windowMinutes: minutes,
            entries: [PlanUtilizationHistoryEntry(capturedAt: self.now, usedPercent: 10, resetsAt: nil)])
    }

    private func widgetEntry(
        provider: UsageProvider,
        primary: RateWindow? = nil,
        secondary: RateWindow? = nil,
        usageRows: [WidgetSnapshot.WidgetUsageRowSnapshot]? = nil) -> WidgetSnapshot.ProviderEntry
    {
        WidgetSnapshot.ProviderEntry(
            provider: provider,
            updatedAt: self.now,
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            usageRows: usageRows,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
    }
}
