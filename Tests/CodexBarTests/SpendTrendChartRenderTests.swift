import AppKit
import CodexBarCore
import SwiftUI
import XCTest
@testable import CodexBar

/// Optional, offline rendering of the production chart, using only synthetic account history.
@MainActor
final class SpendTrendChartRenderTests: XCTestCase {
    fileprivate static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        return calendar
    }
}
