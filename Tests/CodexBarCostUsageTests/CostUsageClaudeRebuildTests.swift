import CryptoKit
import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageClaudeRebuildTests {
    static let now = Date(timeIntervalSince1970: 1_790_769_600) // 2026-09-30 12:00 UTC
    static var range: CostUsageScanner.CostUsageDayRange {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return .init(since: self.now.addingTimeInterval(-29 * 86400), until: self.now, calendar: calendar)
    }

    static func cache(fileCount: Int, rowsPerFile: Int, includeOverflow: Bool = false) -> CostUsageCache {
        var seed: UInt64 = 0xC1A0DE
        func next(_ limit: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int(seed >> 32) % limit
        }
        var cache = CostUsageCache(scanSinceKey: self.range.scanSinceKey, scanUntilKey: self.range.scanUntilKey)
        for file in 0..<fileCount {
            let subagent = file.isMultiple(of: 2)
            let path = String(format: "project/%05d/", file / 2)
                + (subagent ? "subagents/agent.jsonl" : "parent.jsonl")
            var rows: [CostUsageScanner.ClaudeUsageRow] = []
            for index in 0..<rowsPerFile {
                let identity = "\(file / 4)-\(index / 2)"
                let keyKind = index % 8
                let day = next(28) + 1
                rows.append(.init(
                    dayKey: String(format: "2026-09-%02d", day),
                    model: "fixture/model-\(next(3))",
                    sessionId: keyKind == 4 ? " \n\t" : "session-\(file / 4)",
                    messageId: keyKind == 5 ? nil : (keyKind == 6 ? " \n" : "message-\(identity)"),
                    requestId: keyKind < 3 ? "request-\(identity)" : nil,
                    timestampUnixMs: 1_788_264_000_000 + Int64(day - 1) * 86_400_000 + Int64(next(3600)) * 1000,
                    isSidechain: next(4) == 0,
                    pathRole: subagent ? .subagent : .parent,
                    input: next(10000),
                    cacheRead: next(1000),
                    cacheCreate: next(100),
                    cacheCreate1h: next(50),
                    output: next(100),
                    costNanos: next(10_000_000),
                    costPriced: next(5) == 0 ? nil : true,
                    isIncomplete: next(7) == 0 ? true : nil))
            }
            cache.files[path] = .init(mtimeUnixMs: 0, size: 3, days: [:], parsedBytes: 3, claudeRows: rows)
        }
        if includeOverflow {
            let row = CostUsageScanner.ClaudeUsageRow(
                dayKey: "2026-09-01",
                model: "fixture/overflow",
                sessionId: nil,
                messageId: nil,
                requestId: nil,
                timestampUnixMs: nil,
                isSidechain: false,
                pathRole: .parent,
                input: Int.max,
                cacheRead: 0,
                cacheCreate: 0,
                cacheCreate1h: nil,
                output: 1,
                costNanos: 1,
                costPriced: true)
            cache.files["overflow"] = .init(mtimeUnixMs: 0, size: 0, days: [:], claudeRows: [row, row])
        }
        return cache
    }

    private static func digest(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try SHA256.hash(data: encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }
}
