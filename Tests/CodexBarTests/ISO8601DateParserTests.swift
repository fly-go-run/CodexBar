import Foundation
import Testing
@testable import CodexBarCore

struct ISO8601DateParserTests {
    private static func formatterDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return fractional.date(from: text) ?? plain.date(from: text)
    }

    @Test(arguments: [
        "2026-08-30T12:34:56Z",
        "2026-08-30T12:34:56.123Z",
        "2026-08-30T12:34:56.123456789Z",
        "2026-08-30T12:34:56+05:30",
        "2026-08-30T12:34:56.5-08:00",
        "2024-02-29T23:59:59.999Z",
        "2026-08-30T12:34:56+0530",
        "1582-10-04T12:34:56Z",
        "2026-08-30t12:34:56z",
        "2026-08-30",
        "not a date",
    ])
    func `parse matches the fractional then whole-second formatter`(text: String) {
        #expect(ISO8601DateParser.parse(text) == Self.formatterDate(text), "\(text)")
    }

    @Test
    func `parse reads fractional and whole-second timestamps`() {
        #expect(ISO8601DateParser.parse("1970-01-01T00:00:01Z") == Date(timeIntervalSince1970: 1))
        #expect(ISO8601DateParser.parse("1970-01-01T00:00:01.250Z") == Date(timeIntervalSince1970: 1.25))
        #expect(ISO8601DateParser.parse("1970-01-01T01:00:01+01:00") == Date(timeIntervalSince1970: 1))
    }

    @Test
    func `parse rejects missing and empty input`() {
        #expect(ISO8601DateParser.parse(nil) == nil)
        #expect(ISO8601DateParser.parse("") == nil)
    }

    @Test
    func `native path leaves non-RFC3339 spellings to the formatter`() {
        #expect(ISO8601DateParser.parseNativeRFC3339("2026-08-30T12:34:56+0530") == nil)
        #expect(ISO8601DateParser.parseNativeRFC3339("1582-10-04T12:34:56Z") == nil)
        #expect(ISO8601DateParser.parseNativeRFC3339("2026-08-30T12:34:56Z") != nil)
    }
}
