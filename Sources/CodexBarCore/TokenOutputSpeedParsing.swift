import Foundation

/// The few fields the speed parsers need from a session log line, read without decoding the line.
struct TokenSpeedLineFields {
    var type: String?
    var uuid: String?
    var timestamp: String?
    var hasPayloadObject = false
    var payloadType: String?
    var payloadRole: String?
    var payloadModel: String?
}

/// Single-pass, allocation-free reader for the top-level `type` / `uuid` / `timestamp` strings and the
/// `payload.type` / `payload.role` / `payload.model` strings of one JSON object line. Session logs hold
/// huge tool outputs and base64 images that the speed parsers never look at, so skipping the generic
/// JSON decode for them is most of the scan cost.
enum TokenSpeedLineExtractor {
    /// Returns nil when the line cannot be read this way (not an object, unbalanced, or a field of
    /// interest contains escapes or invalid UTF-8); callers then fall back to a full decode so results
    /// stay identical. With `allowIncomplete` a line cut off at the byte cap still yields the fields
    /// seen before the cut.
    static func extract(_ bytes: UnsafeBufferPointer<UInt8>, allowIncomplete: Bool) -> TokenSpeedLineFields? {
        var reader = Reader(bytes: bytes)
        return reader.run(allowIncomplete: allowIncomplete)
    }

    private struct Reader {
        enum TopKey {
            case type, uuid, timestamp, payload, other

            var bit: UInt8 {
                switch self {
                case .type: 0
                case .uuid: 1
                case .timestamp: 2
                case .payload: 3
                case .other: 7
                }
            }
        }

        enum PayloadKey {
            case type, role, model, other

            var bit: UInt8 {
                switch self {
                case .type: 0
                case .role: 1
                case .model: 2
                case .other: 7
                }
            }
        }

        enum StringResult { case read, unterminated, unreadable }

        let bytes: UnsafeBufferPointer<UInt8>
        var index = 0
        var depth = 0
        var expectTopKey = true
        var topKey = TopKey.other
        var inPayload = false
        var expectPayloadKey = false
        var payloadKey = PayloadKey.other
        /// Bit sets of recognized keys already seen at this level. JSONSerialization keeps the last of
        /// duplicate keys, so a repeat sends the line to the full decoder instead of guessing.
        var seenTopKeys: UInt8 = 0
        var seenPayloadKeys: UInt8 = 0
        var fields = TokenSpeedLineFields()

        init(bytes: UnsafeBufferPointer<UInt8>) {
            self.bytes = bytes
        }

        mutating func run(allowIncomplete: Bool) -> TokenSpeedLineFields? {
            let count = self.bytes.count
            while self.index < count, Self.isWhitespace(self.bytes[self.index]) {
                self.index += 1
            }
            guard self.index < count, self.bytes[self.index] == 0x7B else { return nil }
            self.index += 1
            self.depth = 1

            while self.index < count {
                let byte = self.bytes[self.index]
                switch byte {
                case 0x22:
                    switch self.readString() {
                    case .read: break
                    case .unterminated: return allowIncomplete ? self.fields : nil
                    case .unreadable: return nil
                    }
                    continue
                case 0x7B, 0x5B:
                    self.open(isObject: byte == 0x7B)
                case 0x7D, 0x5D:
                    self.depth -= 1
                    if self.depth == 1 { self.inPayload = false }
                    if self.depth == 0 { return self.fields }
                case 0x2C:
                    self.comma()
                default:
                    break
                }
                self.index += 1
            }
            return allowIncomplete ? self.fields : nil
        }

        private mutating func open(isObject: Bool) {
            self.depth += 1
            if self.depth == 2, isObject, self.topKey == .payload, !self.expectTopKey {
                self.inPayload = true
                self.expectPayloadKey = true
                self.payloadKey = .other
                self.seenPayloadKeys = 0
                self.fields.hasPayloadObject = true
            }
        }

        private mutating func comma() {
            if self.depth == 1 {
                self.expectTopKey = true
                self.topKey = .other
            } else if self.depth == 2, self.inPayload {
                self.expectPayloadKey = true
                self.payloadKey = .other
            }
        }

        /// Consumes the string starting at `index` and leaves `index` just past its closing quote.
        private mutating func readString() -> StringResult {
            let count = self.bytes.count
            var end = self.index + 1
            var hasEscape = false
            while end < count {
                let current = self.bytes[end]
                if current == 0x5C {
                    hasEscape = true
                    end += 2
                    continue
                }
                if current == 0x22 { break }
                end += 1
            }
            guard end < count else { return .unterminated }
            let range = (self.index + 1)..<end
            let readable = if self.depth == 1 {
                self.topString(range, hasEscape: hasEscape)
            } else if self.depth == 2, self.inPayload {
                self.payloadString(range, hasEscape: hasEscape)
            } else {
                true
            }
            guard readable else { return .unreadable }
            self.index = end + 1
            return .read
        }

