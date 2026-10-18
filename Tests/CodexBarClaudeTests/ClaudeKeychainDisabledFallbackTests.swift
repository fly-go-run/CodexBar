import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeKeychainDisabledFallbackTests {
    private static let missingCLIPath = "/definitely/missing/claude"

    private func fetchOutcome(webError: Error) async -> ProviderFetchOutcome {
        let settings = ProviderSettingsSnapshot.make(claude: .init(
            usageDataSource: .auto,
            webExtrasEnabled: false,
            cookieSource: .manual,
            manualCookieHeader: "sessionKey=sk-ant-session-token"))
        let env = ["CLAUDE_CLI_PATH": Self.missingCLIPath]
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let context = ProviderFetchContext(
            runtime: .app,
            sourceMode: .auto,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: settings,
            fetcher: UsageFetcher(environment: env),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)
        let usageLoader: ClaudeWebFetchStrategy.UsageLoader = { _ in throw webError }
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .claude)

        return await KeychainAccessGate.withTaskOverrideForTesting(true) {
            await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting(Self.missingCLIPath) {
                await self.withNoOAuthCredentials {
                    await ClaudeWebFetchStrategy.$usageLoaderOverrideForTesting.withValue(usageLoader) {
                        await descriptor.fetchPlan.fetchOutcome(context: context, provider: .claude)
                    }
                }
            }
        }
    }

    private func withNoOAuthCredentials<T>(operation: () async throws -> T) async rethrows -> T {
        let missingCredentialsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-claude-creds-\(UUID().uuidString).json")
        return try await KeychainCacheStore.withServiceOverrideForTesting("claude-disabled-\(UUID().uuidString)") {
            KeychainCacheStore.setTestStoreForTesting(true)
            defer { KeychainCacheStore.setTestStoreForTesting(false) }
            return try await ClaudeOAuthCredentialsStore.withIsolatedMemoryCacheForTesting {
                try await ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
                    try await ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(missingCredentialsURL) {
                        try await ClaudeOAuthCredentialsStore.withKeychainAccessOverrideForTesting(true) {
                            try await ClaudeOAuthCredentialsStore.withClaudeKeychainOverridesForTesting(
                                data: nil,
                                fingerprint: nil)
                            {
                                try await operation()
                            }
                        }
                    }
                }
            }
        }
    }

    @Test
    func `offline web failure stops the fetch instead of falling back`() async {
        let outcome = await self.fetchOutcome(webError: URLError(.notConnectedToInternet))

        #expect(outcome.attempts.map(\.strategyID) == ["claude.web"])
        switch outcome.result {
        case let .failure(error as URLError):
            #expect(error.code == .notConnectedToInternet)
        case let .failure(error):
            Issue.record("Unexpected failure: \(error)")
        case let .success(result):
            Issue.record("Unexpected success: \(result.sourceLabel)")
        }
    }

    @Test
    func `web failure is surfaced over missing OAuth credentials`() async {
        let outcome = await self.fetchOutcome(webError: ClaudeWebAPIFetcher.FetchError.unauthorized)

        #expect(outcome.attempts.map(\.strategyID) == ["claude.web", "claude.cli", "claude.oauth"])
        #expect(outcome.attempts.map(\.wasAvailable) == [true, false, true])
        switch outcome.result {
        case let .failure(error as ClaudeWebAPIFetcher.FetchError):
            guard case .unauthorized = error else {
                Issue.record("Unexpected web failure: \(error)")
                return
            }
        case let .failure(error):
            Issue.record("Unexpected failure: \(error)")
        case let .success(result):
            Issue.record("Unexpected success: \(result.sourceLabel)")
        }
    }
}
