import Foundation
import Testing
@testable import CodexBarCore

struct ProviderNumericBoundaryTests {
    @Test
    func `monthly pacing retains its original window when inferred minutes overflow`() {
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: ProviderPaceCapability.monthlyWindowSentinelMinutes,
            resetsAt: Date(timeIntervalSince1970: 8e23),
            resetDescription: nil)
        let resolved = ProviderPaceCapability.calendarMonthResetWindow.resolvedResetWindowForPace(window)
        #expect(resolved.windowMinutes == window.windowMinutes)
        #expect(resolved.usedPercent == 50)
    }

    @Test(arguments: [1e30, -1e30, Double.infinity, -.infinity, .nan])
    func `shared date formatting handles unrepresentable timestamps`(seconds: Double) {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let date = Date(timeIntervalSince1970: seconds)
        #expect(UsageFormatter.resetCountdownDescription(from: date, now: now) == "Unknown")
        #expect(UsageFormatter.updatedString(from: date, now: now) == "Updated Unknown")
        let window = RateWindow(usedPercent: 50, windowMinutes: nil, resetsAt: date, resetDescription: nil)
        #expect(UsageFormatter.resetLine(for: window, style: .countdown, now: now) == nil)
        #expect(UsageFormatter.resetLine(for: window, style: .absolute, now: now) == nil)
    }
}
