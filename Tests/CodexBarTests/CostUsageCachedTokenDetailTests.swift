import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageCachedTokenDetailTests {
    private static func fetch(
        now: Date,
        forceRefresh: Bool,
        options: CostUsageScanner.Options) async throws -> CostUsageTokenSnapshot
    {
        try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            environment: [:],
            now: now,
            forceRefresh: forceRefresh,
            historyDays: 30,
            allowPricingRefresh: false,
            scannerOptions: options)
    }

    private static func turn(timestamp: String, id: String) -> [String: Any] {
        [
            "type": "turn_context",
            "timestamp": timestamp,
            "payload": ["model": "openai/gpt-5.4", "turn_id": id],
        ]
    }

    private static func event(timestamp: String, total: [Int], last: [Int]) -> [String: Any] {
        [
            "type": "event_msg",
            "timestamp": timestamp,
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": self.tokens(total),
                    "last_token_usage": self.tokens(last),
                ],
            ],
        ]
    }

    private static func tokens(_ values: [Int]) -> [String: Int] {
        [
            "input_tokens": values[0],
            "cached_input_tokens": values[1],
            "output_tokens": values[2],
            "reasoning_output_tokens": values[3],
        ]
    }
}
