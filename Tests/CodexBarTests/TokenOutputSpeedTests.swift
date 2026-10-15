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
        func assistant(_ uuid: String, parent: String, ago: Double, id: String, output: Int) -> [String: Any] {
            [
                "type": "assistant", "uuid": uuid, "parentUuid": parent, "timestamp": self.stamp(now, ago),
                "message": ["id": id, "model": "claude-sonnet-4-5", "usage": ["output_tokens": output]],
            ]
        }
        return [
            ["type": "user", "uuid": "u1", "timestamp": self.stamp(now, 100)],
            assistant("a1", parent: "u1", ago: 95, id: "msg_1", output: 500),
            assistant("a2", parent: "a1", ago: 90, id: "msg_1", output: 500),
            // Tool results mention assistant entries in nested payloads without being one.
            [
                "type": "user", "uuid": "u2", "parentUuid": "a2", "timestamp": self.stamp(now, 80),
                "toolUseResult": ["uuid": "nested", "type": "assistant", "timestamp": "bogus"],
                "message": ["content": [["type": "tool_result", "content": "\"type\":\"assistant\" caf\u{e9}"]]],
            ],
            assistant("a3", parent: "u2", ago: 70, id: "msg_2", output: 300),
            assistant("a4", parent: "a3", ago: 60, id: "msg_2", output: 300),
            ["type": "user", "uuid": "u3", "parentUuid": "a4", "timestamp": self.stamp(now, 50)],
            assistant("a5", parent: "u3", ago: 40, id: "msg_3", output: 200),
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
        return [
            ["timestamp": self.stamp(now, 200), "type": "turn_context", "payload": ["model": "gpt-5"]],
            ["timestamp": self.stamp(now, 199), "type": "event_msg", "payload": ["type": "agent_message"]],
            item(198, ["type": "message", "role": "user"]),
            item(195, ["type": "reasoning"]),
            item(190, ["type": "function_call_output", "output": String(repeating: "x", count: 500)]),
            tokens(189, 250),
            item(180, ["type": "message", "role": "assistant"]),
            tokens(179, 120),
            item(100, ["type": "message", "role": "user"]),
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

        // Split between an output item and its token_count, and again inside the last request.
        try Data(entries[0...6].joined()).write(to: file)
        let incremental = TokenOutputSpeedScanner()
        _ = try incremental.snapshot(provider: .codex, codexHomePath: codexHome, now: now)
        try Self.append(Data(entries[7...8].joined()), to: file)
        _ = try incremental.snapshot(provider: .codex, codexHomePath: codexHome, now: now)
        try Self.append(Data(entries[9...].joined()), to: file)
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
    func `oversized lines are skipped without breaking the lines around them`() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let data = try Self.jsonl([
            ["type": "user", "uuid": "u1", "timestamp": Self.stamp(now, 100)],
            // Too long for the cap: its uuid is never learned, so the response it triggered is dropped.
            [
                "type": "user", "uuid": "u2", "timestamp": Self.stamp(now, 90),
                "blob": String(repeating: "x", count: 10000),
            ],
            [
                "type": "assistant", "uuid": "a1", "parentUuid": "u2", "timestamp": Self.stamp(now, 80),
                "message": ["id": "msg_1", "model": "claude-sonnet-4-5", "usage": ["output_tokens": 500]],
            ],
            [
                "type": "assistant", "uuid": "a2", "parentUuid": "u1", "timestamp": Self.stamp(now, 70),
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
        // The scanner hands over only the leading bytes of a line that exceeds the cap.
        parser.consume(line: Data(cutOff.prefix(200)), truncated: true)
        parser.consume(
            line: line(
                "2026-10-08T14:30:24.001Z",
                "event_msg",
                #"{"type":"token_count","info":{"last_token_usage":{"output_tokens":250}}}"#),
            truncated: false)

        #expect(parser.samples.map(\.outputTokens) == [250])
        #expect(parser.samples.first?.durationSeconds == 4)
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
