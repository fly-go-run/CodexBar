import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CodexHistoricalPricingProofTests {
    private struct SessionFixture {
        let day: Date
        let filename: String
        let sessionID: String
        let model: String
    }

    private func writeCodexSession(env: CostUsageTestEnvironment, fixture: SessionFixture) throws {
        _ = try env.writeCodexSessionFile(
            day: fixture.day,
            filename: fixture.filename,
            contents: env.jsonl([
                [
                    "type": "session_meta",
                    "timestamp": env.isoString(for: fixture.day),
                    "payload": ["session_id": fixture.sessionID],
                ],
                [
                    "type": "turn_context",
                    "timestamp": env.isoString(for: fixture.day),
                    "payload": ["model": fixture.model],
                ],
                [
                    "type": "event_msg",
                    "timestamp": env.isoString(for: fixture.day.addingTimeInterval(1)),
                    "payload": [
                        "type": "token_count",
                        "info": [
                            "model": fixture.model,
                            "last_token_usage": [
                                "input_tokens": 100,
                                "cached_input_tokens": 10,
                                "output_tokens": 5,
                            ],
                        ],
                    ],
                ],
            ]))
    }

    private func lookup(
        snapshot: CostUsageTokenSnapshot,
        day: String,
        model: String) -> CostUsageDailyReport.ModelBreakdown?
    {
        snapshot.daily.first(where: { $0.date == day })?.modelBreakdowns?.first(where: { $0.modelName == model })
    }

    private func redactedProofRow(
        day: String,
        model: String,
        breakdown: CostUsageDailyReport.ModelBreakdown) -> [String: Any]
    {
        [
            "day": day,
            "model": model,
            "totalTokens": breakdown.totalTokens as Any,
            "costUSD": breakdown.costUSD as Any,
        ]
    }
}
