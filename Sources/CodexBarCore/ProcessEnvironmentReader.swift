import Foundation

/// Bounded readers for a process's environment, limited to an explicit set of variable names.
enum ProcessEnvironmentReader {
    static let maxEnvironmentBytes = 1_048_576

    static func parseNULSeparated(_ data: Data, names: Set<String>) -> [String: String]? {
        guard data.count <= self.maxEnvironmentBytes,
              data.isEmpty || data.last == 0
        else { return nil }

        var selected: [String: String] = [:]
        // Byte-range search avoids walking large unrelated values through Data's generic split iterator.
        var remainder = data.drop(while: { $0 == 0 })
        while let end = remainder.range(of: Data([0]))?.lowerBound {
            let record = remainder[..<end]
            remainder = remainder[remainder.index(after: end)...].drop(while: { $0 == 0 })
            guard let separator = record.firstIndex(of: 61) else { return nil }
            guard let name = String(bytes: record[..<separator], encoding: .utf8),
                  names.contains(name)
            else { continue }
            let valueStart = record.index(after: separator)
            guard let value = String(bytes: record[valueStart...], encoding: .utf8) else { return nil }
            // Conflicting duplicate values cannot identify one process-owned value safely.
            if let previous = selected[name], previous != value { return nil }
            selected[name] = value
        }
        return selected
    }
}
