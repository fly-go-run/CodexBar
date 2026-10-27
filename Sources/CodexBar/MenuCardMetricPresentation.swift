import CodexBarCore
import Foundation

extension UsageMenuCardView.Model.Metric {
    /// Menu-card layout of a quota row: the percentage is its own emphasized value and the reset time
    /// sits under the bar. Pace commentary, run-out forecasts included, moves to the hover help. Text surfaces
    /// keep `linePresentation`.
    struct CardPresentation: Equatable {
        let title: String
        let percentText: String
        let percentSuffix: String
        let resetText: String?
        let footnoteText: String?
        let helpText: String?

        var hasFooter: Bool {
            self.resetText != nil || self.footnoteText != nil
        }
    }

    func cardPresentation(title: String) -> CardPresentation {
        let percentText = UsageFormatter.percentText(self.percent, suffix: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detailParts = [self.detailLeftText, self.detailRightText].compactMap(\.trimmedNonEmpty)
        var footnote: String?
        var helpParts = [self.helpText].compactMap(\.trimmedNonEmpty)
        if self.detailIsPaceDerived {
            // Run-out forecasts only repeat what the bar and reset time already say; keep them in the help.
            if !detailParts.isEmpty { helpParts.append(detailParts.joined(separator: " · ")) }
        } else if !detailParts.isEmpty {
            footnote = detailParts.joined(separator: " · ")
        }
        if let equivalent = self.sessionEquivalentDetail {
            helpParts.append(equivalent.accessibilityLabel)
        }
        return CardPresentation(
            title: title,
            percentText: percentText,
            percentSuffix: self.percentStyle.labelSuffix,
            resetText: self.resetText.trimmedNonEmpty,
            footnoteText: footnote,
            helpText: helpParts.isEmpty ? nil : helpParts.joined(separator: "\n"))
    }
}

extension UsageMenuCardView.Model {
    /// "10/24 续订" for the header; only for providers whose plan dates sat beside the quota rows.
    static func planRenewalText(input: Input) -> String? {
        guard input.provider == .codex || input.provider == .claude,
              let snapshot = input.snapshot,
              let renewsAt = snapshot.subscriptionRenewsAt
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = codexBarLocalizedLocale()
        formatter.timeZone = snapshot.subscriptionRenewsAtIsDateOnly ? TimeZone(secondsFromGMT: 0) : .current
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return L("plan_renews_short", formatter.string(from: renewsAt))
    }
}
