import CodexBarCore
import Foundation

extension UsageMenuCardView.Model {
    /// Section titles and row labels localize through the shared catalog; values stay canonical.
    static func localizedProviderDetails(
        _ details: [ProviderDetailSection],
        provider _: UsageProvider) -> [ProviderDetailSection]
    {
        details.compactMap { section in
            let rows = section.rows.compactMap { row in
                try? ProviderDetailSection.Row(
                    id: row.id,
                    label: L(row.label),
                    value: row.value,
                    secondaryValue: row.secondaryValue,
                    progress: row.progress,
                    usageValue: row.usageValue)
            }
            return try? ProviderDetailSection(
                title: section.title.map(L),
                rows: rows,
                chart: section.chart)
        }
    }
}
