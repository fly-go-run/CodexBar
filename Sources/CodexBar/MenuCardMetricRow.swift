import CodexBarCore
import SwiftUI

struct MetricRow: View {
    let metric: UsageMenuCardView.Model.Metric
    let layoutMetric: UsageMenuCardView.Model.Metric
    let title: String
    let progressColor: Color
    var compact = false
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        let presentation = self.metric.cardPresentation(title: self.title)
        let layoutPresentation = self.layoutMetric.cardPresentation(title: self.title)
        VStack(alignment: .leading, spacing: 5) {
            if let statusText = self.metric.statusText {
                Text(self.title)
                    .font(.body)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            } else {
                self.header(presentation)
                UsageProgressBar(
                    percent: self.metric.percent,
                    tint: self.progressColor,
                    accessibilityLabel: self.metric.percentStyle.accessibilityLabel,
                    pacePercent: self.metric.pacePercent,
                    paceOnTop: self.metric.paceOnTop)
                // Reserve the footer whenever the layout model has one so live updates never resize.
                if !self.compact, layoutPresentation.hasFooter {
                    self.footer(presentation)
                }
                if !self.compact, self.layoutMetric.detailText != nil {
                    Text(self.metric.detailText ?? " ")
                        .font(.subheadline)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .help(presentation.helpText ?? "")
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(self.metric.cardStyle ? 10 : 0)
        .background(self.metric.cardStyle ? Color.secondary.opacity(self.isHighlighted ? 0.2 : 0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: self.metric.cardStyle ? 10 : 0))
    }

    private func header(_ presentation: UsageMenuCardView.Model.Metric.CardPresentation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(presentation.title)
                .font(.body)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(presentation.percentText)
                .font(.body.weight(.semibold))
                .monospacedDigit()
            Text(presentation.percentSuffix)
                .font(.subheadline)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        }
        .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
        .accessibilityElement(children: .combine)
    }

    private func footer(_ presentation: UsageMenuCardView.Model.Metric.CardPresentation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(presentation.resetText ?? " ")
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .layoutPriority(1)
            Spacer(minLength: 8)
            if let footnote = presentation.footnoteText {
                Text(footnote)
                    .foregroundStyle(
                        presentation.footnoteIsWarning && !self.isHighlighted
                            ? Color(nsColor: .systemOrange)
                            : MenuHighlightStyle.secondary(self.isHighlighted))
                    .minimumScaleFactor(0.85)
            }
        }
        .font(.subheadline)
        .monospacedDigit()
        .lineLimit(1)
    }
}
