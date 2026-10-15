import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct ProviderRawValueRoundTripTests {
    @Test
    func `provider enum exposes exactly codex and claude`() {
        #expect(UsageProvider.allCases.map(\.rawValue) == ["codex", "claude"])
    }

    @Test(arguments: ["codex", "claude"])
    func `raw values round trip through config widget and CLI wire formats`(raw: String) throws {
        let provider = try #require(UsageProvider(rawValue: raw))
        #expect(provider.rawValue == raw)
        #expect(provider.instanceID.rawValue == raw)

        let config = CodexBarConfig(providers: [ProviderConfig(id: provider.instanceID, enabled: true)])
        let configData = try JSONEncoder().encode(config)
        let decodedConfig = try JSONDecoder().decode(CodexBarConfig.self, from: configData)
        #expect(decodedConfig.providers.map(\.id) == [provider.instanceID])

        let entry = WidgetSnapshot.ProviderEntry(
            instanceID: provider.instanceID,
            updatedAt: Date(timeIntervalSince1970: 0),
            primary: nil,
            secondary: nil,
            tertiary: nil,
            creditsRemaining: nil,
            codeReviewRemainingPercent: nil,
            tokenUsage: nil,
            dailyUsage: [])
        let entryObject = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(entry)) as? [String: Any])
        #expect(entryObject["provider"] as? String == raw)

        let payload = ProviderPayload(
            provider: provider,
            account: nil,
            version: nil,
            source: "fixture",
            status: nil,
            usage: nil,
            credits: nil,
            openaiDashboard: nil,
            error: nil)
        let payloadObject = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(payload)) as? [String: Any])
        #expect(payloadObject["provider"] as? String == raw)
    }
}
