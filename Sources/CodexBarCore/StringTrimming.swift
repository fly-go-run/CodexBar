import Foundation

extension String {
    /// The string without surrounding whitespace and newlines, or nil when nothing is left.
    package var trimmedNonEmpty: String? {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension String? {
    /// The wrapped string without surrounding whitespace and newlines, or nil when nothing is left.
    package var trimmedNonEmpty: String? {
        self?.trimmedNonEmpty
    }
}