        private mutating func topString(_ range: Range<Int>, hasEscape: Bool) -> Bool {
            if self.expectTopKey {
                guard !hasEscape else { return false }
                self.topKey = self.classifyTop(range)
                self.expectTopKey = false
                guard self.topKey != .other else { return true }
                let bit = UInt8(1) << self.topKey.bit
                defer { self.seenTopKeys |= bit }
                return self.seenTopKeys & bit == 0
            }
            guard self.topKey != .other, self.topKey != .payload else { return true }
            guard !hasEscape, let value = self.string(range) else { return false }
            switch self.topKey {
            case .type: self.fields.type = value
            case .uuid: self.fields.uuid = value
            case .timestamp: self.fields.timestamp = value
            case .payload, .other: break
            }
            return true
        }

        private mutating func payloadString(_ range: Range<Int>, hasEscape: Bool) -> Bool {
            if self.expectPayloadKey {
                guard !hasEscape else { return false }
                self.payloadKey = self.classifyPayload(range)
                self.expectPayloadKey = false
                guard self.payloadKey != .other else { return true }
                let bit = UInt8(1) << self.payloadKey.bit
                defer { self.seenPayloadKeys |= bit }
                return self.seenPayloadKeys & bit == 0
            }
            guard self.payloadKey != .other else { return true }
            guard !hasEscape, let value = self.string(range) else { return false }
            switch self.payloadKey {
            case .type: self.fields.payloadType = value
            case .role: self.fields.payloadRole = value
            case .model: self.fields.payloadModel = value
            case .other: break
            }
            return true
        }

        private func string(_ range: Range<Int>) -> String? {
            String(bytes: UnsafeBufferPointer(rebasing: self.bytes[range]), encoding: .utf8)
        }

        private func matches(_ range: Range<Int>, _ literal: StaticString) -> Bool {
            guard range.count == literal.utf8CodeUnitCount, let base = self.bytes.baseAddress else { return false }
            return memcmp(base + range.lowerBound, literal.utf8Start, range.count) == 0
        }

        private func classifyTop(_ range: Range<Int>) -> TopKey {
            if self.matches(range, "type") { return .type }
            if self.matches(range, "uuid") { return .uuid }
            if self.matches(range, "timestamp") { return .timestamp }
            if self.matches(range, "payload") { return .payload }
            return .other
        }

        private func classifyPayload(_ range: Range<Int>) -> PayloadKey {
            if self.matches(range, "type") { return .type }
            if self.matches(range, "role") { return .role }
            if self.matches(range, "model") { return .model }
            return .other
        }

        private static func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }
    }
}

/// Claude Code writes one line per content block; lines of one response share `message.id`
/// and carry the final `usage.output_tokens`. A response's first line points (`parentUuid`)
/// at the entry that triggered the request — a prompt, tool result, or attachment.
///
/// The parser is incremental: it keeps the entry-time map and the requests seen so far, so feeding
/// it only the bytes appended to a log gives the same result as parsing the whole file again.
struct ClaudeSessionParser: Sendable {
    private struct Request {
        let model: String
        let startedAt: Date
        var completedAt: Date
        var outputTokens: Int
    }

    private var entryTimes: [String: Date] = [:]
    /// `.some(nil)` marks a response whose start is unknown, so later blocks must not revive it.
    private var requests: [String: Request?] = [:]
    private var order: [String] = []

    var samples: [TokenOutputSpeedSample] {
        self.order.compactMap { id in
            guard case let .some(request?) = self.requests[id] else { return nil }
            return TokenOutputSpeedSample(
                model: request.model,
                outputTokens: request.outputTokens,
                startedAt: request.startedAt,
                completedAt: request.completedAt)
        }
    }

    /// Responses are fully decoded since their usage sits at the tail, so a line cut off at the byte
    /// cap is unusable. Every other entry only needs uuid + timestamp, which the extractor reads
    /// without decoding the (often huge) tool output or image payload.
    mutating func consume(line: Data, truncated: Bool) {
        guard !truncated else { return }
        let fields = line.withUnsafeBytes { raw -> TokenSpeedLineFields? in
            TokenSpeedLineExtractor.extract(raw.bindMemory(to: UInt8.self), allowIncomplete: false)
        }
        if let fields, fields.type != "assistant" {
            if let uuid = fields.uuid, let timestamp = fields.timestamp.flatMap(Self.parseTimestamp) {
                self.entryTimes[uuid] = timestamp
            }
            return
        }
        if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
            self.consume(object: object)
        }
    }

    mutating func consume(object: [String: Any]) {
        guard let timestamp = (object["timestamp"] as? String).flatMap(Self.parseTimestamp) else { return }
        guard let uuid = object["uuid"] as? String else { return }
        self.entryTimes[uuid] = timestamp
        guard object["type"] as? String == "assistant" else { return }
        guard let message = object["message"] as? [String: Any],
              let id = message["id"] as? String,
              let model = message["model"] as? String,
              model != "<synthetic>"
        else { return }
        let output = ((message["usage"] as? [String: Any])?["output_tokens"] as? NSNumber)?.intValue

        if let existing = self.requests[id] {
            guard var request = existing else { return }
            request.completedAt = max(request.completedAt, timestamp)
            if let output { request.outputTokens = max(request.outputTokens, output) }
            self.requests[id] = request
            return
        }
        self.order.append(id)
        guard let parent = object["parentUuid"] as? String,
              let startedAt = self.entryTimes[parent],
              startedAt <= timestamp
        else {
            self.requests[id] = .some(nil)
            return
        }
        self.requests[id] = Request(
            model: model,
            startedAt: startedAt,
            completedAt: timestamp,
            outputTokens: output ?? 0)
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        CostUsageScanner.dateFromTimestamp(raw)
    }
}

