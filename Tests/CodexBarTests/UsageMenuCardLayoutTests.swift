import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct UsageMenuCardLayoutTests {
    private static let heightTolerance: CGFloat = 1

    @Test
    func `overview groups provider content without section dividers`() {
        #expect(OverviewMenuCardRowView.showsSectionDividers == false)
    }

    @Test
    func `metric line presentation keeps remaining percent and reset in title row`() {
        let metric = UsageMenuCardView.Model.Metric(
            id: "weekly",
            title: "Weekly",
            percent: 69,
            percentStyle: .left,
            resetText: "Resets Jul 22, 8:33 AM",
            detailText: nil,
            detailLeftText: "26% in deficit",
            detailRightText: "Runs out in 19h 7m (85% risk)",
            pacePercent: 43,
            paceOnTop: true,
            sessionEquivalentDetail: .init(
                leftText: "Est. 2 session quotas left",
                rightText: "6 windows until reset",
                accessibilityLabel: "Est. 2 session quotas left · 6 windows until reset"))

        let presentation = metric.linePresentation(title: metric.title)

        #expect(presentation.titleText == "Weekly 69% left")
        #expect(presentation.resetText == "Resets Jul 22, 8:33 AM")
        #expect(presentation.metaText ==
            "26% in deficit · Runs out in 19h 7m (85% risk) · " +
            "Est. 2 session quotas left · 6 windows until reset")
    }

    @Test
    func `metric title follows configured percent style`() {
        let leftMetric = UsageMenuCardView.Model.Metric(
            id: "weekly",
            title: "Weekly",
            percent: 69,
            percentStyle: .left,
            resetText: nil,
            detailText: nil,
            detailLeftText: nil,
            detailRightText: nil,
            pacePercent: nil,
            paceOnTop: true)
        let usedMetric = UsageMenuCardView.Model.Metric(
            id: "weekly",
            title: "Weekly",
            percent: 31,
            percentStyle: .used,
            resetText: nil,
            detailText: nil,
            detailLeftText: nil,
            detailRightText: nil,
            pacePercent: nil,
            paceOnTop: true)

        #expect(leftMetric.linePresentation(title: leftMetric.title).titleText == "Weekly 69% left")
        #expect(usedMetric.linePresentation(title: usedMetric.title).titleText == "Weekly 31% used")
    }
}
