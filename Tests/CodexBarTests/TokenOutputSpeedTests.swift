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
    func `claude requests run from the first token of their thinking block to the last block`() throws {
        let data = try Self.jsonl([
            ["type": "user", "uuid": "u1", "timestamp": "2026-10-10T11:37:00.000Z"],
            // The first block streamed for 1.5s before it was written: the first token came at 11:37:01.5, and the
            // wait since the prompt is not generation time.
            [
                "type": "assistant", "uuid": "m1", "parentUuid": "u1", "timestamp": "2026-10-10T11:37:03.000Z",
                "thinkingDurationMs": 1500,
                "message": ["id": "msg_1", "model": "claude-opus-4-1", "usage": ["output_tokens": 400]],
            ],
            [
                "type": "assistant", "uuid": "m2", "parentUuid": "m1", "timestamp": "2026-10-10T11:37:05.000Z",
                "message": ["id": "msg_1", "model": "claude-opus-4-1", "usage": ["output_tokens": 400]],
            ],
            // Opens without a thinking block: its first token is unknown, so it is not measured at all, even
            // when a later block of the same response carries a thinking duration.
            [
                "type": "assistant", "uuid": "m3", "parentUuid": "m2", "timestamp": "2026-10-10T11:38:00.000Z",
                "message": ["id": "msg_2", "model": "claude-opus-4-1", "usage": ["output_tokens": 50]],
            ],
            [
                "type": "assistant", "uuid": "m4", "parentUuid": "m3", "timestamp": "2026-10-10T11:38:02.000Z",
                "thinkingDurationMs": 1000,
                "message": ["id": "msg_2", "model": "claude-opus-4-1", "usage": ["output_tokens": 50]],
            ],
            [
                "type": "assistant", "uuid": "m5", "parentUuid": "m4", "timestamp": "2026-10-10T11:38:03.000Z",
                "thinkingDurationMs": 100,
                "message": ["id": "msg_3", "model": "<synthetic>", "usage": ["output_tokens": 0]],
            ],
            [
                "type": "assistant", "uuid": "m6", "timestamp": "2026-10-10T11:39:02.000Z",
                "thinkingDurationMs": 2000,
                "message": ["id": "msg_4", "model": "claude-opus-4-1", "usage": ["output_tokens": 100]],
            ],
        ])

        let samples = TokenOutputSpeedScanner.parseClaudeSession(data)

        #expect(samples.count == 2)
        let sample = try #require(samples.first)
        #expect(sample.model == "claude-opus-4-1")
        #expect(sample.outputTokens == 400)
        #expect(try sample.startedAt == (Self.date("2026-10-10T11:37:01.500Z")))
        #expect(sample.durationSeconds == 3.5)
        #expect(samples.last?.durationSeconds == 2)
    }

    @Test
    func `codex requests run from the first output item's start to the last output item`() throws {
        func item(_ ts: String, _ payload: [String: Any]) -> [String: Any] {
            ["timestamp": ts, "type": "response_item", "payload": payload]
        }
        func completed(_ ts: String, _ type: String, startedAt: String) throws -> [String: Any] {
            let started = try Self.date(startedAt).timeIntervalSince1970 * 1000
            return [
                "timestamp": ts, "type": "event_msg",
                "payload": ["type": "item_completed", "item": ["type": type], "started_at_ms": started],
            ]
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
            completed("2026-10-08T14:30:19.600Z", "UserMessage", startedAt: "2026-10-08T14:30:19.500Z"),
            // The wait for the first token (19.5s to 21s) is not generation time.
            completed("2026-10-08T14:30:22.000Z", "Reasoning", startedAt: "2026-10-08T14:30:21.000Z"),
            item("2026-10-08T14:30:22.000Z", ["type": "reasoning"]),
            item("2026-10-08T14:30:24.500Z", ["type": "custom_tool_call"]),
            // The tool runs after its call was written: neither its events nor its run time count.
            completed("2026-10-08T14:30:29.000Z", "CommandExecution", startedAt: "2026-10-08T14:30:24.600Z"),
            item("2026-10-08T14:30:30.000Z", ["type": "custom_tool_call_output"]),
            tokens("2026-10-08T14:30:30.001Z", 250),
            // Duplicate token_count for the same request must not produce a second sample.
            tokens("2026-10-08T14:30:30.002Z", 250),
            completed("2026-10-08T14:30:32.000Z", "AgentMessage", startedAt: "2026-10-08T14:30:31.000Z"),
            // A later item does not move the start of the first one.
            completed("2026-10-08T14:30:32.000Z", "Reasoning", startedAt: "2026-10-08T14:30:31.500Z"),
            item("2026-10-08T14:30:32.000Z", ["type": "message", "role": "assistant"]),
            tokens("2026-10-08T14:30:32.100Z", 120),
            // Opens with a tool call, so the first token is unknown and the request is not measured.
            item("2026-10-08T14:30:40.000Z", ["type": "message", "role": "user"]),
            item("2026-10-08T14:30:45.000Z", ["type": "function_call"]),
            tokens("2026-10-08T14:30:45.100Z", 80),
            // A user message without any model output yet never yields a sample.
            item("2026-10-08T14:31:00.000Z", ["type": "message", "role": "user"]),
            tokens("2026-10-08T14:31:00.100Z", 99),
        ])

        let samples = TokenOutputSpeedScanner.parseCodexSession(data)

        #expect(samples.count == 2)
        #expect(samples.map(\.outputTokens) == [250, 120])
        #expect(samples.map(\.durationSeconds) == [3.5, 1])
        #expect(try samples[1].startedAt == (Self.date("2026-10-08T14:30:31.000Z")))
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
        #expect(snapshot.lastHourModels.map(\.model) == ["opus", "sonnet"])
        #expect(snapshot.lastHourModels.map(\.tokensPerSecond) == [100, 50])
    }

    private static func speedSample(
        _ model: String,
        _ tokens: Int,
        minutesAgo: Double,
        seconds: TimeInterval = 10,
        now: Date) -> TokenOutputSpeedSample
    {
        let end = now.addingTimeInterval(-minutesAgo * 60)
        return TokenOutputSpeedSample(
            model: model, outputTokens: tokens, startedAt: end.addingTimeInterval(-seconds), completedAt: end)
    }

    @Test
    func `speed summary lists the models of the last hour with their own rates`() throws {
        let now = try Self.date("2026-10-10T12:00:00.000Z")
        func sample(
            _ model: String,
            _ tokens: Int,
            minutesAgo: Double,
            seconds: TimeInterval = 10) -> TokenOutputSpeedSample
        {
            Self.speedSample(model, tokens, minutesAgo: minutesAgo, seconds: seconds, now: now)
        }
        typealias Model = UsageMenuCardView.Model
        typealias Row = TokenSpeedSummary.Row
        let opus = "claude-opus-4-1-20250805"
        let sonnet = "claude-sonnet-4-5"
        let window24h = L("token_speed_window_24h")

        // Each model keeps its own rate, never a blend; one with too few requests this hour shows its 24h rate.
        let busy = TokenOutputSpeedSnapshot(
            samples: [
                sample(opus, 900, minutesAgo: 5),
                sample(opus, 900, minutesAgo: 10),
                sample(opus, 900, minutesAgo: 15),
                sample(sonnet, 600, minutesAgo: 20),
                sample(opus, 300, minutesAgo: 300),
            ],
            now: now)
        let summary = try #require(Model.tokenSpeedSummary(busy))
        #expect(summary.title == L("token_speed_title_last_hour"))
        // 90 tok/s now vs 75 over 24h for Opus: not slower, so nothing is flagged.
        #expect(summary.rows.map(\.headline) == [
            Row(model: "Opus 4.1", value: "90 tok/s", windowNote: nil, slowdownPercent: nil),
            Row(model: "Sonnet 4.5", value: "60 tok/s", windowNote: window24h, slowdownPercent: nil),
        ])
        #expect(summary.lines == [
            "\(L("token_speed_title_last_hour")) · Opus 4.1 90 tok/s",
            "Sonnet 4.5 (\(window24h)) 60 tok/s",
        ])
        #expect(Model.tokenOutputSpeedLines(busy) == summary.lines)

        // Models that only ran earlier in the day are not listed while the last hour is busy.
        let switched = TokenOutputSpeedSnapshot(
            samples: [
                sample(sonnet, 600, minutesAgo: 5),
                sample(sonnet, 600, minutesAgo: 10),
                sample(sonnet, 600, minutesAgo: 15),
                sample(opus, 5000, minutesAgo: 300, seconds: 100),
            ],
            now: now)
        let switchedSummary = try #require(Model.tokenSpeedSummary(switched))
        #expect(switchedSummary.rows.map(\.model) == ["Sonnet 4.5"])
        #expect(switchedSummary.rows.first?.value == "60 tok/s")

        // A slowdown compares the model with its own 24h average; a model under 10% of the output is left out.
        let slow = TokenOutputSpeedSnapshot(
            samples: [
                sample(opus, 300, minutesAgo: 5),
                sample(opus, 300, minutesAgo: 10),
                sample(opus, 300, minutesAgo: 15),
                sample(opus, 9000, minutesAgo: 300, seconds: 100),
                sample(sonnet, 50, minutesAgo: 20, seconds: 0.5),
            ],
            now: now)
        let slowSummary = try #require(Model.tokenSpeedSummary(slow))
        #expect(slowSummary.rows.map(\.headline) == [
            Row(model: "Opus 4.1", value: "30 tok/s", windowNote: nil, slowdownPercent: 61),
        ])
        #expect(slowSummary.lines == ["\(L("token_speed_title_last_hour")) · Opus 4.1 30 tok/s ↓61%"])

        // No model has enough requests this hour: the block lists the 24h models and their 24h rates.
        let quiet = TokenOutputSpeedSnapshot(
            samples: [
                sample(sonnet, 900, minutesAgo: 5),
                sample(sonnet, 900, minutesAgo: 10),
                sample(opus, 5000, minutesAgo: 300, seconds: 100),
            ],
            now: now)
        let fallback = try #require(Model.tokenSpeedSummary(quiet))
        #expect(fallback.title == L("token_speed_title_24h"))
        #expect(fallback.rows.map(\.headline) == [
            Row(model: "Opus 4.1", value: "50 tok/s", windowNote: nil, slowdownPercent: nil),
            Row(model: "Sonnet 4.5", value: "90 tok/s", windowNote: nil, slowdownPercent: nil),
        ])
        #expect(Model.tokenSpeedSummary(nil) == nil)
        #expect(Model.tokenOutputSpeedLines(nil).isEmpty)
    }

    @Test
    func `speed summary caps the block at three models with a real share of the output`() throws {
        let now = try Self.date("2026-10-10T12:00:00.000Z")
        func busy(_ model: String, _ tokens: Int) -> [TokenOutputSpeedSample] {
            (1...3).map { Self.speedSample(model, tokens, minutesAgo: Double($0) * 5, now: now) }
        }
        let snapshot = TokenOutputSpeedSnapshot(
            samples: busy("model-a", 1000) + busy("model-b", 800) + busy("model-c", 600) + busy("model-d", 500)
                + busy("model-e", 30),
            now: now)
        let summary = try #require(UsageMenuCardView.Model.tokenSpeedSummary(snapshot))
        #expect(summary.rows.map(\.model) == ["Model A", "Model B", "Model C"])
        #expect(summary.rows.map(\.value) == ["100 tok/s", "80 tok/s", "60 tok/s"])

        func twice(_ model: String, _ tokens: Int) -> [TokenOutputSpeedSample] {
            (1...2).map { Self.speedSample(model, tokens, minutesAgo: Double($0) * 5, now: now) }
        }
        // The leader stays even when no model reaches 10% of the output or enough requests on its own.
        let spread = TokenOutputSpeedSnapshot(
            samples: (0..<12).flatMap { twice("model-\($0)", 100 - $0) },
            now: now)
        let spreadSummary = try #require(UsageMenuCardView.Model.tokenSpeedSummary(spread))
        #expect(spreadSummary.rows.map(\.model) == ["Model 0"])
    }

    @Test
    func `speed summary keeps a small model the user ran enough requests on`() throws {
        let now = try Self.date("2026-10-10T12:00:00.000Z")
        func samples(_ model: String, _ tokens: Int, count: Int) -> [TokenOutputSpeedSample] {
            (1...count).map { Self.speedSample(model, tokens, minutesAgo: Double($0), now: now) }
        }
        // Sonnet is well under 10% of the hour's output but has three requests; Haiku has two and stays out.
        let snapshot = TokenOutputSpeedSnapshot(
            samples: samples("claude-opus-4-1", 900, count: 40)
                + samples("claude-sonnet-4-5", 600, count: 3)
                + samples("claude-haiku-4-5", 400, count: 2),
            now: now)
        let summary = try #require(UsageMenuCardView.Model.tokenSpeedSummary(snapshot))
        #expect(summary.title == L("token_speed_title_last_hour"))
        #expect(summary.rows.map(\.model) == ["Opus 4.1", "Sonnet 4.5"])
        #expect(summary.rows.map(\.value) == ["90 tok/s", "60 tok/s"])
    }

    @Test
    func `cost submenu lists every model of the day with its own window`() throws {
        let now = try Self.date("2026-10-10T12:00:00.000Z")
        func busy(_ model: String, _ tokens: Int, seconds: TimeInterval = 10) -> [TokenOutputSpeedSample] {
            (1...3).map { Self.speedSample(model, tokens, minutesAgo: Double($0) * 5, seconds: seconds, now: now) }
        }
        let opus = "claude-opus-4-1-20250805"
        let sonnet = "claude-sonnet-4-5"
        let haiku = "claude-haiku-4-5"
        // Opus is busy this hour and slower than earlier; Sonnet and a tiny Haiku share only ran earlier, which
        // the card leaves out but the submenu still lists with their 24h rates.
        let snapshot = TokenOutputSpeedSnapshot(
            samples: busy(opus, 300) + [
                Self.speedSample(opus, 9000, minutesAgo: 300, seconds: 100, now: now),
                Self.speedSample(sonnet, 800, minutesAgo: 200, now: now),
                Self.speedSample(sonnet, 1000, minutesAgo: 400, now: now),
                Self.speedSample(haiku, 40, minutesAgo: 90, seconds: 0.5, now: now),
            ],
            now: now)
        typealias Model = UsageMenuCardView.Model
        #expect(Model.tokenSpeedSummary(snapshot)?.rows.map(\.model) == ["Opus 4.1"])

        let summary = try #require(Model.tokenSpeedAllModelsSummary(snapshot))
        #expect(summary.rows.map(\.model) == ["Opus 4.1", "Sonnet 4.5", "Haiku 4.5"])
        #expect(summary.rows.map(\.value) == ["30 tok/s", "90 tok/s", "80 tok/s"])
        #expect(summary.rows.map(\.slowdownPercent) == [61, nil, nil])
        #expect(summary.rows.map(\.detail) == [
            [
                L("token_speed_window_last_hour"),
                L("token_speed_vs_day_slower", "61"),
                L("token_speed_requests", codexBarLocalizedInteger(3)),
            ].joined(separator: " · "),
            "\(L("token_speed_window_24h")) · \(L("token_speed_requests", codexBarLocalizedInteger(2)))",
            "\(L("token_speed_window_24h")) · \(L("token_speed_requests", codexBarLocalizedInteger(1)))",
        ])
        #expect(summary.rows.first?.detailIsWarning == true)
        #expect(summary.requestCount == 7)
        #expect(Model.tokenSpeedAllModelsSummary(nil) == nil)
    }

    @Test
    func `snapshot keeps each model's median request and its recent active periods`() throws {
        let now = try Self.date("2026-10-10T12:00:00.000Z")
        let snapshot = TokenOutputSpeedSnapshot(
            samples: [
                Self.speedSample("opus", 1000, minutesAgo: 2, now: now),
                Self.speedSample("opus", 300, minutesAgo: 5, now: now),
                Self.speedSample("opus", 600, minutesAgo: 25, now: now),
                Self.speedSample("opus", 400, minutesAgo: 600, now: now),
            ],
            now: now)

        // Per-request rates 100, 30, 60 in the last hour and 40 earlier.
        #expect(snapshot.lastHourModels.first?.medianTokensPerSecond == 60)
        #expect(snapshot.models.first?.medianTokensPerSecond == 50)
        // Idle periods are skipped: ten hours ago sits right before the last half hour.
        #expect(snapshot.recentRates["opus"] == [40, 60, 65])
    }

    @Test
    func `recent periods keep only the latest twelve`() throws {
        let now = try Self.date("2026-10-10T12:00:00.000Z")
        let samples = (0..<15).map { index in
            Self.speedSample("opus", 100 * (index + 1), minutesAgo: Double(index) * 10 + 1, now: now)
        }
        let snapshot = TokenOutputSpeedSnapshot(samples: samples, now: now)
        let recent = try #require(snapshot.recentRates["opus"])
        #expect(recent.count == TokenOutputSpeedSnapshot.recentPeriodCount)
        #expect(recent.first == 120)
        #expect(recent.last == 10)
    }

    @Test
    func `speed rows compare the last hour with the model's own 24h average`() throws {
        let now = try Self.date("2026-10-10T12:00:00.000Z")
        let opus = "claude-opus-4-1-20250805"
        let sonnet = "claude-sonnet-4-5"
        let snapshot = TokenOutputSpeedSnapshot(
            samples: [
                Self.speedSample(opus, 900, minutesAgo: 5, now: now),
                Self.speedSample(opus, 900, minutesAgo: 10, now: now),
                Self.speedSample(opus, 900, minutesAgo: 15, now: now),
                Self.speedSample(sonnet, 600, minutesAgo: 20, now: now),
                Self.speedSample(opus, 300, minutesAgo: 300, now: now),
            ],
            now: now)
        let summary = try #require(UsageMenuCardView.Model.tokenSpeedSummary(snapshot))

        #expect(summary.heading == L("token_speed_heading"))
        #expect(summary.requestCount == 4)
        #expect(summary.windowSummary
            == "\(L("token_speed_window_last_hour")) · \(L("token_speed_requests", codexBarLocalizedInteger(4)))")

        // 90 tok/s now against 75 over 24h.
        let lead = try #require(summary.rows.first)
        #expect(lead.rateText == "90")
        #expect(lead.baseline == 75)
        #expect(lead.trend == [30, 90, 90])
        #expect(lead.detail == L("token_speed_vs_day_faster", "20"))
        #expect(!lead.detailIsWarning)
        #expect(lead.help?.contains(L("token_speed_help_day", "75")) == true)

        // A model on its 24h rate has nothing to compare with, so it has no sentence.
        let fallback = try #require(summary.rows.last)
        #expect(fallback.windowNote == L("token_speed_window_24h"))
        #expect(fallback.baseline == 60)
        #expect(fallback.detail == nil)
    }

    @Test
    func `speed comparison reads steady near the average and warns only when clearly slower`() {
        typealias Model = UsageMenuCardView.Model
        #expect(Model.tokenSpeedComparison(rate: 103, average: 100) == L("token_speed_vs_day_same"))
        #expect(Model.tokenSpeedComparison(rate: 96, average: 100) == L("token_speed_vs_day_same"))
        #expect(Model.tokenSpeedComparison(rate: 111, average: 100) == L("token_speed_vs_day_faster", "11"))
        #expect(Model.tokenSpeedComparison(rate: 88, average: 100) == L("token_speed_vs_day_slower", "12"))
        #expect(Model.tokenSpeedComparison(rate: 50, average: 0) == L("token_speed_vs_day_same"))
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
                "timestamp": formatter.string(from: now.addingTimeInterval(-10)), "thinkingDurationMs": 10000,
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

        let snapshot = try #require(try TokenOutputSpeedScanner().snapshot(
            provider: .claude,
            claudeProjectsRoots: [root],
            now: now))

        #expect(snapshot.models.count == 1)
        #expect(snapshot.models[0].requestCount == 1)
        #expect(snapshot.models[0].tokensPerSecond == 50)
    }
}

