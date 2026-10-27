import CodexBarCore
import SwiftUI

extension UsageMenuCardView.Model {
    /// How the card arranges its quota rows: the tightest quota leads at full size, the other plain quotas
    /// sit in a compact two-column grid below it, untouched ones collapse into one quiet line (a full bar
    /// that says "nothing used" is noise), and rows with their own layout (status text, card style) keep
    /// their full row after that.
    struct QuotaLayout: Equatable {
        let leadID: String?
        let compactIDs: [String]
        var unusedIDs: [String] = []
        let fullIDs: [String]

        var heightFingerprint: String {
            [
                "lead=\(self.leadID ?? "-")",
                "compact=\(self.compactIDs.joined(separator: ","))",
                "unused=\(self.unusedIDs.joined(separator: ","))",
            ].joined(separator: ";")
        }
    }

    /// The lead only exists when there is something to rank: with a single plain quota the card keeps
    /// its ordinary rows.
    static func quotaLayout(for metrics: [Metric]) -> QuotaLayout {
        let plain = metrics.filter { $0.statusText == nil && !$0.cardStyle }
        guard plain.count >= 2,
              let lead = plain.enumerated().min(by: { lhs, rhs in
                  lhs.element.remainingPercent != rhs.element.remainingPercent
                      ? lhs.element.remainingPercent < rhs.element.remainingPercent
                      : lhs.offset < rhs.offset
              })?.element
        else {
            return QuotaLayout(leadID: nil, compactIDs: [], fullIDs: metrics.map(\.id))
        }
        let plainIDs = Set(plain.map(\.id))
        let others = plain.filter { $0.id != lead.id }
        return QuotaLayout(
            leadID: lead.id,
            compactIDs: others.filter { !$0.isUnused }.map(\.id),
            unusedIDs: others.filter(\.isUnused).map(\.id),
            fullIDs: metrics.map(\.id).filter { !plainIDs.contains($0) })
    }

    var quotaLayout: QuotaLayout {
        Self.quotaLayout(for: self.metrics)
    }
}

extension UsageMenuCardView.Model.Metric {
    /// Below this the lead quota's percentage turns orange.
    static let lowRemainingPercent = 20.0

    var remainingPercent: Double {
        self.percentStyle == .left ? self.percent : 100 - self.percent
    }

    /// Nothing used yet in this window; its reset time says nothing then.
    var isUnused: Bool {
        self.remainingPercent >= 100
    }
}

/// A secondary quota in the compact grid: title and percentage on one line, the bar, then the reset time.
/// Pace and other commentary move to the hover help.
struct CompactMetricCell: View {
    let metric: UsageMenuCardView.Model.Metric
    let title: String
    let progressColor: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        let presentation = self.metric.cardPresentation(title: self.title)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(presentation.title)
                    .font(.subheadline)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(presentation.percentText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            UsageProgressBar(
                percent: self.metric.percent,
                tint: self.progressColor,
                accessibilityLabel: self.metric.percentStyle.accessibilityLabel,
                pacePercent: self.metric.pacePercent,
                paceOnTop: self.metric.paceOnTop)
            Text(presentation.resetText ?? " ")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(self.help(presentation))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func help(_ presentation: UsageMenuCardView.Model.Metric.CardPresentation) -> String {
        [
            "\(presentation.title) \(presentation.percentText) \(presentation.percentSuffix)",
            presentation.resetText,
            presentation.footnoteText,
            presentation.helpText,
        ]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: "\n")
    }
}

/// Quotas nothing has touched yet, as one quiet line: "Fable 每周 · 未使用". Their reset times are in the help.
struct UnusedQuotasLine: View {
    let metrics: [UsageMenuCardView.Model.Metric]
    let titles: [String]
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        Text("\(self.titles.joined(separator: ", ")) · \(L("usage_metric_unused"))")
            .font(.caption)
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(zip(self.titles, self.metrics)
                .map { title, metric in [title, metric.resetText].compactMap(\.self).joined(separator: " · ") }
                .joined(separator: "\n"))
    }
}
