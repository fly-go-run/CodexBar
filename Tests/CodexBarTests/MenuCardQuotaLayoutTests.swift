import Testing
@testable import CodexBar

struct MenuCardQuotaLayoutTests {
    private typealias Model = UsageMenuCardView.Model

    private static func metric(
        _ id: String,
        percent: Double,
        style: Model.PercentStyle = .left,
        statusText: String? = nil,
        cardStyle: Bool = false) -> Model.Metric
    {
        Model.Metric(
            id: id,
            title: id,
            percent: percent,
            percentStyle: style,
            statusText: statusText,
            resetText: nil,
            detailText: nil,
            detailLeftText: nil,
            detailRightText: nil,
            pacePercent: nil,
            paceOnTop: true,
            cardStyle: cardStyle)
    }

    @Test
    func `the tightest quota leads and the rest keep their order in the grid`() {
        let layout = Model.quotaLayout(for: [
            Self.metric("primary", percent: 86),
            Self.metric("secondary", percent: 12),
            Self.metric("tertiary", percent: 100),
        ])
        // An untouched quota still gets its bar in the grid.
        #expect(layout == Model.QuotaLayout(
            leadID: "secondary",
            compactIDs: ["primary", "tertiary"],
            fullIDs: []))
    }

    @Test
    func `used percentages rank by what is left`() {
        let layout = Model.quotaLayout(for: [
            Self.metric("primary", percent: 30, style: .used),
            Self.metric("secondary", percent: 90, style: .used),
        ])
        #expect(layout.leadID == "secondary")
        #expect(layout.compactIDs == ["primary"])
    }

    @Test
    func `ties keep the first quota and status or card rows stay full width`() {
        let layout = Model.quotaLayout(for: [
            Self.metric("primary", percent: 50),
            Self.metric("extra", percent: 10, cardStyle: true),
            Self.metric("secondary", percent: 50),
            Self.metric("review", percent: 0, statusText: "Unavailable"),
        ])
        #expect(layout == Model.QuotaLayout(
            leadID: "primary",
            compactIDs: ["secondary"],
            fullIDs: ["extra", "review"]))
    }

    @Test
    func `a single plain quota keeps the ordinary rows`() {
        let metrics = [
            Self.metric("primary", percent: 40),
            Self.metric("extra", percent: 10, cardStyle: true),
        ]
        let layout = Model.quotaLayout(for: metrics)
        #expect(layout.leadID == nil)
        #expect(layout.compactIDs.isEmpty)
        #expect(layout.fullIDs == ["primary", "extra"])
    }
}
