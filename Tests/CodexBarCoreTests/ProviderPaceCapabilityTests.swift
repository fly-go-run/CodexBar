import CodexBarCore
import Foundation
import Testing

struct ProviderPaceCapabilityTests {
    private static let weeklyWindowMinutes = 7 * 24 * 60
    private static let monthlyWindowSentinelMinutes = 30 * 24 * 60

    @Test
    func `calendar month pace resolves the real cycle duration`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let resetsAt = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 3,
            day: 1)))
        let window = Self.window(
            minutes: Self.monthlyWindowSentinelMinutes,
            resetsAt: resetsAt)

        let resolved = ProviderPaceCapability.calendarMonthResetWindow.resolvedResetWindowForPace(window)

        #expect(resolved.windowMinutes == 28 * 24 * 60)
        #expect(resolved.resetsAt == resetsAt)
        #expect(resolved.usedPercent == window.usedPercent)
    }

    private static func window(
        minutes: Int?,
        resetsAt: Date?,
        resetDescription: String? = nil) -> RateWindow
    {
        RateWindow(
            usedPercent: 50,
            windowMinutes: minutes,
            resetsAt: resetsAt,
            resetDescription: resetDescription)
    }
}
