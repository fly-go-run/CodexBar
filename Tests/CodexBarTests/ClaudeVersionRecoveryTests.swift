import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeVersionRecoveryTests {
    @Test
    func `user initiated CLI success refreshes missing Claude version`() async throws {
        try await self.withMissingCredentialsFile {
            let probe = ProbeState()
            self.configureVersionProbe(probe)
            defer { ProviderVersionDetector.resetHooksAndCache() }

            let fixture = try await MainActor.run {
                try self.makeFixture(strategyKind: .cli)
            }
            await ProviderInteractionContext.$current.withValue(.userInitiated) {
                await fixture.store.refreshProvider(.claude)
            }
            await fixture.store.claudeVersionRefreshTask?.value

            #expect(await fixture.store.version(for: .claude) == "2.1.229 (Claude Code)")
            #expect(probe.callCount == 1)
        }
    }

    @Test
    func `background CLI success leaves version probe untouched`() async throws {
        try await self.withMissingCredentialsFile {
            let probe = ProbeState()
            self.configureVersionProbe(probe)
            defer { ProviderVersionDetector.resetHooksAndCache() }

            let fixture = try await MainActor.run {
                try self.makeFixture(strategyKind: .cli)
            }
            await ProviderInteractionContext.$current.withValue(.background) {
                await fixture.store.refreshProvider(.claude)
            }

            #expect(await fixture.store.claudeVersionRefreshTask == nil)
            #expect(await fixture.store.version(for: .claude) == nil)
            #expect(probe.callCount == 0)
        }
    }

    @Test
    func `user initiated OAuth refresh also fills the missing Claude version`() async throws {
        try await self.withMissingCredentialsFile {
            let probe = ProbeState()
            self.configureVersionProbe(probe)
            defer { ProviderVersionDetector.resetHooksAndCache() }

            let fixture = try await MainActor.run {
                try self.makeFixture(strategyKind: .oauth)
            }
            await ProviderInteractionContext.$current.withValue(.userInitiated) {
                await fixture.store.refreshProvider(.claude)
            }
            await fixture.store.claudeVersionRefreshTask?.value

            #expect(await fixture.store.version(for: .claude) == "2.1.229 (Claude Code)")
            #expect(probe.callCount == 1)
        }
    }

    @Test
    func `manual refresh probes the Claude version only while it is missing`() async throws {
        try await self.withMissingCredentialsFile {
            let probe = ProbeState()
            self.configureVersionProbe(probe)
            defer { ProviderVersionDetector.resetHooksAndCache() }

            let fixture = try await MainActor.run {
                try self.makeFixture(strategyKind: .oauth)
            }
            for _ in 0..<2 {
                await ProviderInteractionContext.$current.withValue(.userInitiated) {
                    await fixture.store.refreshProvider(.claude)
                }
                await fixture.store.claudeVersionRefreshTask?.value
            }

            #expect(await fixture.store.version(for: .claude) == "2.1.229 (Claude Code)")
            #expect(probe.callCount == 1)
        }
    }

    @Test
    func `gated background probe marks a resolved Claude binary as installed without version`() async throws {
        try await ClaudeCLIBackgroundAvailability.withIsolatedStoreForTesting {
            try await self.withMissingCredentialsFile {
                let probe = ProbeState()
                self.configureVersionProbe(probe, binaryPath: "/mock/bin/claude-\(UUID().uuidString)")
                defer { ProviderVersionDetector.resetHooksAndCache() }

                let fixture = try await MainActor.run {
                    try self.makeFixture(strategyKind: .oauth)
                }
                await ProviderInteractionContext.$current.withValue(.background) {
                    await fixture.store.detectVersions()
                    await fixture.store.versionDetectionTask?.value
                }

                #expect(probe.callCount == 0)
                #expect(await fixture.store.version(for: .claude) == nil)
                #expect(await fixture.store.claudeBinaryResolvedWithoutVersion)
                #expect(await fixture.store.versionDisplayText(for: .claude) == L("installed (version not detected)"))

                await ProviderInteractionContext.$current.withValue(.userInitiated) {
                    await fixture.store.refreshProvider(.claude)
                }
                await fixture.store.claudeVersionRefreshTask?.value

                #expect(await !fixture.store.claudeBinaryResolvedWithoutVersion)
                #expect(await fixture.store.versionDisplayText(for: .claude) == "2.1.229 (Claude Code)")
            }
        }
    }

    @Test
    @MainActor
    func `version display text distinguishes installed from missing`() throws {
        let fixture = try self.makeFixture(strategyKind: .oauth)
        let store = fixture.store
        #expect(store.versionDisplayText(for: .claude) == L("not detected"))
        #expect(store.versionDisplayText(for: .codex) == L("not detected"))

        store.claudeBinaryResolvedWithoutVersion = true
        #expect(store.versionDisplayText(for: .claude) == L("installed (version not detected)"))
        #expect(store.versionDisplayText(for: .codex) == L("not detected"))

        let context = ProviderPresentationContext(
            provider: .claude,
            settings: store.settings,
            store: store,
            metadata: store.metadata(for: .claude))
        let line = ClaudeProviderImplementation().presentation(context: context).detailLine(context)
        #expect(line.hasSuffix(L("installed (version not detected)")))

        store.versions[UsageProvider.claude.instanceID] = "2.1.296 (Claude Code)"
        #expect(store.versionDisplayText(for: .claude) == "2.1.296 (Claude Code)")
        let trimmed = ClaudeProviderImplementation().presentation(context: context).detailLine(context)
        #expect(trimmed.hasSuffix(" 2.1.296"))
    }

    @Test
    func `later version detection publish preserves recovered Claude version`() async throws {
        try await ClaudeCLIBackgroundAvailability.withIsolatedStoreForTesting {
            try await self.withMissingCredentialsFile {
                let binaryPath = "/mock/bin/claude-\(UUID().uuidString)"
                let recoveryProbe = ProbeState()
                self.configureVersionProbe(recoveryProbe, binaryPath: binaryPath)
                defer { ProviderVersionDetector.resetHooksAndCache() }

                let fixture = try await MainActor.run {
                    try self.makeFixture(strategyKind: .cli)
                }
                await ProviderInteractionContext.$current.withValue(.userInitiated) {
                    await fixture.store.refreshProvider(.claude)
                }
                await fixture.store.claudeVersionRefreshTask?.value
                #expect(await fixture.store.version(for: .claude) == "2.1.229 (Claude Code)")

                ProviderVersionDetector.resetHooksAndCache()
                let backgroundProbe = ProbeState()
                self.configureVersionProbe(backgroundProbe, binaryPath: binaryPath)
                await ProviderInteractionContext.$current.withValue(.background) {
                    await fixture.store.detectVersions()
                    await fixture.store.versionDetectionTask?.value
                }

                #expect(await fixture.store.version(for: .claude) == "2.1.229 (Claude Code)")
                #expect(backgroundProbe.callCount == 0)
            }
        }
    }

    @Test
    func `removed Claude binary clears the recovered version on the next detection run`() async throws {
        try await ClaudeCLIBackgroundAvailability.withIsolatedStoreForTesting {
            try await self.withMissingCredentialsFile {
                let recoveryProbe = ProbeState()
                self.configureVersionProbe(recoveryProbe)
                defer { ProviderVersionDetector.resetHooksAndCache() }

                let fixture = try await MainActor.run {
                    try self.makeFixture(strategyKind: .cli)
                }
                await ProviderInteractionContext.$current.withValue(.userInitiated) {
                    await fixture.store.refreshProvider(.claude)
                }
                await fixture.store.claudeVersionRefreshTask?.value
                #expect(await fixture.store.version(for: .claude) == "2.1.229 (Claude Code)")

                ProviderVersionDetector.resetHooksAndCache()
                ProviderVersionDetector.whichHook = { _ in nil }
                await ProviderInteractionContext.$current.withValue(.background) {
                    await fixture.store.detectVersions()
                    await fixture.store.versionDetectionTask?.value
                }

                #expect(await fixture.store.version(for: .claude) == nil)
            }
        }
    }

    private func withMissingCredentialsFile<T>(
        _ operation: () async throws -> T) async throws -> T
    {
        try await ClaudeOAuthCredentialsStore.withIsolatedCredentialsFileTrackingForTesting {
            let missingURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("missing-credentials.json")
            return try await ClaudeOAuthCredentialsStore.withCredentialsURLOverrideForTesting(missingURL) {
                try await operation()
            }
        }
    }

    @MainActor
    private func makeFixture(strategyKind: ProviderFetchKind) throws -> ClaudeVersionRecoveryFixture {
        let settings = testSettingsStore(suiteName: "ClaudeVersionRecoveryTests")
        settings.claudeUsageDataSource = .cli
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        let metadata = ProviderRegistry.shared.metadata
        for provider in UsageProvider.allCases {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(metadata[provider]),
                enabled: provider == .claude)
        }

        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        store._test_providerFetchOutcomeOverride = { _ in
            Self.successOutcome(strategyKind: strategyKind)
        }
        return ClaudeVersionRecoveryFixture(store: store)
    }

    private static func successOutcome(strategyKind: ProviderFetchKind) -> ProviderFetchOutcome {
        ProviderFetchOutcome(
            result: .success(ProviderFetchResult(
                usage: UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: 20,
                        windowMinutes: 300,
                        resetsAt: nil,
                        resetDescription: nil),
                    secondary: nil,
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
                    identity: ProviderIdentitySnapshot(
                        providerID: .claude,
                        accountEmail: "new@example.com",
                        accountOrganization: nil,
                        loginMethod: "Max")),
                credits: nil,
                dashboard: nil,
                sourceLabel: "claude",
                strategyID: "test.claude-success",
                strategyKind: strategyKind,
                claudeOAuthCredentialOwner: strategyKind == .oauth ? .claudeCLI : nil)),
            attempts: [ProviderFetchAttempt(
                strategyID: "test.claude-success",
                kind: strategyKind,
                wasAvailable: true,
                errorDescription: nil)])
    }

    private func configureVersionProbe(
        _ probe: ProbeState,
        binaryPath: String = "/mock/bin/claude")
    {
        ProviderVersionDetector.resetHooksAndCache()
        ProviderVersionDetector.whichHook = { _ in binaryPath }
        ProviderVersionDetector.attributesHook = { _ in
            [
                .modificationDate: Date(timeIntervalSince1970: 1000),
                .size: NSNumber(value: 5000),
                .systemFileNumber: NSNumber(value: 99),
            ]
        }
        ProviderVersionDetector.runClaudeVersionHook = { _ in
            probe.recordCall()
            return TTYCommandRunner.Result(
                text: "2.1.229 (Claude Code)",
                completion: .processExited(status: 0))
        }
    }
}

@MainActor
private struct ClaudeVersionRecoveryFixture {
    let store: UsageStore
}

private final class ProbeState: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        self.lock.withLock { self.calls }
    }

    func recordCall() {
        self.lock.withLock {
            self.calls += 1
        }
    }
}
