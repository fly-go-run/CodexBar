import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct DashboardReportedCostTests {
    private static let now = Date(timeIntervalSince1970: 1_789_779_600) // 2026-09-19 01:00 UTC

    private static func history(
        cost: Double?,
        dailyCost: Double? = nil,
        currency: String = "USD",
        days: Int = 30) -> CostUsageTokenSnapshot
    {
        CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: 120_000,
            last30DaysCostUSD: cost,
            currencyCode: currency,
            historyDays: days,
            historyLabel: "Last 30 days (UTC)",
            costProvenance: .vendorMetered,
            daily: [ClaudeIncompleteUsagePropagationTests.entry(
                day: "2026-09-18", cost: dailyCost, tokens: 120_000)],
            updatedAt: self.now)
    }
}
