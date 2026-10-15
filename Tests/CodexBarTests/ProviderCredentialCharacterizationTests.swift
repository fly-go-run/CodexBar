import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

enum ProviderCredentialCharacterizationTests {
    private struct APIKeyProjectionFixture: Sendable {
        let provider: UsageProvider
        let environmentKey: String
    }

    private struct DiagnoseFixture: Sendable {
        let provider: UsageProvider
        let environment: [String: String]
        let mode: String
    }

    private static func issueCodes(for provider: ProviderConfig) -> Set<String> {
        Set(CodexBarConfigValidator.validate(CodexBarConfig(providers: [provider])).map(\.code))
    }
}
