import Foundation
import Testing
@testable import CodexBarCore

struct ProviderDiagnosticExportTests {
    @Test
    func `diagnostic export carries detail sections`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [.makeSection(title: "Credits", rows: [
                .makeRow(label: "Credits used", value: "31", secondaryValue: "Resets in 1d"),
            ])],
            updatedAt: now)
        let summary = ProviderDiagnosticUsageSummary(from: snapshot)

        #expect(summary.detailSections == snapshot.details)
        #expect(!summary.providerSpecificData.contains("copilotCredits"))

        let json = try self.json(summary)
        #expect(json.contains("\"detailSections\""))
        #expect(json.contains("\"Credits used\""))
        #expect(json.contains("31"))
    }

    @Test
    func `usage snapshot defaults legacy payloads to unknown confidence without reencoding unknown`() throws {
        let json = """
        {
          "primary": {
            "usedPercent": 42,
            "windowMinutes": 300,
            "hasResetDescription": false
          },
          "secondary": null,
          "tertiary": null,
          "updatedAt": "2023-11-14T22:13:20Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.dataConfidence == .unknown)

        let encoded = try self.json(snapshot)
        #expect(!encoded.contains("dataConfidence"))
    }

    @Test
    func `usage snapshot preserves explicit confidence through Codable`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 12,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(18000),
                resetDescription: nil),
            secondary: nil,
            updatedAt: now,
            dataConfidence: .exact)

        let encoded = try self.json(snapshot)
        #expect(encoded.contains("\"dataConfidence\" : \"exact\""))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UsageSnapshot.self, from: Data(encoded.utf8))
        #expect(decoded.dataConfidence == .exact)
    }

    @Test
    func `usage snapshot treats future confidence values as unknown`() throws {
        let json = """
        {
          "primary": null,
          "secondary": null,
          "tertiary": null,
          "updatedAt": "2023-11-14T22:13:20Z",
          "dataConfidence": "future"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(UsageSnapshot.self, from: Data(json.utf8))

        #expect(snapshot.dataConfidence == .unknown)
        #expect(try !self.json(snapshot).contains("dataConfidence"))
    }

    @Test
    func `diagnostic usage summary includes confidence`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = ProviderDiagnosticUsageSummary(from: UsageSnapshot(
            primary: RateWindow(
                usedPercent: 12,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(18000),
                resetDescription: nil),
            secondary: nil,
            updatedAt: now,
            dataConfidence: .exact))

        #expect(summary.dataConfidence == "exact")
    }

    @Test
    func `diagnostic usage summary defaults legacy payloads to unknown confidence`() throws {
        let json = """
        {
          "updatedAt": "2023-11-14T22:13:20Z",
          "windows": [],
          "extraWindowCount": 0,
          "providerCostPresent": false,
          "providerSpecificData": []
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let summary = try decoder.decode(
            ProviderDiagnosticUsageSummary.self,
            from: Data(json.utf8))

        #expect(summary.dataConfidence == "unknown")
        #expect(try self.json(summary).contains("\"dataConfidence\" : \"unknown\""))
    }

    @Test
    func `diagnostic export marks named windows with unknown usage`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = ProviderDiagnosticUsageSummary(from: UsageSnapshot(
            primary: nil,
            secondary: nil,
            extraRateWindows: [
                NamedRateWindow(
                    id: "nebula-window",
                    title: "Nebula Window",
                    window: RateWindow(
                        usedPercent: 100,
                        windowMinutes: nil,
                        resetsAt: now.addingTimeInterval(3600),
                        resetDescription: nil),
                    usageKnown: false),
            ],
            updatedAt: now))

        let json = try self.json(summary)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let windows = try #require(object["windows"] as? [[String: Any]])

        #expect(windows.first?["usageKnown"] as? Bool == false)
    }

    @Test
    func `diagnostic rate window defaults legacy payloads to known usage`() throws {
        let json = """
        {
          "label": "Legacy Window",
          "usedPercent": 42,
          "hasResetDescription": false
        }
        """

        let window = try JSONDecoder().decode(
            ProviderDiagnosticRateWindow.self,
            from: Data(json.utf8))

        #expect(window.usageKnown)
    }

    @Test(arguments: [
        (ProviderFetchClassifiedError.Kind.authenticationExpired, "auth"),
        (.missingCredential, "auth"),
        (.permissionDenied, "auth"),
        (.rateLimited, "api"),
        (.providerUnavailable, "api"),
        (.apiFailure, "api"),
        (.parseFailure, "parse"),
        (.networkFailure, "network"),
    ])
    func `diagnostic error maps classified plugin failures`(kind: ProviderFetchClassifiedError.Kind, category: String) {
        let error = ProviderFetchClassifiedError(kind: kind, message: "fixture detail")

        let diagnostic = ProviderDiagnosticError(from: error, authConfigured: true)

        #expect(diagnostic.category == category)
        #expect(!diagnostic.safeDescription.contains("fixture detail"))
    }

    @Test
    func `diagnostic error maps Alibaba invalid endpoint override to configuration`() {
        let error = ProviderEndpointOverrideError.alibabaCodingPlan("ALIBABA_CODING_PLAN_QUOTA_URL")
        let diag = ProviderDiagnosticError(from: error, authConfigured: true)

        #expect(diag.category == "configuration")
        #expect(diag.safeDescription == "Configuration issue - check provider source and settings")
    }

    @Test
    func `endpoint override fetch attempt stays in configuration category`() {
        let error = ProviderEndpointOverrideError.minimax("MINIMAX_HOST")
        let attempt = ProviderFetchAttempt(
            strategyID: "minimax.web",
            kind: .web,
            wasAvailable: true,
            errorDescription: error.localizedDescription)

        let diagError = ProviderDiagnosticError(from: error, authConfigured: true)
        let diagAttempt = ProviderDiagnosticFetchAttempt(from: attempt)

        #expect(diagError.category == "configuration")
        #expect(diagAttempt.errorCategory == "configuration")
    }

    @Test
    func `fetch attempt error maps to safe category, never raw text`() {
        let attemptWithRawError = ProviderFetchAttempt(
            strategyID: "minimax.api",
            kind: .apiToken,
            wasAvailable: true,
            errorDescription: "MiniMax API timeout after 30 seconds - connection refused for host platform.minimax.io")
        let diagAttempt = ProviderDiagnosticFetchAttempt(from: attemptWithRawError)
        #expect(diagAttempt.kind == "api")
        #expect(diagAttempt.wasAvailable == true)
        let errorCategoryOne = diagAttempt.errorCategory
        #expect(errorCategoryOne == "network")
        let cat1 = errorCategoryOne ?? ""
        #expect(!cat1.contains("timeout"))
        #expect(!cat1.contains("connection refused"))
        #expect(!cat1.contains("platform.minimax.io"))

        let attemptWithAuthError = ProviderFetchAttempt(
            strategyID: "minimax.web",
            kind: .web,
            wasAvailable: false,
            errorDescription: "invalid auth token cookie HERTZ-SESSION=abc123")
        let diagAuthAttempt = ProviderDiagnosticFetchAttempt(from: attemptWithAuthError)
        #expect(diagAuthAttempt.wasAvailable == false)
        let errorCategoryTwo = diagAuthAttempt.errorCategory
        #expect(errorCategoryTwo == "auth")
        let cat2 = errorCategoryTwo ?? ""
        #expect(!cat2.contains("HERTZ-SESSION"))
    }

    @Test
    func `fetch attempt carries strategy identity and outcome`() {
        let failed = ProviderDiagnosticFetchAttempt(from: ProviderFetchAttempt(
            strategyID: "antigravity.app-local",
            kind: .localProbe,
            wasAvailable: true,
            errorDescription: "quota request rejected"))
        #expect(failed.strategyID == "antigravity.app-local")
        #expect(failed.kind == "local")
        #expect(failed.outcome == "failed")

        let skipped = ProviderDiagnosticFetchAttempt(from: ProviderFetchAttempt(
            strategyID: "antigravity.cli-https",
            kind: .cli,
            wasAvailable: false,
            errorDescription: nil))
        #expect(skipped.strategyID == "antigravity.cli-https")
        #expect(skipped.outcome == "skipped")

        let succeeded = ProviderDiagnosticFetchAttempt(from: ProviderFetchAttempt(
            strategyID: "antigravity.oauth",
            kind: .oauth,
            wasAvailable: true,
            errorDescription: nil))
        #expect(succeeded.strategyID == "antigravity.oauth")
        #expect(succeeded.outcome == "succeeded")
    }

    @Test
    func `legacy fetch attempt JSON derives outcome without strategy identity`() throws {
        let legacyJSON = """
        {"kind":"local","wasAvailable":true,"errorCategory":"api"}
        """
        let legacy = try JSONDecoder().decode(
            ProviderDiagnosticFetchAttempt.self,
            from: Data(legacyJSON.utf8))

        #expect(legacy.strategyID == nil)
        #expect(legacy.outcome == "failed")

        let legacySkipped = try JSONDecoder().decode(
            ProviderDiagnosticFetchAttempt.self,
            from: Data(#"{"kind":"cli","wasAvailable":false,"errorCategory":null}"#.utf8))
        #expect(legacySkipped.outcome == "skipped")
    }

    @Test
    func `serialized fetch outcomes remain compatible with legacy readers`() throws {
        struct LegacyAttempt: Codable {
            let kind: String
            let wasAvailable: Bool
            let errorCategory: String?
        }
        let attempts = [
            ProviderFetchAttempt(
                strategyID: "antigravity.app-local",
                kind: .localProbe,
                wasAvailable: true,
                errorDescription: "HTTP failure: sensitive-payload"),
            ProviderFetchAttempt(
                strategyID: "antigravity.cli-https",
                kind: .cli,
                wasAvailable: false,
                errorDescription: nil),
            ProviderFetchAttempt(
                strategyID: "antigravity.oauth",
                kind: .oauth,
                wasAvailable: true,
                errorDescription: nil),
        ].map { ProviderDiagnosticFetchAttempt(from: $0) }
        let data = try JSONEncoder().encode(attempts)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(object.compactMap { $0["strategyID"] as? String } == [
            "antigravity.app-local", "antigravity.cli-https", "antigravity.oauth",
        ])
        #expect(object.compactMap { $0["outcome"] as? String } == ["failed", "skipped", "succeeded"])
        #expect(try !#require(String(data: data, encoding: .utf8)).contains("sensitive-payload"))
        let legacy = try JSONDecoder().decode([LegacyAttempt].self, from: data)
        #expect(legacy.map(\.kind) == ["local", "cli", "oauth"])
        let oldData = try JSONEncoder().encode(legacy)
        let restored = try JSONDecoder().decode([ProviderDiagnosticFetchAttempt].self, from: oldData)
        #expect(restored.allSatisfy { $0.strategyID == nil })
        #expect(restored.map(\.outcome) == ["failed", "skipped", "succeeded"])
    }

    @Test
    func `missing api key setup errors map to auth before api`() {
        let category = ProviderDiagnosticFetchAttempt.errorCategoryLabel(
            "Azure OpenAI API key not configured. Set AZURE_OPENAI_API_KEY.")

        #expect(category == "auth")
    }

    @Test
    func `claude subscription notice without quota maps to configuration not auth`() {
        let error = ClaudeStatusProbeError.parseFailed(ClaudeStatusProbe.subscriptionQuotaUnavailableDescription)
        let category = ProviderDiagnosticFetchAttempt.errorCategoryLabel(error.localizedDescription)
        let diagnostic = ProviderDiagnosticError(from: error, authConfigured: true)

        #expect(category == "configuration")
        #expect(diagnostic.category == "configuration")
        #expect(diagnostic.safeDescription == "Configuration issue - check provider source and settings")
        #expect(ProviderDiagnosticFetchAttempt.errorCategoryLabel(
            error.localizedDescription.uppercased()) == "configuration")
    }

    @Test
    func `fetch attempt coding preserves diagnostic fields`() throws {
        let attempt = ProviderDiagnosticFetchAttempt(
            strategyID: "claude.cli", kind: "cli", wasAvailable: true, errorCategory: "configuration")
        let data = try JSONEncoder().encode(attempt)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["strategyID", "kind", "outcome", "wasAvailable", "errorCategory"])
        let decoded = try JSONDecoder().decode(ProviderDiagnosticFetchAttempt.self, from: data)
        #expect(decoded.strategyID == "claude.cli")
        #expect(decoded.kind == "cli")
        #expect(decoded.outcome == "failed")
        #expect(decoded.wasAvailable)
        #expect(decoded.errorCategory == "configuration")
    }

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
