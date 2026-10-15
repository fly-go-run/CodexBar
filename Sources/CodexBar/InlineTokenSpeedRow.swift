import SwiftUI

/// Output-speed block of the inline cost dashboard: label and headline rate on one line, the
/// per-model 24h rates as a quiet second line.
struct InlineTokenSpeedRow: View {
    let summary: TokenSpeedSummary
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(self.summary.title)
                    .font(.body)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if let slowdown = self.summary.slowdownText {
                    Text(slowdown)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(self.isHighlighted
                            ? MenuHighlightStyle.primary(true)
                            : Color(nsColor: .systemOrange))
                        .help(self.summary.slowdownHelp ?? "")
                }
                Text(self.summary.value)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
            if let rowsLine = self.summary.rowsLine {
                Text(rowsLine)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
