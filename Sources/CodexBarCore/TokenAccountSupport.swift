import Foundation

public struct TokenAccountSupport: Sendable {
    public let title: String
    public let subtitle: String
    public let placeholder: String
    public let requiresManualCookieSource: Bool
    public let cookieName: String?
    public let showsOrganizationField: Bool
    private let environmentOverride: @Sendable (String) -> [String: String]?
    private let environmentScrubber: @Sendable (inout [String: String], String) -> Void

    public init(
        title: String,
        subtitle: String,
        placeholder: String,
        requiresManualCookieSource: Bool,
        cookieName: String?,
        showsOrganizationField: Bool = false,
        environmentOverride: @escaping @Sendable (String) -> [String: String]?,
        environmentScrubber: @escaping @Sendable (inout [String: String], String) -> Void)
    {
        self.title = title
        self.subtitle = subtitle
        self.placeholder = placeholder
        self.requiresManualCookieSource = requiresManualCookieSource
        self.cookieName = cookieName
        self.showsOrganizationField = showsOrganizationField
        self.environmentOverride = environmentOverride
        self.environmentScrubber = environmentScrubber
    }

    public func envOverride(token: String) -> [String: String]? {
        self.environmentOverride(token)
    }

    public func scrubEnvironment(_ environment: inout [String: String], token: String) {
        self.environmentScrubber(&environment, token)
    }

    public func normalizedCookieHeader(token: String) -> String {
        TokenAccountSupportCatalog.normalizedCookieHeader(token, support: self)
    }
}

public enum TokenAccountSupportCatalog {
    public static func support(for provider: UsageProvider) -> TokenAccountSupport? {
        ProviderDescriptorRegistry.descriptor(for: provider).credentials?.tokenAccountSupport
    }

    public static func envOverride(for provider: UsageProvider, token: String) -> [String: String]? {
        self.support(for: provider)?.envOverride(token: token)
    }

    public static func scrubEnvironmentForSelectedAccount(
        _ environment: inout [String: String],
        provider: UsageProvider,
        token: String)
    {
        self.support(for: provider)?.scrubEnvironment(&environment, token: token)
    }

    public static func normalizedCookieHeader(for provider: UsageProvider, token: String) -> String {
        guard let support = self.support(for: provider) else {
            return token.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return support.normalizedCookieHeader(token: token)
    }

    public static func isClaudeOAuthToken(_ token: String) -> Bool {
        ClaudeCredentialRouting.resolve(tokenAccountToken: token, manualCookieHeader: nil).isOAuth
    }

    public static func normalizedCookieHeader(_ token: String, support: TokenAccountSupport) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cookieName = support.cookieName else { return trimmed }
        let lower = trimmed.lowercased()
        if lower.contains("cookie:") || trimmed.contains("=") {
            return trimmed
        }
        return "\(cookieName)=\(trimmed)"
    }
}
