import Foundation
import Testing
@testable import CodexBarCore

struct ClaudeSourcePlannerTests {
    @Test
    func `app auto plan preserves ordered steps and reasons`() {
        let plan = ClaudeSourcePlanner.resolve(input: ClaudeSourcePlanningInput(
            runtime: .app,
            selectedDataSource: .auto,
            webExtrasEnabled: false,
            hasWebSession: true,
            hasCLI: true,
            hasOAuthCredentials: true))

        #expect(plan.orderedSteps.map(\.dataSource) == [.oauth, .cli, .web])
        #expect(plan.orderedSteps.map(\.inclusionReason) == [
            .appAutoPreferredOAuth,
            .appAutoFallbackCLI,
            .appAutoFallbackWeb,
        ])
        #expect(plan.availableSteps.map(\.dataSource) == [.oauth, .cli, .web])
        #expect(plan.preferredStep?.dataSource == .oauth)
    }

    @Test
    func `app auto with Keychain disabled prefers web then CLI then OAuth`() {
        let plan = ClaudeSourcePlanner.resolve(input: ClaudeSourcePlanningInput(
            runtime: .app,
            selectedDataSource: .auto,
            webExtrasEnabled: false,
            hasWebSession: true,
            hasCLI: true,
            hasOAuthCredentials: true,
            keychainAccessDisabled: true))

        #expect(plan.orderedSteps.map(\.dataSource) == [.web, .cli, .oauth])
        #expect(plan.orderedSteps.map(\.inclusionReason) == [
            .appAutoKeychainDisabledPreferredWeb,
            .appAutoKeychainDisabledFallbackCLI,
            .appAutoKeychainDisabledFallbackOAuth,
        ])
        #expect(plan.preferredStep?.dataSource == .web)
    }

    @Test
    func `Keychain disabled does not reorder CLI runtime or explicit sources`() {
        let cliPlan = ClaudeSourcePlanner.resolve(input: ClaudeSourcePlanningInput(
            runtime: .cli,
            selectedDataSource: .auto,
            webExtrasEnabled: false,
            hasWebSession: true,
            hasCLI: true,
            hasOAuthCredentials: false,
            keychainAccessDisabled: true))
        #expect(cliPlan.orderedSteps.map(\.dataSource) == [.web, .cli])

        let explicitPlan = ClaudeSourcePlanner.resolve(input: ClaudeSourcePlanningInput(
            runtime: .app,
            selectedDataSource: .cli,
            webExtrasEnabled: false,
            hasWebSession: true,
            hasCLI: true,
            hasOAuthCredentials: true,
            keychainAccessDisabled: true))
        #expect(explicitPlan.orderedSteps.map(\.dataSource) == [.cli])
    }

    @Test
    func `leading web step falls back to the CLI when Keychain is disabled`() {
        let context = Self.makeAppAutoContext()
        let leadingWeb = ClaudePlannedFetchStrategy(
            base: ClaudeWebFetchStrategy(browserDetection: BrowserDetection(cacheTTL: 0)),
            plannedStep: ClaudeFetchPlanStep(
                dataSource: .web,
                inclusionReason: .appAutoKeychainDisabledPreferredWeb,
                isPlausiblyAvailable: true))
        #expect(leadingWeb.shouldFallback(
            on: ClaudeWebAPIFetcher.FetchError.noSessionKeyFound,
            context: context))
        #expect(!leadingWeb.shouldFallback(on: CancellationError(), context: context))

        // The default app-auto order keeps web terminal so its concrete error surfaces.
        let trailingWeb = ClaudePlannedFetchStrategy(
            base: ClaudeWebFetchStrategy(browserDetection: BrowserDetection(cacheTTL: 0)),
            plannedStep: ClaudeFetchPlanStep(
                dataSource: .web,
                inclusionReason: .appAutoFallbackWeb,
                isPlausiblyAvailable: true))
        #expect(!trailingWeb.shouldFallback(
            on: ClaudeWebAPIFetcher.FetchError.noSessionKeyFound,
            context: context))
    }

    private struct StubClaudeFetcher: ClaudeUsageFetching {
        func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
            throw ClaudeUsageError.parseFailed("stub")
        }

        func debugRawProbe(model _: String) async -> String {
            "stub"
        }

        func detectVersion() -> String? {
            nil
        }
    }

    private static func makeAppAutoContext() -> ProviderFetchContext {
        ProviderFetchContext(
            runtime: .app,
            sourceMode: .auto,
            includeCredits: false,
            includeOptionalUsage: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: nil,
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: StubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }

    @Test
    func `CLI auto plan preserves ordered steps and reasons`() {
        let plan = ClaudeSourcePlanner.resolve(input: ClaudeSourcePlanningInput(
            runtime: .cli,
            selectedDataSource: .auto,
            webExtrasEnabled: false,
            hasWebSession: true,
            hasCLI: true,
            hasOAuthCredentials: false))

        #expect(plan.orderedSteps.map(\.dataSource) == [.web, .cli])
        #expect(plan.orderedSteps.map(\.inclusionReason) == [
            .cliAutoPreferredWeb,
            .cliAutoFallbackCLI,
        ])
        #expect(plan.preferredStep?.dataSource == .web)
    }

    @Test
    func `explicit mode plan is single step`() {
        let plan = ClaudeSourcePlanner.resolve(input: ClaudeSourcePlanningInput(
            runtime: .app,
            selectedDataSource: .cli,
            webExtrasEnabled: true,
            hasWebSession: false,
            hasCLI: true,
            hasOAuthCredentials: false))

        #expect(plan.orderedSteps.count == 1)
        #expect(plan.orderedSteps.first?.dataSource == .cli)
        #expect(plan.orderedSteps.first?.inclusionReason == .explicitSourceSelection)
        #expect(plan.compatibilityStrategy == ClaudeUsageStrategy(dataSource: .cli, useWebExtras: true))
    }

    @Test
    func `app explicit OAuth selects owner mediated CLI when direct credentials are unavailable`() {
        let plan = ClaudeSourcePlanner.resolve(input: ClaudeSourcePlanningInput(
            runtime: .app,
            selectedDataSource: .oauth,
            webExtrasEnabled: false,
            hasWebSession: true,
            hasCLI: true,
            hasOAuthCredentials: false))

        #expect(plan.orderedSteps.map(\.dataSource) == [.oauth, .cli])
        #expect(plan.orderedSteps.map(\.inclusionReason) == [
            .explicitSourceSelection,
            .explicitOAuthOwnerCLIFallback,
        ])
        #expect(plan.compatibilityStrategy == ClaudeUsageStrategy(dataSource: .cli, useWebExtras: false))
    }

    @Test
    func `app explicit OAuth selects direct OAuth when credentials are available`() {
        let plan = ClaudeSourcePlanner.resolve(input: ClaudeSourcePlanningInput(
            runtime: .app,
            selectedDataSource: .oauth,
            webExtrasEnabled: false,
            hasWebSession: true,
            hasCLI: true,
            hasOAuthCredentials: true))

        #expect(plan.orderedSteps.map(\.dataSource) == [.oauth, .cli])
        #expect(plan.compatibilityStrategy == ClaudeUsageStrategy(dataSource: .oauth, useWebExtras: false))
    }

    @Test
    func `CLI explicit OAuth remains terminal`() {
        let plan = ClaudeSourcePlanner.resolve(input: ClaudeSourcePlanningInput(
            runtime: .cli,
            selectedDataSource: .oauth,
            webExtrasEnabled: false,
            hasWebSession: true,
            hasCLI: true,
            hasOAuthCredentials: false))

        #expect(plan.orderedSteps.map(\.dataSource) == [.oauth])
        #expect(plan.orderedSteps.map(\.inclusionReason) == [.explicitSourceSelection])
    }

    @Test
    func `app auto CLI fallback reports web extras like runtime`() {
        let plan = ClaudeSourcePlanner.resolve(input: ClaudeSourcePlanningInput(
            runtime: .app,
            selectedDataSource: .auto,
            webExtrasEnabled: true,
            hasWebSession: false,
            hasCLI: true,
            hasOAuthCredentials: false))

        #expect(plan.preferredStep?.dataSource == .cli)
        #expect(plan.compatibilityStrategy == ClaudeUsageStrategy(dataSource: .cli, useWebExtras: true))
    }

    @Test
    func `no source planner output is deterministic`() {
        let input = ClaudeSourcePlanningInput(
            runtime: .app,
            selectedDataSource: .auto,
            webExtrasEnabled: false,
            hasWebSession: false,
            hasCLI: false,
            hasOAuthCredentials: false)
        let plan = ClaudeSourcePlanner.resolve(input: input)

        #expect(plan.orderedSteps.map(\.dataSource) == [.oauth, .cli, .web])
        #expect(plan.availableSteps.isEmpty)
        #expect(plan.isNoSourceAvailable)
        #expect(plan.preferredStep == nil)
        #expect(plan.executionSteps.isEmpty)
        #expect(plan.debugLines() == [
            "planner_order=oauth→cli→web",
            "planner_selected=none",
            "planner_no_source=true",
            "planner_step.oauth=unavailable reason=app-auto-preferred-oauth",
            "planner_step.cli=unavailable reason=app-auto-fallback-cli",
            "planner_step.web=unavailable reason=app-auto-fallback-web",
        ])
    }

    @Test
    func `CLI resolver falls back to PATH when Claude CLI path override is invalid`() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let binaryURL = tempDir.appendingPathComponent("claude")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)

        let resolved = ClaudeCLIResolver.resolvedBinaryPath(
            environment: [
                "CLAUDE_CLI_PATH": "/definitely/missing/claude",
                "PATH": tempDir.path,
            ],
            loginPATH: nil)

        #expect(resolved == binaryURL.path)
    }
}
