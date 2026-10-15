import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct ShareStatsCompletenessTests {
    @Test
    func `one incomplete account excludes only its provider`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let model = SpendDashboardModel.build(
            inputs: [
                Self.input(provider: .codex, name: "Codex A", model: "gpt-4o", tokens: 300, cost: 3),
                Self.input(provider: .codex, name: "Codex B", model: "gpt-4o", tokens: 100, cost: 1, incomplete: 1),
                Self.input(provider: .claude, name: "Claude", model: "claude-sonnet-4", tokens: 200, cost: 2),
            ],
            requestedDays: 7,
            now: Self.now,
            calendar: calendar)
        let payload = try #require(ShareStatsBuilder.make(model: model))

        #expect(payload.providers.count == 3)
        #expect(payload.hasPartialModels)
        #expect(payload.topModels.map(\.provider) == [.claude])
        #expect(payload.topModels.first?.totalTokens == 200)
    }

    private static func input(
        provider: UsageProvider,
        name: String,
        model: String,
        tokens: Int?,
        cost: Double?,
        incomplete: Int = 0,
        hasModels: Bool = true) -> SpendDashboardModel.ProviderInput
    {
        .init(id: name, provider: provider, displayName: name, snapshot: CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            daily: [.init(
                date: "2026-07-16",
                inputTokens: nil,
                outputTokens: nil,
                totalTokens: tokens,
                costUSD: cost,
                modelsUsed: nil,
                modelBreakdowns: hasModels ? [.init(
                    modelName: model,
                    costUSD: cost,
                    totalTokens: tokens,
                    incompleteRequestCount: incomplete)] : nil)],
            updatedAt: self.now))
    }

    private static let now = Date(timeIntervalSince1970: 1_784_179_200)
}
