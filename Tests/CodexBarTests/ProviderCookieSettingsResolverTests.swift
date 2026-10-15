import CodexBarCore
import Foundation
import Testing

enum ProviderCookieSettingsResolverTests {
    private static func account(token: String) -> ProviderTokenAccount {
        ProviderTokenAccount(
            id: UUID(),
            label: "Test",
            token: token,
            addedAt: 0,
            lastUsed: nil)
    }
}
