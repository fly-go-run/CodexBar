import CodexBarCore
import SwiftUI

/// Output-speed block of the inline cost dashboard: a heading with the window and request count, then one
/// row per model with its recent trend against the 24h average, the headline rate, and one sentence saying
/// how that compares with usual. The figures behind it live in the row's hover help.
struct InlineTokenSpeedRow: View {
    let summary: TokenSpeedSummary
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.summary.heading)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Text(self.summary.windowSummary)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 1) {
                ForEach(Array(self.summary.rows.enumerated()), id: \.offset) { index, row in
                    GridRow(alignment: .center) {
                        self.modelLabel(row)
                        TokenSpeedSparkline(
                            trend: row.trend,
                            baseline: row.baseline,
                            isSlow: row.slowdownPercent != nil)
                            .frame(height: 18)
                            .frame(maxWidth: .infinity)
                        self.valueLabel(row)
                            .gridColumnAlignment(.trailing)
                    }
                    .padding(.top, index == 0 ? 0 : 8)
                    .help(row.help ?? "")
                    GridRow {
                        Text(row.detail ?? " ")
                            .font(.caption)
                            .foregroundStyle(row.detailIsWarning && !self.isHighlighted
                                ? Color(nsColor: .systemOrange)
                                : MenuHighlightStyle.secondary(self.isHighlighted))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .gridCellColumns(3)
                            .help(row.help ?? "")
                    }
                }
            }
        }
        .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
        .accessibilityElement(children: .combine)
    }

    private func modelLabel(_ row: TokenSpeedSummary.Row) -> some View {
        Text([row.model, row.windowNote].compactMap(\.self).joined(separator: " · "))
            .font(.subheadline)
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize()
    }

    /// Padded to a three-digit rate so the sparklines end at the same x across rows.
    private func valueLabel(_ row: TokenSpeedSummary.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            ZStack(alignment: .trailing) {
                Text(verbatim: "000").hidden()
                Text(row.rateText)
            }
            .font(.title3.weight(.semibold))
            Text(verbatim: "tok/s")
                .font(.caption)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        }
        .monospacedDigit()
        .fixedSize()
        .accessibilityLabel(row.value)
    }
}

/// Rates of the most recent active periods with the 24h average as a dashed reference. The line keeps a fixed
/// spacing and ends at the right edge, so a short history sits on the right instead of being stretched.
/// The trailing dot is the latest period, orange when the last hour runs clearly below the average.
struct TokenSpeedSparkline: View {
    let trend: [Double]
    let baseline: Double?
    let isSlow: Bool
    var slotCount = TokenOutputSpeedSnapshot.recentPeriodCount
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        Canvas { context, size in
            let values = self.trend + [self.baseline].compactMap(\.self)
            guard let low = values.min(), let high = values.max(), size.width > 0, !self.trend.isEmpty else { return }
            let span = max(high - low, max(high * 0.2, 1))
            let floor = max(0, low - span * 0.15)
            let ceiling = floor + span * 1.3
            let inset: CGFloat = 3
            func y(_ value: Double) -> CGFloat {
                let ratio = (value - floor) / (ceiling - floor)
                return inset + (size.height - inset * 2) * (1 - CGFloat(ratio))
            }
            let step = (size.width - inset * 2) / CGFloat(max(self.slotCount - 1, 1))
            let firstX = size.width - inset - CGFloat(self.trend.count - 1) * step
            let points = self.trend.enumerated().map { index, value in
                CGPoint(x: firstX + CGFloat(index) * step, y: y(value))
            }

            if let baseline, let first = points.first, let last = points.last {
                var line = Path()
                line.move(to: CGPoint(x: first.x, y: y(baseline)))
                line.addLine(to: CGPoint(x: last.x, y: y(baseline)))
                context.stroke(
                    line,
                    with: .color(MenuHighlightStyle.secondary(self.isHighlighted).opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }

            var path = Path()
            path.addLines(points)
            context.stroke(
                path,
                with: .color(MenuHighlightStyle.secondary(self.isHighlighted)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            if let last = points.last {
                let dotColor: Color = self.isHighlighted
                    ? MenuHighlightStyle.primary(true)
                    : self.isSlow ? Color(nsColor: .systemOrange) : MenuHighlightStyle.primary(false)
                context.fill(
                    Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)),
                    with: .color(dotColor))
            }
        }
        .accessibilityHidden(true)
    }
}
