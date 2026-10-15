import Foundation

public enum ClaudeAdminAPISettingsReader {
    public static let workspaceSpendEnvironmentKey = "ANTHROPIC_ADMIN_WORKSPACE_SPEND"
    public static let adminAPIKeyEnvironmentKey = "ANTHROPIC_ADMIN_KEY"
    public static let alternateAdminAPIKeyEnvironmentKey = "ANTHROPIC_ADMIN_API_KEY"
    public static let apiKeyEnvironmentKeys = [
        Self.adminAPIKeyEnvironmentKey,
        Self.alternateAdminAPIKeyEnvironmentKey,
    ]

    public static func apiKey(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        SettingsValue.first(in: environment, keys: self.apiKeyEnvironmentKeys)
    }
}

public enum ClaudeAdminAPISettingsError: LocalizedError, Sendable {
    case missingToken

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            "Claude API usage needs an Anthropic Admin API key."
        }
    }
}
