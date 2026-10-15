import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

enum SpendTrendScopeTests {
    private static func day(_ day: Int, month: Int = 10, calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
    }
}
