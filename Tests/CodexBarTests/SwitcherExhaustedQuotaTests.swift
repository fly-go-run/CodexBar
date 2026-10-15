import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

enum SwitcherExhaustedQuotaTests {
    private static func snapshot(
        rolling: Double = 20,
        weekly: Double? = 40,
        monthly: Double) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: RateWindow(usedPercent: rolling, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: weekly.map {
                RateWindow(usedPercent: $0, windowMinutes: 10080, resetsAt: nil, resetDescription: nil)
            },
            tertiary: RateWindow(usedPercent: monthly, windowMinutes: 43200, resetsAt: nil, resetDescription: nil),
            updatedAt: Date(timeIntervalSince1970: 1_788_480_000))
    }
}
