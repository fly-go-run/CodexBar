import Foundation
import Testing
@testable import CodexBarCore

struct WidgetSnapshotCompatibilityTests {
    @Test
    func `an account record cannot substitute quota from a different provider`() throws {
        let old = try self.decoder().decode(WidgetSnapshot.self, from: Data(Self.legacyJSON.utf8))
        let codex = try #require(old.entries.first { $0.provider == .codex })
        let snapshot = WidgetSnapshot(
            entries: old.entries,
            accounts: [.init(id: "claude/token:work", provider: .claude, label: "Work", usage: codex)],
            enabledProviders: old.enabledProviders,
            generatedAt: old.generatedAt)
        let selected = snapshot.selectingAccount("claude/token:work", for: .claude)

        #expect(!selected.entries.contains { $0.provider == .claude })
        #expect(selected.entries.first?.provider == .codex)
        #expect(selected.entries.first?.primary?.remainingPercent == 90)
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Fixed pre-feature wire data, independent of the current WidgetSnapshot encoder.
    private static let legacyJSON = #"""
    {
      "entries": [
        {
          "provider": "claude",
          "updatedAt": "2025-12-20T12:00:00Z",
          "primary": {"usedPercent": 25, "windowMinutes": 300, "resetsAt": "2025-12-20T15:00:00Z"},
          "secondary": {"usedPercent": 40, "windowMinutes": 10080, "resetsAt": "2025-12-25T12:00:00Z"},
          "usageRows": [
            {"id": "session", "title": "Session", "percentLeft": 75},
            {"id": "weekly", "title": "Weekly", "percentLeft": 60}
          ],
          "dailyUsage": [],
          "quotaOwnerKey": "fixture-claude-owner"
        },
        {
          "provider": "codex",
          "updatedAt": "2025-12-20T12:00:00Z",
          "primary": {"usedPercent": 10, "windowMinutes": 300, "resetsAt": "2025-12-20T16:00:00Z"},
          "secondary": {"usedPercent": 20, "windowMinutes": 10080, "resetsAt": "2025-12-26T12:00:00Z"},
          "creditsRemaining": 12.5,
          "codeReviewRemainingPercent": 85,
          "tokenUsage": {
            "sessionCostUSD": 1.25,
            "sessionTokens": 1200,
            "last30DaysCostUSD": 19.5,
            "last30DaysTokens": 18000,
            "currencyCode": "USD",
            "sessionLabel": "Today",
            "last30DaysLabel": "30d",
            "updatedAt": "2025-12-20T11:55:00Z"
          },
          "dailyUsage": [{"dayKey": "2025-12-20", "totalTokens": 1200, "costUSD": 1.25}]
        }
      ],
      "enabledProviders": ["claude", "codex"],
      "usageBarsShowUsed": true,
      "generatedAt": "2025-12-20T12:00:00Z"
    }
    """#
}

/// Freeze the pre-account wire fields here: using WidgetSnapshot itself as the old reader
/// would stop detecting accidental required-field additions or changes to provider entries.
private struct LegacyWidgetSnapshot: Codable {
    let entries: [LegacyWidgetProviderEntry]
    let enabledProviders: [ProviderInstanceID]
    let usageBarsShowUsed: Bool
    let generatedAt: Date
}

private struct LegacyWidgetProviderEntry: Codable {
    let provider: ProviderInstanceID
    let updatedAt: Date
    let primary: RateWindow?
    let secondary: RateWindow?
    let tertiary: RateWindow?
    let usageRows: [WidgetSnapshot.WidgetUsageRowSnapshot]?
    let creditsRemaining: Double?
    let codeReviewRemainingPercent: Double?
    let tokenUsage: WidgetSnapshot.TokenUsageSummary?
    let dailyUsage: [WidgetSnapshot.DailyUsagePoint]
    let providerCost: ProviderCostSnapshot?
    let quotaOwnerKey: String?
}
