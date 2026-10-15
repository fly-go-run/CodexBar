import Foundation

/// Shared, lock-guarded ISO8601 formatters. Allocating a fresh `ISO8601DateFormatter` per parsed
/// field is a measurable share of decoding status feeds (#1399) and cost logs.
private final class ISO8601FormatterBox: @unchecked Sendable {
    let lock = NSLock()
    let withFractional: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    let plain: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt
    }()
}

/// Parses RFC 3339 internet date-times with or without fractional seconds.
enum ISO8601DateParser {
    private static let box = ISO8601FormatterBox()

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = self.parseNativeRFC3339(raw) {
            return date
        }
        return self.parseWithFormatter(raw)
    }

    /// The `ISO8601DateFormatter` path: fractional seconds first, then whole seconds.
    static func parseWithFormatter(_ text: String) -> Date? {
        self.box.lock.lock()
        defer { self.box.lock.unlock() }
        return self.box.withFractional.date(from: text) ?? self.box.plain.date(from: text)
    }

    /// Keep historical ISO log spellings on the formatter path. Foundation handles calendar
    /// conversion; explicit milliseconds preserve ICU truncation and Date rounding.
    static func parseNativeRFC3339(_ text: String) -> Date? {
        let bytes = Array(text.utf8)
        guard bytes.count >= 20, bytes[4] == 45, bytes[7] == 45, bytes[10] == 84,
              bytes[13] == 58, bytes[16] == 58 else { return nil }
        func number(_ start: Int, _ count: Int = 2) -> Int? {
            var value = 0
            for byte in bytes[start..<(start + count)] {
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }
        guard let year = number(0, 4), year >= 1900,
              let month = number(5), (1...12).contains(month),
              let day = number(8), day >= 1,
              let hour = number(11), hour < 24,
              let minute = number(14), minute < 60,
              let second = number(17), second < 60 else { return nil }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard day <= days[month - 1] else { return nil }
        var zoneIndex = 19
        var milliseconds = 0
        if bytes[zoneIndex] == 46 {
            zoneIndex += 1
            let start = zoneIndex
            while zoneIndex < bytes.count, bytes[zoneIndex] >= 48, bytes[zoneIndex] <= 57 {
                let digitIndex = zoneIndex - start
                if digitIndex < 3 {
                    milliseconds += Int(bytes[zoneIndex] - 48) * [100, 10, 1][digitIndex]
                }
                zoneIndex += 1
            }
            guard zoneIndex > start, zoneIndex - start <= 9 else { return nil }
        }
        guard zoneIndex < bytes.count else { return nil }
        if bytes[zoneIndex] == 90 {
            guard bytes.count == zoneIndex + 1 else { return nil }
        } else {
            guard bytes.count == zoneIndex + 6, bytes[zoneIndex] == 43 || bytes[zoneIndex] == 45,
                  bytes[zoneIndex + 3] == 58, let hours = number(zoneIndex + 1), hours < 24,
                  let minutes = number(zoneIndex + 4), minutes < 60 else { return nil }
        }
        guard let whole = zoneIndex == 19 ? text : String(bytes: bytes[..<19] + bytes[zoneIndex...], encoding: .utf8)
        else { return nil }
        guard let date = try? Date.ISO8601FormatStyle().parse(whole) else { return nil }
        return Date(timeIntervalSince1970: date.timeIntervalSince1970 + Double(milliseconds) / 1000)
    }
}
