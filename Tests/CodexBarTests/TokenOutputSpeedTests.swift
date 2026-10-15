import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct TokenOutputSpeedTests {
    private static func jsonl(_ objects: [[String: Any]]) throws -> Data {
        var data = Data()
        for object in objects {
            try data.append(JSONSerialization.data(withJSONObject: object))
            data.append(0x0A)
        }
        return data
    }

    private static func date(_ raw: String) throws -> Date {
        try #require(CostUsageScanner.dateFromTimestamp(raw))
    }

    @Test
    func `claude requests start at their parent entry and end at the last block`() throws {
        let data = try Self.jsonl([
            ["type": "user", "uuid": "u1", "timestamp": "2026-10-10T11:37:00.000Z"],
            ["type": "attachment", "uuid": "a1", "parentUuid": "u1", "timestamp": "2026-10-10T11:37:01.000Z"],
            [
                "type": "assistant", "uuid": "m1", "parentUuid": "a1", "timestamp": "2026-10-10T11:37:03.000Z",
                "message": ["id": "msg_1", "model": "claude-opus-4-1", "usage": ["output_tokens": 400]],
            ],
            [
                "type": "assistant", "uuid": "m2", "parentUuid": "m1", "timestamp": "2026-10-10T11:37:05.000Z",
                "message": ["id": "msg_1", "model": "claude-opus-4-1", "usage": ["output_tokens": 400]],
            ],
            // Parent was never logged (e.g. a resumed session): no trustworthy start time.
            [
                "type": "assistant", "uuid": "m3", "parentUuid": "missing", "timestamp": "2026-10-10T11:38:00.000Z",
                "message": ["id": "msg_2", "model": "claude-opus-4-1", "usage": ["output_tokens": 50]],
            ],
            [
                "type": "assistant", "uuid": "m4", "parentUuid": "m2", "timestamp": "2026-10-10T11:38:01.000Z",
                "message": ["id": "msg_3", "model": "<synthetic>", "usage": ["output_tokens": 0]],
            ],
        ])

        let samples = TokenOutputSpeedScanner.parseClaudeSession(data)

        #expect(samples.count == 1)
        let sample = try #require(samples.first)
        #expect(sample.model == "claude-opus-4-1")
        #expect(sample.outputTokens == 400)
        #expect(try sample.startedAt == (Self.date("2026-10-10T11:37:01.000Z")))
        #expect(sample.durationSeconds == 4)
    }

    @Test
    func `codex requests span from the triggering input to the last output item`() throws {
        func item(_ ts: String, _ payload: [String: Any]) -> [String: Any] {
            ["timestamp": ts, "type": "response_item", "payload": payload]
        }
        func tokens(_ ts: String, _ output: Int) -> [String: Any] {
            [
                "timestamp": ts, "type": "event_msg",
                "payload": ["type": "token_count", "info": ["last_token_usage": ["output_tokens": output]]],
            ]
        }
        let data = try Self.jsonl([
            ["timestamp": "2026-10-08T14:30:19.000Z", "type": "turn_context", "payload": ["model": "gpt-5"]],
            item("2026-10-08T14:30:19.500Z", ["type": "message", "role": "user"]),
            item("2026-10-08T14:30:22.000Z", ["type": "reasoning"]),
            item("2026-10-08T14:30:24.500Z", ["type": "custom_tool_call"]),
            item("2026-10-08T14:30:30.000Z", ["type": "custom_tool_call_output"]),
            tokens("2026-10-08T14:30:30.001Z", 250),
            // Duplicate token_count for the same request must not produce a second sample.
            tokens("2026-10-08T14:30:30.002Z", 250),
            item("2026-10-08T14:30:32.000Z", ["type": "message", "role": "assistant"]),
            tokens("2026-10-08T14:30:32.100Z", 120),
            // A user message without any model output yet never yields a sample.
            item("2026-10-08T14:31:00.000Z", ["type": "message", "role": "user"]),
            tokens("2026-10-08T14:31:00.100Z", 99),
        ])

        let samples = TokenOutputSpeedScanner.parseCodexSession(data)

        #expect(samples.count == 2)
        #expect(samples.map(\.outputTokens) == [250, 120])
        #expect(samples.map(\.durationSeconds) == [5, 2])
        #expect(try samples[1].startedAt == (Self.date("2026-10-08T14:30:30.000Z")))
        #expect(samples.allSatisfy { $0.model == "gpt-5" })
    }

    @Test
    func `snapshot weights by duration and drops unmeasurable requests`() throws {
        let now = try Self.date("2026-10-10T12:00:00.000Z")
        func sample(_ model: String, _ tokens: Int, seconds: Double, minutesAgo: Double) -> TokenOutputSpeedSample {
            let end = now.addingTimeInterval(-minutesAgo * 60)
            return TokenOutputSpeedSample(
                model: model,
                outputTokens: tokens,
                startedAt: end.addingTimeInterval(-seconds),
                completedAt: end)
        }
        let snapshot = TokenOutputSpeedSnapshot(
            samples: [
                sample("opus", 1000, seconds: 10, minutesAgo: 5),
                sample("opus", 200, seconds: 10, minutesAgo: 120),
                sample("sonnet", 300, seconds: 6, minutesAgo: 30),
                sample("sonnet", 5, seconds: 1, minutesAgo: 1), // too few tokens
                sample("sonnet", 500, seconds: 900, minutesAgo: 1), // stalled
                sample("sonnet", 500, seconds: 5, minutesAgo: 25 * 60), // outside window
            ],
            now: now)

        #expect(snapshot.models.map(\.model) == ["opus", "sonnet"])
        #expect(snapshot.models[0].tokensPerSecond == 60)
        #expect(snapshot.models[0].requestCount == 2)
        #expect(snapshot.models[1].tokensPerSecond == 50)
        let lastHour = try #require(snapshot.lastHour)
        #expect(lastHour.requestCount == 2)
        #expect(lastHour.outputTokens == 1300)
    }

    @Test
    func `speed summary leads with the last hour once it has enough requests`() throws {
        let now = try Self.date("2026-10-10T12:00:00.000Z")
        func sample(_ model: String, _ tokens: Int, minutesAgo: Double) -> TokenOutputSpeedSample {
            let end = now.addingTimeInterval(-minutesAgo * 60)
            return TokenOutputSpeedSample(
                model: model, outputTokens: tokens, startedAt: end.addingTimeInterval(-10), completedAt: end)
        }
        typealias Model = UsageMenuCardView.Model
        let busy = TokenOutputSpeedSnapshot(
            samples: [
                sample("claude-opus-4-1-20250805", 900, minutesAgo: 5),
                sample("claude-opus-4-1-20250805", 900, minutesAgo: 10),
                sample("claude-sonnet-4-5", 600, minutesAgo: 20),
                sample("claude-opus-4-1-20250805", 300, minutesAgo: 300),
            ],
            now: now)

        let summary = try #require(Model.tokenSpeedSummary(busy))

        #expect(summary.title == L("token_speed_title_last_hour"))
        #expect(summary.value == "80 tok/s")
        #expect(summary.rows == [
            .init(name: "Opus 4.1", value: "70"),
            .init(name: "Sonnet 4.5", value: "60"),
        ])
        #expect(summary.rowsLine == "24h · Opus 4.1 70 · Sonnet 4.5 60")
        // 80 tok/s now vs ~73 over 24h: not slower, so nothing is flagged.
        #expect(summary.slowdownPercent == nil)
        #expect(Model.tokenOutputSpeedLines(busy) == [summary.compactLine])

        // Too few recent requests: fall back to the 24h rate; a lone model row would only repeat it.
        let quiet = TokenOutputSpeedSnapshot(
            samples: [sample("claude-opus-4-1-20250805", 500, minutesAgo: 300)],
            now: now)
        let fallback = try #require(Model.tokenSpeedSummary(quiet))
        #expect(fallback.title == L("token_speed_title_24h"))
        #expect(fallback.value == "50 tok/s")
        #expect(fallback.rows.isEmpty)
        #expect(Model.tokenSpeedSummary(nil) == nil)
        #expect(Model.tokenOutputSpeedLines(nil).isEmpty)
    }

    @Test
    func `speed model names are readable and unknown ids pass through`() {
        typealias Model = UsageMenuCardView.Model
        #expect(Model.tokenSpeedModelName("claude-opus-4-1-20250805") == "Opus 4.1")
        #expect(Model.tokenSpeedModelName("claude-3-5-sonnet") == "Sonnet 3.5")
        #expect(Model.tokenSpeedModelName("gpt-5-codex") == "GPT-5 Codex")
        #expect(Model.tokenSpeedModelName("gpt-5") == "GPT-5")
        #expect(Model.tokenSpeedModelName("codex-auto-review") == "Codex Auto Review")
        #expect(Model.tokenSpeedModelName("Custom Model") == "Custom Model")
    }

    @Test
    func `scanner reads only recent session files from the given roots`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("token-speed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let data = try Self.jsonl([
            ["type": "user", "uuid": "u1", "timestamp": formatter.string(from: now.addingTimeInterval(-20))],
            [
                "type": "assistant", "uuid": "m1", "parentUuid": "u1",
                "timestamp": formatter.string(from: now.addingTimeInterval(-10)),
                "message": ["id": "msg_1", "model": "claude-sonnet-4-5", "usage": ["output_tokens": 500]],
            ],
        ])
        let recent = project.appendingPathComponent("recent.jsonl")
        let stale = project.appendingPathComponent("stale.jsonl")
        try data.write(to: recent)
        try data.write(to: stale)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-3 * 24 * 60 * 60)],
            ofItemAtPath: stale.path)

        let snapshot = try #require(TokenOutputSpeedScanner().snapshot(
            provider: .claude,
            claudeProjectsRoots: [root],
            now: now))

        #expect(snapshot.models.count == 1)
        #expect(snapshot.models[0].requestCount == 1)
        #expect(snapshot.models[0].tokensPerSecond == 50)
    }
}
