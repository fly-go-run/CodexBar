import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct ProviderDetailSectionsContentTests {
    @Test(arguments: [ProviderDetailSection.Chart.Kind.bars, .line])
    func `generic detail renderer lays out rows and chart kinds`(kind: ProviderDetailSection.Chart.Kind) throws {
        let view = try ProviderDetailSectionsContent(sections: [Self.section(kind: kind)], chartColor: .blue)
        let size = NSHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: 280, height: CGFloat.greatestFiniteMagnitude))

        #expect(size.width > 0)
        #expect(size.height > 58)
    }

    private static func section(kind: ProviderDetailSection.Chart.Kind) throws -> ProviderDetailSection {
        try ProviderDetailSection(
            title: "Usage",
            rows: [ProviderDetailSection.Row(label: "Requests", value: "42", secondaryValue: "Today")],
            chart: ProviderDetailSection.Chart(
                kind: kind,
                title: "Daily",
                unit: "tokens",
                points: [
                    ProviderDetailSection.Chart.Point(label: "Mon", value: 12),
                    ProviderDetailSection.Chart.Point(label: "Tue", value: 24),
                ]))
    }
}
