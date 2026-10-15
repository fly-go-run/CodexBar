import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized, ClaudeOAuthDefaultsFixtures(), ProviderTransportRegressionFixtures())
@MainActor
struct OfflineRefreshHandlingTests {
    private static let provider = UsageProvider.claude

    private static func snapshot(updatedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            primary: nil,
            secondary: nil,
            updatedAt: updatedAt,
            identity: ProviderIdentitySnapshot(
                providerID: self.provider.instanceID,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: "API key"))
    }

    private static func failureOutcome(_ error: Error) -> ProviderFetchOutcome {
        ProviderFetchOutcome(result: .failure(error), attempts: [])
    }

    private static func successOutcome(updatedAt: Date) -> ProviderFetchOutcome {
        ProviderFetchOutcome(result: .success(ProviderFetchResult(
            usage: self.snapshot(updatedAt: updatedAt),
            credits: nil,
            dashboard: nil,
            sourceLabel: "fixture",
            strategyID: "fixture",
            strategyKind: .apiToken)), attempts: [])
    }

    private static func realError() -> NSError {
        NSError(domain: "fixture-provider", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "Quota endpoint rejected the request",
        ])
    }

    // MARK: - Failure handling

    @Test
    func `offline failure with fresh prior data keeps the snapshot and surfaces no error`() async throws {
        try await ProviderTransportRegressionSupport.withStore(provider: Self.provider) { store, _ in
            let recent = Date().addingTimeInterval(-35 * 60)
            store._setSnapshotForTesting(Self.snapshot(updatedAt: recent), provider: Self.provider)
            store._test_providerFetchOutcomeOverride = { _ in Self.failureOutcome(URLError(.notConnectedToInternet)) }

            for _ in 0..<3 {
                await store.refreshProvider(Self.provider, allowDisabled: true)
                #expect(store.errors[Self.provider.instanceID] == nil)
                #expect(store.offlineProviders.contains(Self.provider.instanceID))
                #expect(store.snapshot(for: Self.provider.instanceID)?.updatedAt == recent)
            }
            #expect(!store.isStale)
        }
    }

    @Test
    func `real failure still follows the consecutive failure gate and never marks offline`() async throws {
        try await ProviderTransportRegressionSupport.withStore(provider: Self.provider) { store, _ in
            store._setSnapshotForTesting(
                Self.snapshot(updatedAt: Date().addingTimeInterval(-60)),
                provider: Self.provider)
            let error = Self.realError()
            store._test_providerFetchOutcomeOverride = { _ in Self.failureOutcome(error) }

            await store.refreshProvider(Self.provider, allowDisabled: true)
            #expect(store.errors[Self.provider.instanceID] == nil)
            #expect(store.snapshot(for: Self.provider.instanceID) != nil)

            await store.refreshProvider(Self.provider, allowDisabled: true)
            #expect(store.errors[Self.provider.instanceID] == error.localizedDescription)
            #expect(store.offlineProviders.isEmpty)
        }
    }

    @Test
    func `offline failure with very stale prior data surfaces a calm offline message`() async throws {
        try await ProviderTransportRegressionSupport.withStore(provider: Self.provider) { store, _ in
            let old = Date().addingTimeInterval(-7 * 60 * 60)
            store._setSnapshotForTesting(Self.snapshot(updatedAt: old), provider: Self.provider)
            store._test_providerFetchOutcomeOverride = { _ in Self.failureOutcome(URLError(.notConnectedToInternet)) }

            await store.refreshProvider(Self.provider, allowDisabled: true)

            let message = try #require(store.errors[Self.provider.instanceID])
            #expect(message == L("Offline · data may be outdated"))
            #expect(!message.contains("Internet"))
            #expect(store.snapshot(for: Self.provider.instanceID)?.updatedAt == old)
            #expect(store.offlineProviders.contains(Self.provider.instanceID))
        }
    }

    @Test
    func `offline failure on cold start shows a short offline message`() async throws {
        try await ProviderTransportRegressionSupport.withStore(
            provider: Self.provider,
            hasPriorData: false)
        { store, _ in
            store._test_providerFetchOutcomeOverride = { _ in Self.failureOutcome(URLError(.notConnectedToInternet)) }

            await store.refreshProvider(Self.provider, allowDisabled: true)

            #expect(store.errors[Self.provider.instanceID] == L("Offline"))
            #expect(store.snapshot(for: Self.provider.instanceID) == nil)
            #expect(store.offlineProviders.isEmpty)
        }
    }

    @Test
    func `successful refresh clears the offline state`() async throws {
        try await ProviderTransportRegressionSupport.withStore(provider: Self.provider) { store, _ in
            store._setSnapshotForTesting(
                Self.snapshot(updatedAt: Date().addingTimeInterval(-60)),
                provider: Self.provider)
            store._test_providerFetchOutcomeOverride = { _ in Self.failureOutcome(URLError(.networkConnectionLost)) }
            await store.refreshProvider(Self.provider, allowDisabled: true)
            #expect(store.offlineProviders.contains(Self.provider.instanceID))

            let fresh = Date()
            store._test_providerFetchOutcomeOverride = { _ in Self.successOutcome(updatedAt: fresh) }
            await store.refreshProvider(Self.provider, allowDisabled: true)

            #expect(store.offlineProviders.isEmpty)
            #expect(store.errors[Self.provider.instanceID] == nil)
            #expect(store.snapshot(for: Self.provider.instanceID)?.updatedAt == fresh)
        }
    }

    @Test
    func `real failure after an offline period clears the offline state`() async throws {
        try await ProviderTransportRegressionSupport.withStore(provider: Self.provider) { store, _ in
            store._setSnapshotForTesting(
                Self.snapshot(updatedAt: Date().addingTimeInterval(-60)),
                provider: Self.provider)
            store._test_providerFetchOutcomeOverride = { _ in Self.failureOutcome(URLError(.notConnectedToInternet)) }
            await store.refreshProvider(Self.provider, allowDisabled: true)
            #expect(store.offlineProviders.contains(Self.provider.instanceID))

            let error = Self.realError()
            store._test_providerFetchOutcomeOverride = { _ in Self.failureOutcome(error) }
            await store.refreshProvider(Self.provider, allowDisabled: true)

            #expect(store.offlineProviders.isEmpty)
        }
    }

    @Test
    func `provider error text that says the connection appears offline is treated as offline`() async throws {
        try await ProviderTransportRegressionSupport.withStore(provider: Self.provider) { store, _ in
            store._setSnapshotForTesting(
                Self.snapshot(updatedAt: Date().addingTimeInterval(-60)),
                provider: Self.provider)
            let error = NSError(domain: "fixture-provider", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Request failed: The Internet connection appears to be offline.",
            ])
            store._test_providerFetchOutcomeOverride = { _ in Self.failureOutcome(error) }

            await store.refreshProvider(Self.provider, allowDisabled: true)

            #expect(store.errors[Self.provider.instanceID] == nil)
            #expect(store.offlineProviders.contains(Self.provider.instanceID))
        }
    }

    @Test
    func `timeout counts as offline only while the network path is down`() async throws {
        try await ProviderTransportRegressionSupport.withStore(provider: Self.provider) { store, _ in
            store._setSnapshotForTesting(
                Self.snapshot(updatedAt: Date().addingTimeInterval(-60)),
                provider: Self.provider)
            store._test_providerFetchOutcomeOverride = { _ in Self.failureOutcome(URLError(.timedOut)) }

            await store.refreshProvider(Self.provider, allowDisabled: true)
            #expect(store.offlineProviders.isEmpty)

            store.networkPathUnsatisfied = true
            await store.refreshProvider(Self.provider, allowDisabled: true)
            #expect(store.offlineProviders.contains(Self.provider.instanceID))
            #expect(store.errors[Self.provider.instanceID] == nil)
        }
    }

    // MARK: - Classification

    @Test(arguments: [
        URLError.Code.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
        .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff, .callIsActive, .secureConnectionFailed,
    ])
    func `offline classification covers the broadened URL error codes`(code: URLError.Code) {
        let error = URLError(code)
        #expect(UsageStore.isOfflineNetworkError(error))
        #expect(UsageStore.isTransientNetworkError(error))
        #expect(UsageStore.isPreservableNetworkTransportError(error))
        #expect(UsageStore.isStartupConnectivityRetryableError(error))
        #expect(UsageStore.shouldPreservePriorSnapshot(after: error, hadPriorData: true))
    }

    @Test
    func `timeout is transient but not offline and cancellation is neither`() {
        #expect(!UsageStore.isOfflineNetworkError(URLError(.timedOut)))
        #expect(UsageStore.isTransientNetworkError(URLError(.timedOut)))
        #expect(!UsageStore.isOfflineNetworkError(URLError(.cancelled)))
        #expect(!UsageStore.isTransientNetworkError(URLError(.cancelled)))
        #expect(!UsageStore.isOfflineNetworkError(CancellationError()))
        #expect(!UsageStore.isTransientNetworkError(CancellationError()))
    }

    @Test(arguments: [URLError.Code.badURL, .userAuthenticationRequired, .badServerResponse, .cannotParseResponse])
    func `unrelated URL errors are not offline`(code: URLError.Code) {
        #expect(!UsageStore.isOfflineNetworkError(URLError(code)))
        #expect(!UsageStore.isTransientNetworkError(URLError(code)))
        #expect(!UsageStore.isPreservableNetworkTransportError(URLError(code)))
    }

    @Test
    func `message fallback matches the real offline description`() {
        let offline = NSError(domain: "fixture", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "The Internet connection appears to be offline.",
        ])
        let old = NSError(domain: "fixture", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "You are not connected to the internet",
        ])
        let unrelated = NSError(domain: "fixture", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Invalid API key",
        ])
        #expect(UsageStore.isOfflineNetworkError(offline))
        #expect(UsageStore.isOfflineNetworkError(old))
        #expect(!UsageStore.isOfflineNetworkError(unrelated))
        #expect(UsageStore.shouldPreservePriorSnapshot(after: offline, hadPriorData: true))
        #expect(UsageStore.isStartupConnectivityRetryableError(offline))
    }

    // MARK: - Subtitle

    @Test
    func `offline card subtitle is secondary text with relative update time`() throws {
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let updatedAt = now.addingTimeInterval(-35 * 60)
        func model(isOffline: Bool) -> UsageMenuCardView.Model {
            UsageMenuCardView.Model.make(.init(
                provider: .claude,
                metadata: metadata,
                snapshot: UsageSnapshot(
                    primary: RateWindow(usedPercent: 20, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
                    secondary: nil,
                    updatedAt: updatedAt),
                credits: nil,
                creditsError: nil,
                dashboardError: nil,
                tokenSnapshot: nil,
                tokenError: nil,
                account: AccountInfo(email: nil, plan: nil),
                isOffline: isOffline,
                isRefreshing: false,
                lastError: nil,
                usageBarsShowUsed: false,
                resetTimeDisplayStyle: .countdown,
                tokenCostUsageEnabled: false,
                showOptionalCreditsAndExtraUsage: true,
                hidePersonalInfo: false,
                now: now))
        }
        let online = model(isOffline: false)
        let offline = model(isOffline: true)
        #expect(offline.subtitleStyle == .info)
        #expect(offline.subtitleText == L("Offline · %@", online.subtitleText))
        #expect(offline.subtitleText.contains(online.subtitleText))
    }

    // MARK: - Network recovery

    @Test
    func `network recovery refreshes once after the debounce when a provider is offline`() async throws {
        try await ProviderTransportRegressionSupport.withStore(provider: Self.provider) { store, _ in
            store.offlineProviders.insert(Self.provider.instanceID)
            var refreshes = 0
            var sleeps: [TimeInterval] = []
            store._test_networkRecoverySleepOverride = { sleeps.append($0) }
            store._test_networkRecoveryRefresh = { refreshes += 1 }

            store.handleNetworkPathChange(isSatisfied: false)
            #expect(store.networkPathUnsatisfied)
            store.handleNetworkPathChange(isSatisfied: true)
            store.handleNetworkPathChange(isSatisfied: true)
            let task = try #require(store.networkRecoveryTask)
            await task.value

            #expect(refreshes == 1)
            #expect(sleeps == [UsageStore.networkRecoveryDebounce])
            #expect(!store.networkPathUnsatisfied)
            #expect(store.networkRecoveryTask == nil)
        }
    }

    @Test
    func `network recovery does nothing when every provider is healthy or the path never dropped`() async throws {
        try await ProviderTransportRegressionSupport.withStore(provider: Self.provider) { store, _ in
            var refreshes = 0
            store._test_networkRecoverySleepOverride = { _ in }
            store._test_networkRecoveryRefresh = { refreshes += 1 }

            store.handleNetworkPathChange(isSatisfied: true)
            #expect(store.networkRecoveryTask == nil)

            store.handleNetworkPathChange(isSatisfied: false)
            store.handleNetworkPathChange(isSatisfied: true)
            #expect(store.networkRecoveryTask == nil)
            #expect(refreshes == 0)
        }
    }

    @Test
    func `network recovery also covers providers that failed with a real error`() async throws {
        try await ProviderTransportRegressionSupport.withStore(provider: Self.provider) { store, _ in
            store.errors[Self.provider.instanceID] = "Offline"
            var refreshes = 0
            store._test_networkRecoverySleepOverride = { _ in }
            store._test_networkRecoveryRefresh = { refreshes += 1 }

            store.handleNetworkPathChange(isSatisfied: false)
            store.handleNetworkPathChange(isSatisfied: true)
            await store.networkRecoveryTask?.value

            #expect(refreshes == 1)
        }
    }

    @Test
    func `network flapping during the debounce cancels the pending recovery`() async throws {
        try await ProviderTransportRegressionSupport.withStore(provider: Self.provider) { store, _ in
            store.offlineProviders.insert(Self.provider.instanceID)
            var refreshes = 0
            let gate = RecoveryDebounceGate()
            store._test_networkRecoverySleepOverride = { _ in try await gate.sleep() }
            store._test_networkRecoveryRefresh = { refreshes += 1 }

            store.handleNetworkPathChange(isSatisfied: false)
            store.handleNetworkPathChange(isSatisfied: true)
            let first = try #require(store.networkRecoveryTask)
            await gate.waitUntilSleeping()

            store.handleNetworkPathChange(isSatisfied: false)
            #expect(store.networkRecoveryTask == nil)
            await gate.resume()
            await first.value
            #expect(refreshes == 0)

            store.handleNetworkPathChange(isSatisfied: true)
            let second = try #require(store.networkRecoveryTask)
            await gate.waitUntilSleeping()
            await gate.resume()
            await second.value
            #expect(refreshes == 1)
        }
    }
}

private actor RecoveryDebounceGate {
    private var sleeper: CheckedContinuation<Void, Error>?
    private var waiter: CheckedContinuation<Void, Never>?

    func sleep() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.sleeper = continuation
                self.waiter?.resume()
                self.waiter = nil
            }
        } onCancel: {
            Task { await self.cancelSleeper() }
        }
    }

    func waitUntilSleeping() async {
        if self.sleeper != nil { return }
        await withCheckedContinuation { self.waiter = $0 }
    }

    func resume() {
        self.sleeper?.resume()
        self.sleeper = nil
    }

    private func cancelSleeper() {
        self.sleeper?.resume(throwing: CancellationError())
        self.sleeper = nil
    }
}