/// Codex rollouts: a request starts at the user message or tool output that precedes it,
/// ends at the last model output item, and `token_count.info.last_token_usage` reports its
/// output tokens (reasoning included). `token_count` is often logged after the tool output
/// that already belongs to the next request, so that input is held until the count lands.
///
/// Incremental like `ClaudeSessionParser`: model, startedAt, completedAt and nextStartedAt carry
/// across appended chunks.
struct CodexSessionParser: Sendable {
    private(set) var samples: [TokenOutputSpeedSample] = []
    private var model: String?
    private var startedAt: Date?
    private var completedAt: Date?
    private var nextStartedAt: Date?

    mutating func consume(line: Data, truncated: Bool) {
        let fields = line.withUnsafeBytes { raw -> TokenSpeedLineFields? in
            TokenSpeedLineExtractor.extract(raw.bindMemory(to: UInt8.self), allowIncomplete: truncated)
        }
        guard let fields else {
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                self.consume(object: object)
            }
            return
        }
        guard fields.hasPayloadObject, let type = fields.type else { return }
        switch type {
        case "turn_context", "response_item":
            break
        case "event_msg":
            // Only token counts matter, and they are small; decode them for the nested usage.
            guard fields.payloadType == "token_count", !truncated,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { return }
            self.consume(object: object)
            return
        default:
            return
        }
        guard let timestamp = fields.timestamp.flatMap(Self.parseTimestamp) else { return }
        self.apply(
            Line(
                type: type,
                payloadType: fields.payloadType,
                role: fields.payloadRole,
                payloadModel: fields.payloadModel,
                outputTokens: nil),
            at: timestamp)
    }

    mutating func consume(object: [String: Any]) {
        guard let timestamp = (object["timestamp"] as? String).flatMap(Self.parseTimestamp),
              let payload = object["payload"] as? [String: Any]
        else { return }
        let info = payload["info"] as? [String: Any]
        let last = info?["last_token_usage"] as? [String: Any]
        self.apply(
            Line(
                type: object["type"] as? String,
                payloadType: payload["type"] as? String,
                role: payload["role"] as? String,
                payloadModel: payload["model"] as? String,
                outputTokens: (last?["output_tokens"] as? NSNumber)?.intValue),
            at: timestamp)
    }

    private struct Line {
        let type: String?
        let payloadType: String?
        let role: String?
        let payloadModel: String?
        let outputTokens: Int?
    }

    private mutating func apply(_ line: Line, at timestamp: Date) {
        switch (line.type, line.payloadType) {
        case ("turn_context", _):
            if let payloadModel = line.payloadModel, !payloadModel.isEmpty { self.model = payloadModel }
        case ("response_item", "message"):
            switch line.role {
            case "assistant": self.output(timestamp)
            case "user": self.input(timestamp)
            default: break
            }
        case ("response_item", "function_call_output"), ("response_item", "custom_tool_call_output"):
            self.input(timestamp)
        case ("response_item", _):
            self.output(timestamp)
        case ("event_msg", "token_count"):
            guard let start = self.startedAt, let end = self.completedAt else { return }
            guard let outputTokens = line.outputTokens else { return }
            if let model = self.model {
                self.samples.append(TokenOutputSpeedSample(
                    model: model,
                    outputTokens: outputTokens,
                    startedAt: start,
                    completedAt: end))
            }
            self.startedAt = self.nextStartedAt
            self.completedAt = nil
            self.nextStartedAt = nil
        default:
            break
        }
    }

    private mutating func input(_ timestamp: Date) {
        if self.completedAt == nil {
            self.startedAt = timestamp
        } else {
            self.nextStartedAt = timestamp
        }
    }

    private mutating func output(_ timestamp: Date) {
        if let next = self.nextStartedAt {
            // The previous request never reported tokens; start over from the newer input.
            self.startedAt = next
            self.nextStartedAt = nil
        }
        if self.startedAt != nil { self.completedAt = timestamp }
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        CostUsageScanner.dateFromTimestamp(raw)
    }
}
