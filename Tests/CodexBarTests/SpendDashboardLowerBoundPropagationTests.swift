import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// A partial or partly unpriced scan must stay marked as a floor everywhere it is shown or exported.
/// The header used to say "partial estimate" while the subscription row and the exported JSON
/// presented the same totals as exact values.
struct SpendDashboardLowerBoundPropagationTests {
    @Test
    func `metric text marks lower bound cost and tokens`() {
        let both = spendDashboardMetricText(
            cost: 74.15,
            tokens: 431_000_000,
            currencyCode: "USD",
            costIsLowerBound: true,
            tokensAreLowerBound: true)
        #expect(both.contains("≥"))
        #expect(both.components(separatedBy: "≥").count == 3)

        let costOnly = spendDashboardMetricText(
            cost: 74.15,
            tokens: 431_000_000,
            currencyCode: "USD",
            costIsLowerBound: true,
            tokensAreLowerBound: false)
        #expect(costOnly.components(separatedBy: "≥").count == 2)
    }

    @Test
    func `exact totals keep no lower bound marker`() {
        let text = spendDashboardMetricText(cost: 12, tokens: 900, currencyCode: "USD")
        #expect(!text.contains("≥"))
    }

    /// 2026-07-16, one day after the fixture row, so the recorded usage falls inside the window.
    private static let now = Date(timeIntervalSince1970: 1_784_179_200)
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}
