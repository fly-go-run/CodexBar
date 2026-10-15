import Foundation

/// Decides whether a Codex session row's model name is attributed to the Codex subscription.
///
/// Plain model names and `openai/`-prefixed names count. Any other provider prefix (for example a model routed
/// through a third-party gateway) is excluded from subscription coverage and spend.
enum CodexSubscriptionModel {
    static func countsTowardSubscription(modelName: String) -> Bool {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slash = trimmed.firstIndex(of: "/") else { return true }
        let prefix = trimmed[..<slash].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return prefix == "openai"
    }
}
