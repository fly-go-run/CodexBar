import CodexBarCore
import SwiftUI

/// Output speed of every model of the last 24h at the foot of the cost submenu, so models the card leaves out
/// (a smaller share, a model switched away from) can still be compared. Typography follows the cost detail
/// rows above it; the trend line is the card's.
struct CostHistoryTokenSpeedSection: View {
    let summary: TokenSpeedSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.summary.heading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(self.summary.windowSummary)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .lineLimit(1)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 1) {
                ForEach(Array(self.summary.rows.enumerated()), id: \.offset) { index, row in
                    GridRow(alignment: .center) {
                        Text(row.model)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .fixedSize()
                        TokenSpeedSparkline(
                            trend: row.trend,
                            baseline: row.baseline,
                            isSlow: row.slowdownPercent != nil)
                            .frame(height: 16)
                            .frame(maxWidth: .infinity)
                        self.valueLabel(row)
                            .gridColumnAlignment(.trailing)
                    }
                    .padding(.top, index == 0 ? 0 : 6)
                    .help(row.help ?? "")
                    GridRow {
                        Text(row.detail ?? " ")
                            .font(.caption2)
                            .foregroundStyle(row.detailIsWarning
                                ? Color(nsColor: .systemOrange)
                                : Color(nsColor: .tertiaryLabelColor))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .gridCellColumns(3)
                            .help(row.help ?? "")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Padded to a three-digit rate so the trend lines end at the same x across rows.
    private func valueLabel(_ row: TokenSpeedSummary.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            ZStack(alignment: .trailing) {
                Text(verbatim: "000").hidden()
                Text(row.rateText)
            }
            .font(.callout.weight(.semibold))
            Text(verbatim: "tok/s")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .fixedSize()
        .accessibilityLabel(row.value)
    }
}
