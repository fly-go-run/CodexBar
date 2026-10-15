import CodexBarCore
import Foundation

/// Implementations shipped in the app, indexed by `ProviderCatalog`.
enum ProviderImplementationManifest {
    static let implementations: [any ProviderImplementation] = [
        CodexProviderImplementation(),
        ClaudeProviderImplementation(),
    ]
}