// MARK: - Incremental scanning

struct TokenOutputSpeedIncrementalTests {
    private static func stamp(_ now: Date, _ secondsAgo: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: now.addingTimeInterval(-secondsAgo))
    }

    private static func jsonl(_ objects: [[String: Any]]) throws -> Data {
        var data = Data()
        for object in objects {
            try data.append(JSONSerialization.data(withJSONObject: object))
            data.append(0x0A)
        }
        return data
    }

    private static func lines(_ objects: [[String: Any]]) throws -> [Data] {
        try objects.map { try Self.jsonl([$0]) }
    }

    private static func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("token-speed-inc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("project", isDirectory: true),
            withIntermediateDirectories: true)
        return root
    }

    private static func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private static func byteCount(_ lines: some Sequence<Data>) -> Int64 {
        Int64(lines.reduce(0) { $0 + $1.count })
    }

    private static func claudeEntries(_ now: Date) -> [[String: Any]] {
        func assistant(
            _ uuid: String,
            parent: String,
            ago: Double,
            id: String,
            output: Int,
            thinkingSeconds: Double? = nil) -> [String: Any]
        {
            var entry: [String: Any] = [
                "type": "assistant", "uuid": uuid, "parentUuid": parent, "timestamp": self.stamp(now, ago),
                "message": ["id": id, "model": "claude-sonnet-4-5", "usage": ["output_tokens": output]],
            ]
            if let thinkingSeconds { entry["thinkingDurationMs"] = thinkingSeconds * 1000 }
            return entry
        }
        return [
            ["type": "user", "uuid": "u1", "timestamp": self.stamp(now, 100)],
            assistant("a1", parent: "u1", ago: 95, id: "msg_1", output: 500, thinkingSeconds: 3),
            assistant("a2", parent: "a1", ago: 90, id: "msg_1", output: 500),
            // Tool results mention assistant entries in nested payloads without being one.
            [
                "type": "user", "uuid": "u2", "parentUuid": "a2", "timestamp": self.stamp(now, 80),
                "toolUseResult": ["uuid": "nested", "type": "assistant", "timestamp": "bogus"],
                "message": ["content": [["type": "tool_result", "content": "\"type\":\"assistant\" caf\u{e9}"]]],
            ],
            assistant("a3", parent: "u2", ago: 70, id: "msg_2", output: 300, thinkingSeconds: 5),
            assistant("a4", parent: "a3", ago: 60, id: "msg_2", output: 300),
            ["type": "user", "uuid": "u3", "parentUuid": "a4", "timestamp": self.stamp(now, 50)],
            assistant("a5", parent: "u3", ago: 40, id: "msg_3", output: 200, thinkingSeconds: 5),
        ]
    }

    private static func codexEntries(_ now: Date) -> [[String: Any]] {
        func item(_ ago: Double, _ payload: [String: Any]) -> [String: Any] {
            ["timestamp": self.stamp(now, ago), "type": "response_item", "payload": payload]
        }
        func tokens(_ ago: Double, _ output: Int) -> [String: Any] {
            [
                "timestamp": self.stamp(now, ago), "type": "event_msg",
                "payload": ["type": "token_count", "info": ["last_token_usage": ["output_tokens": output]]],
            ]
        }
        func completed(_ ago: Double, _ type: String, startedAgo: Double) -> [String: Any] {
            [
                "timestamp": self.stamp(now, ago), "type": "event_msg",
                "payload": [
                    "type": "item_completed", "item": ["type": type],
                    "started_at_ms": (now.timeIntervalSince1970 - startedAgo) * 1000,
                ],
            ]
        }
        return [
            ["timestamp": self.stamp(now, 200), "type": "turn_context", "payload": ["model": "gpt-5"]],
            ["timestamp": self.stamp(now, 199), "type": "event_msg", "payload": ["type": "agent_message"]],
            item(198, ["type": "message", "role": "user"]),
            completed(195, "Reasoning", startedAgo: 197),
            item(195, ["type": "reasoning"]),
            item(190, ["type": "function_call_output", "output": String(repeating: "x", count: 500)]),
            tokens(189, 250),
            completed(180, "AgentMessage", startedAgo: 182),
            item(180, ["type": "message", "role": "assistant"]),
            tokens(179, 120),
            item(100, ["type": "message", "role": "user"]),
            completed(90, "AgentMessage", startedAgo: 95),
            item(90, ["type": "message", "role": "assistant"]),
            tokens(89, 400),
        ]
    }

    @Test
    func `appended claude lines scan to the same result as one full scan`() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let entries = try Self.lines(Self.claudeEntries(now))
        let file = root.appendingPathComponent("project/session.jsonl")
        // The first chunk ends before the second block of msg_2 is written, and the next append
        // is a half-written line that only the one after it completes.
        try Data(entries[0...3].joined()).write(to: file)
        let incremental = TokenOutputSpeedScanner()
        _ = try incremental.snapshot(provider: .claude, claudeProjectsRoots: [root], now: now)
        #expect(incremental.totalBytesParsed == Self.byteCount(entries[0...3]))

        let split = entries[4]
        try Self.append(Data(split.prefix(split.count / 2)), to: file)
        _ = try incremental.snapshot(provider: .claude, claudeProjectsRoots: [root], now: now)
        try Self.append(Data(split.dropFirst(split.count / 2)) + Data(entries[5...].joined()), to: file)
        let result = try incremental.snapshot(provider: .claude, claudeProjectsRoots: [root], now: now)

        let full = try TokenOutputSpeedScanner().snapshot(provider: .claude, claudeProjectsRoots: [root], now: now)
        #expect(result == full)
        #expect(result?.models.first?.requestCount == 3)
        // Every byte was parsed exactly once across the three scans.
        #expect(incremental.totalBytesParsed == Self.byteCount(entries))
    }

    @Test
    func `appended codex lines scan to the same result as one full scan`() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let entries = try Self.lines(Self.codexEntries(now))
        let sessions = root.appendingPathComponent("home/sessions/2026", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("rollout.jsonl")
        let codexHome = root.appendingPathComponent("home").path

        // Split between an output item and its token_count, and again between the last request's first item
        // starting and its output.
        try Data(entries[0...8].joined()).write(to: file)
        let incremental = TokenOutputSpeedScanner()
        _ = try incremental.snapshot(provider: .codex, codexHomePath: codexHome, now: now)
        try Self.append(Data(entries[9...11].joined()), to: file)
        _ = try incremental.snapshot(provider: .codex, codexHomePath: codexHome, now: now)
        try Self.append(Data(entries[12...].joined()), to: file)
        let result = try incremental.snapshot(provider: .codex, codexHomePath: codexHome, now: now)

        let full = try TokenOutputSpeedScanner().snapshot(provider: .codex, codexHomePath: codexHome, now: now)
        #expect(result == full)
        #expect(result?.models.first?.requestCount == 3)
        #expect(incremental.totalBytesParsed == Self.byteCount(entries))
    }

    @Test
    func `a shrunk or replaced log is parsed again from the start`() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let entries = try Self.lines(Self.claudeEntries(now))
        let file = root.appendingPathComponent("project/session.jsonl")
        let scanner = TokenOutputSpeedScanner()

        try Data(entries.joined()).write(to: file)
        let before = try scanner.snapshot(provider: .claude, claudeProjectsRoots: [root], now: now)
        #expect(before?.models.first?.requestCount == 3)

        // Truncated in place to a shorter log: nothing of the old state may survive.
        try Data(entries[0...2].joined()).write(to: file)
        let shrunk = try scanner.snapshot(provider: .claude, claudeProjectsRoots: [root], now: now)
        let shrunkFull = try TokenOutputSpeedScanner().snapshot(
            provider: .claude, claudeProjectsRoots: [root], now: now)
        #expect(shrunk == shrunkFull)
        #expect(shrunk?.models.first?.requestCount == 1)

        // Rotated: a new, larger file at the same path (new inode) with different content.
        try FileManager.default.removeItem(at: file)
        let rotated = try Self.jsonl(Self.claudeEntries(now).map { entry in
            var entry = entry
            if let uuid = entry["uuid"] as? String { entry["uuid"] = "r-\(uuid)" }
            if let parent = entry["parentUuid"] as? String { entry["parentUuid"] = "r-\(parent)" }
            return entry
        })
        try (rotated + Data(entries.joined())).write(to: file)
        let replaced = try scanner.snapshot(provider: .claude, claudeProjectsRoots: [root], now: now)
        let replacedFull = try TokenOutputSpeedScanner().snapshot(
            provider: .claude, claudeProjectsRoots: [root], now: now)
        #expect(replaced == replacedFull)
    }

    @Test
    func `a log rewritten in place with more bytes is not treated as an append`() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let file = root.appendingPathComponent("project/session.jsonl")
        let scanner = TokenOutputSpeedScanner()
        try Self.jsonl(Self.claudeEntries(now)).write(to: file)
        let inode = try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? Int
        _ = try scanner.snapshot(provider: .claude, claudeProjectsRoots: [root], now: now)

        // Same inode, larger, and none of the bytes already parsed survive: other model, other ids.
        let rewritten = Self.claudeEntries(now).map { entry -> [String: Any] in
            var entry = entry
            if let uuid = entry["uuid"] as? String { entry["uuid"] = "w-\(uuid)" }
            if let parent = entry["parentUuid"] as? String { entry["parentUuid"] = "w-\(parent)" }
            if var message = entry["message"] as? [String: Any], message["id"] != nil {
                message["id"] = "w-\(message["id"] ?? "")"
                message["model"] = "claude-opus-4-1"
                entry["message"] = message
            }
            return entry
        }
        try (Self.jsonl(rewritten) + Self.jsonl(rewritten)).write(to: file)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? Int == inode)

        let result = try scanner.snapshot(provider: .claude, claudeProjectsRoots: [root], now: now)
        let fresh = try TokenOutputSpeedScanner().snapshot(
            provider: .claude, claudeProjectsRoots: [root], now: now)
        #expect(result == fresh)
        #expect(result?.models.map(\.model) == ["claude-opus-4-1"])
    }

    @Test
    func `oversized lines are skipped without breaking the lines around them`() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let data = try Self.jsonl([
            ["type": "user", "uuid": "u1", "timestamp": Self.stamp(now, 100)],
            // Too long for the cap: its first-token time is never learned, so the response is dropped.
            [
                "type": "assistant", "uuid": "a1", "parentUuid": "u1", "timestamp": Self.stamp(now, 80),
                "thinkingDurationMs": 5000, "blob": String(repeating: "x", count: 10000),
                "message": ["id": "msg_1", "model": "claude-sonnet-4-5", "usage": ["output_tokens": 500]],
            ],
            [
                "type": "assistant", "uuid": "a2", "parentUuid": "a1", "timestamp": Self.stamp(now, 70),
                "thinkingDurationMs": 5000,
                "message": ["id": "msg_2", "model": "claude-sonnet-4-5", "usage": ["output_tokens": 300]],
            ],
        ])
        try data.write(to: root.appendingPathComponent("project/session.jsonl"))

        let capped = TokenOutputSpeedScanner(claudeMaxLineBytes: 2048, codexMaxLineBytes: 2048)
        let snapshot = try #require(try capped.snapshot(provider: .claude, claudeProjectsRoots: [root], now: now))
        #expect(snapshot.models.map(\.requestCount) == [1])
        #expect(snapshot.models[0].outputTokens == 300)
        // With the default cap the same log keeps both requests.
        let uncapped = try #require(try TokenOutputSpeedScanner().snapshot(
            provider: .claude, claudeProjectsRoots: [root], now: now))
        #expect(uncapped.models[0].requestCount == 2)
    }

    @Test
    func `an oversized codex output item still counts through its leading fields`() {
        func line(_ timestamp: String, _ type: String, _ payload: String) -> Data {
            Data(#"{"timestamp":"\#(timestamp)","type":"\#(type)","payload":\#(payload)}"#.utf8 + [0x0A])
        }
        let huge = String(repeating: "x", count: 10000)
        let cutOff = line(
            "2026-10-08T14:30:24.000Z",
            "response_item",
            #"{"type":"message","role":"assistant","content":"\#(huge)"}"#)
        var parser = CodexSessionParser()
        parser.consume(
            line: line("2026-10-08T14:30:19.000Z", "turn_context", #"{"model":"gpt-5"}"#),
            truncated: false)
        parser.consume(
            line: line("2026-10-08T14:30:20.000Z", "response_item", #"{"type":"message","role":"user"}"#),
            truncated: false)
        parser.consume(
            line: line(
                "2026-10-08T14:30:24.000Z",
                "event_msg",
                #"{"type":"item_completed","item":{"type":"AgentMessage"},"started_at_ms":1791469821000}"#),
            truncated: false)
        // The scanner hands over only the leading bytes of a line that exceeds the cap.
        parser.consume(line: Data(cutOff.prefix(200)), truncated: true)
        parser.consume(
            line: line(
                "2026-10-08T14:30:24.001Z",
                "event_msg",
                #"{"type":"token_count","info":{"last_token_usage":{"output_tokens":250}}}"#),
            truncated: false)

        #expect(parser.samples.map(\.outputTokens) == [250])
        #expect(parser.samples.first?.durationSeconds == 3)
    }

    @Test
    func `fast line extraction matches a full decode on awkward lines`() throws {
        let now = Date()
        let claude = try Self.lines(Self.claudeEntries(now)) + [
            Data(#"{"uuid":"escA","type":"user","timestamp":"\#(Self.stamp(now, 30))"}"#.utf8),
            Data(#"{"timestamp":"\#(Self.stamp(now, 20))","uuid":"u9","type":"user","type":"assistant"}"#.utf8),
            Data("not json".utf8),
            Data("[1,2,3]".utf8),
        ]
        var fast = ClaudeSessionParser()
        var reference = ClaudeSessionParser()
        for line in claude {
            fast.consume(line: line, truncated: false)
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                reference.consume(object: object)
            }
        }
        #expect(fast.samples == reference.samples)
        #expect(fast.samples.count == 3)

        let stamp = Self.stamp(now, 50)
        let codex = try Self.lines(Self.codexEntries(now)) + [
            Data(#"{"timestamp":"\#(stamp)","type":"response_item","payload":null}"#.utf8),
            Data(#"{"timestamp":"\#(stamp)","type":"response_item","payload":{"type":"reasoning"}}"#.utf8),
            Data(#"{"type":"response_item","payload":{"type":"reasoning"}}"#.utf8),
            Data(
                (#"{"timestamp":"\#(stamp)","type":"response_item","#
                    + #""payload":{"x":{"type":"message","role":"user"},"type":"custom_tool_call"}}"#).utf8),
        ]
        var fastCodex = CodexSessionParser()
        var referenceCodex = CodexSessionParser()
        for line in codex {
            fastCodex.consume(line: line, truncated: false)
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                referenceCodex.consume(object: object)
            }
        }
        #expect(fastCodex.samples == referenceCodex.samples)
        #expect(fastCodex.samples.count == 3)
    }

    @Test
    func `duplicate keys fall back to the full decoder`() {
        let now = Date()
        let stamp = Self.stamp(now, 40)
        func fields(_ json: String) -> TokenSpeedLineFields? {
            Array(json.utf8).withUnsafeBufferPointer {
                TokenSpeedLineExtractor.extract($0, allowIncomplete: false)
            }
        }
        let duplicatePayload = #"{"timestamp":"\#(stamp)","type":"response_item","#
            + #""payload":{"type":"message","role":"user"},"payload":null}"#
        let duplicateInner = #"{"timestamp":"\#(stamp)","type":"response_item","#
            + #""payload":{"type":"message","type":"reasoning","role":"user"}}"#
        let duplicateTop = #"{"timestamp":"\#(stamp)","type":"user","timestamp":"\#(stamp)"}"#
        #expect(fields(duplicatePayload) == nil)
        #expect(fields(duplicateInner) == nil)
        #expect(fields(duplicateTop) == nil)
        #expect(fields(#"{"timestamp":"\#(stamp)","type":"response_item","payload":{"type":"message"}}"#) != nil)

        // A null payload wins over the earlier object: that line must do nothing, as with a full decode.
        var fast = CodexSessionParser()
        var reference = CodexSessionParser()
        let lines = [
            #"{"timestamp":"\#(Self.stamp(now, 60))","type":"turn_context","payload":{"model":"gpt-5"}}"#,
            duplicatePayload,
            #"{"timestamp":"\#(Self.stamp(now, 55))","type":"response_item","#
                + #""payload":{"type":"message","role":"user"}}"#,
            #"{"timestamp":"\#(Self.stamp(now, 45))","type":"event_msg","payload":{"type":"item_completed","#
                + #""item":{"type":"Reasoning"},"started_at_ms":\#((now.timeIntervalSince1970 - 47) * 1000)}}"#,
            #"{"timestamp":"\#(Self.stamp(now, 45))","type":"response_item","payload":{"type":"reasoning"}}"#,
            #"{"timestamp":"\#(Self.stamp(now, 44))","type":"event_msg","payload":{"type":"token_count","#
                + #""info":{"last_token_usage":{"output_tokens":250}}}}"#,
        ].map { Data($0.utf8) }
        for line in lines {
            fast.consume(line: line, truncated: false)
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                reference.consume(object: object)
            }
        }
        #expect(fast.samples == reference.samples)
        #expect(fast.samples.count == 1)
    }

    @Test
    func `cache entries of files that left the window are evicted`() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let data = try Self.jsonl(Self.claudeEntries(now))
        let kept = root.appendingPathComponent("project/kept.jsonl")
        let aging = root.appendingPathComponent("project/aging.jsonl")
        try data.write(to: kept)
        try data.write(to: aging)
        let scanner = TokenOutputSpeedScanner()
        _ = try scanner.snapshot(provider: .claude, claudeProjectsRoots: [root], now: now)
        #expect(scanner.cachedFileCount(for: .claude) == 2)

        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-3 * 24 * 60 * 60)],
            ofItemAtPath: aging.path)
        _ = try scanner.snapshot(provider: .claude, claudeProjectsRoots: [root], now: now)
        #expect(scanner.cachedFileCount(for: .claude) == 1)

        try FileManager.default.removeItem(at: kept)
        _ = try scanner.snapshot(provider: .claude, claudeProjectsRoots: [root], now: now)
        #expect(scanner.cachedFileCount(for: .claude) == 0)
        #expect(scanner.cachedFileCount(for: .codex) == 0)
    }

    @Test
    func `a cancelled scan throws instead of returning a partial snapshot`() async throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        try Self.jsonl(Self.claudeEntries(now)).write(to: root.appendingPathComponent("project/session.jsonl"))
        let scanner = TokenOutputSpeedScanner()

        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return try scanner.snapshot(provider: .claude, claudeProjectsRoots: [root], now: now)
        }
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(scanner.cachedFileCount(for: .claude) == 0)
        // The next, uncancelled scan still works.
        #expect(try scanner.snapshot(provider: .claude, claudeProjectsRoots: [root], now: now) != nil)
    }

    @Test
    func `claude speed scans see claude swap profile sessions like cost tracking`() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("token-speed-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent(
            ".claude-swap-backup/sessions/2-work/projects/demo",
            isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let now = Date()
        try Self.jsonl(Self.claudeEntries(now)).write(to: project.appendingPathComponent("session.jsonl"))

        let snapshot = try TokenOutputSpeedScanner().snapshot(
            provider: .claude,
            environment: ["HOME": home.path],
            now: now)

        #expect(snapshot?.models.first?.requestCount == 3)
    }
}

extension TokenSpeedSummary.Row {
    /// The rate fields alone, without the trend and context line covered by their own tests.
    fileprivate var headline: Self {
        Self(model: self.model, value: self.value, windowNote: self.windowNote, slowdownPercent: self.slowdownPercent)
    }
}
