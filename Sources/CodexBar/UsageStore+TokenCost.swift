import CodexBarCore
import Foundation

struct CurrentProviderConfigTokenSnapshot: Sendable, Equatable {
    let snapshot: CostUsageTokenSnapshot
    let publicationRevision: UInt64
}

struct CurrentProviderConfigTokenPublication: Sendable, Equatable {
    let snapshot: CostUsageTokenSnapshot?
    let publicationRevision: UInt64
}

struct TokenSnapshotPublication: Sendable, Equatable {
    let snapshot: CostUsageTokenSnapshot?
    let publicationRevision: UInt64
    let providerConfigRevision: UInt64
    let scopeSignature: String
}

extension UsageStore {
    func logTokenUsageSuccess(
        provider: UsageProvider,
        snapshot: CostUsageTokenSnapshot,
        historyDays: Int,
        startedAt: Date)
    {
        let durationText = String(format: "%.2f", Date().timeIntervalSince(startedAt))
        let sessionCost = snapshot.sessionCostUSD
            .map { UsageFormatter.currencyString($0, currencyCode: snapshot.currencyCode) } ?? "—"
        let monthCost = snapshot.last30DaysCostUSD
            .map { UsageFormatter.currencyString($0, currencyCode: snapshot.currencyCode) } ?? "—"
        let message =
            "cost usage success provider=\(provider.rawValue) " +
            "duration=\(durationText)s " +
            "today=\(sessionCost) " +
            "historyDays=\(historyDays) windowCost=\(monthCost)"
        self.tokenCostLogger.info(message)
    }

    func loadTokenUsageSnapshot(
        provider: UsageProvider,
        force: Bool,
        now: Date,
        codexHomePath: String?,
        historyDays: Int,
        reportContext: CostUsageReportContext = .regular) async throws -> CostUsageTokenSnapshot
    {
        if let override = self._test_tokenUsageSnapshotLoaderOverride {
            return try await override(provider, force, now, codexHomePath, historyDays)
        }

        let fetcher = self.costUsageFetcher
        let timeoutSeconds = self.tokenFetchTimeout
        // Provider-specific by design: the Codex ledger owns pricing refresh.
        let allowPricingRefresh = provider != .codex || !self.settings.codexLocalSessionCostLedgerEnabled
        let environment = self.environmentBase
        return try await withThrowingTaskGroup(of: CostUsageTokenSnapshot.self) { group in
            group.addTask(priority: .utility) {
                try await fetcher.loadTokenSnapshot(
                    provider: provider,
                    environment: environment,
                    now: now,
                    forceRefresh: force,
                    codexHomePath: codexHomePath,
                    historyDays: historyDays,
                    allowPricingRefresh: allowPricingRefresh,
                    bypassScannerDebounce: true,
                    calendar: self.settings.costUsageBucketCalendar,
                    reportContext: reportContext)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw CostUsageError.timedOut(seconds: Int(timeoutSeconds))
            }
            defer { group.cancelAll() }
            guard let snapshot = try await group.next() else { throw CancellationError() }
            return snapshot
        }
    }

    func tokenSnapshot(for provider: UsageProvider) -> CostUsageTokenSnapshot? {
        self.accountScopedTokenSnapshot(for: provider)
    }

    func tokenSnapshotForCurrentProviderConfig(
        for provider: UsageProvider) -> CurrentProviderConfigTokenSnapshot?
    {
        guard let publication = self.tokenSnapshotPublicationForCurrentProviderConfig(for: provider),
              let snapshot = publication.snapshot
        else { return nil }
        return CurrentProviderConfigTokenSnapshot(
            snapshot: snapshot,
            publicationRevision: publication.publicationRevision)
    }

    func tokenSnapshotPublicationForCurrentProviderConfig(
        for provider: UsageProvider) -> CurrentProviderConfigTokenPublication?
    {
        guard let publication = self.tokenSnapshotPublications[provider.instanceID],
              publication.providerConfigRevision == self.settings.providerConfigRevision(for: provider),
              publication.scopeSignature == self.tokenSnapshotScopeSignature(for: provider)
        else { return nil }
        return CurrentProviderConfigTokenPublication(
            snapshot: publication.snapshot,
            publicationRevision: publication.publicationRevision)
    }

    func tokenSnapshotPublicationRevision(for provider: UsageProvider) -> UInt64 {
        self.tokenSnapshotPublicationRevisions[provider.instanceID] ?? 0
    }

    enum TokenSnapshotError: LocalizedError {
        case historyUnavailable

        var errorDescription: String? {
            "Local token history is unavailable or incomplete."
        }
    }

    func retainsEstablishedTokenHistory(_ snapshot: CostUsageTokenSnapshot, for provider: UsageProvider) -> Bool {
        // Provider-specific by design: bounded Codex scans retain complete same-scope history.
        if provider == .codex, !snapshot.historyCoverageIsEstablished,
           self.tokenSnapshotPublicationForCurrentProviderConfig(for: provider)?
               .snapshot?.historyCoverageIsEstablished == true
        {
            return true
        }
        return false
    }

    func publishTokenSnapshot(
        _ snapshot: CostUsageTokenSnapshot,
        for provider: UsageProvider)
    {
        if self.retainsEstablishedTokenHistory(snapshot, for: provider) { return }
        self.publishTokenSnapshotState(snapshot, for: provider)
    }

    func publishConfirmedEmptyTokenSnapshot(for provider: UsageProvider) {
        self.publishTokenSnapshotState(nil, for: provider)
    }

    private func publishTokenSnapshotState(
        _ snapshot: CostUsageTokenSnapshot?,
        for provider: UsageProvider)
    {
        self.tokenSnapshotPublicationRevisions[provider.instanceID, default: 0] &+= 1
        self.installCachedTokenSnapshot(snapshot, for: provider)
        self.synchronizeSharedSpendDashboardAfterTokenPublication(for: provider)
    }

    /// The menu card projects quota weeks synchronously while it builds, so the per-slice pass runs
    /// off the main actor when possible; a card arriving first can still build it synchronously.
    private func warmQuotaProjection(for snapshot: CostUsageTokenSnapshot?) {
        guard let snapshot, !snapshot.quotaSlices.isEmpty || !snapshot.hourly.isEmpty else { return }
        let calendar = self.settings.costUsageBucketCalendar
        Task.detached(priority: .utility) {
            snapshot.warmQuotaProjection(calendar: calendar)
        }
    }

    func installCachedTokenSnapshot(
        _ snapshot: CostUsageTokenSnapshot?,
        for provider: UsageProvider)
    {
        self.tokenSnapshotPublications[provider.instanceID] = TokenSnapshotPublication(
            snapshot: snapshot?.reporting(self.settings.costReportingPeriod),
            publicationRevision: self.tokenSnapshotPublicationRevision(for: provider),
            providerConfigRevision: self.settings.providerConfigRevision(for: provider),
            scopeSignature: self.tokenSnapshotScopeSignature(for: provider))
        self.warmQuotaProjection(for: snapshot)
    }

    func clearTokenSnapshot(for provider: UsageProvider) {
        self.tokenSnapshotPublications.removeValue(forKey: provider.instanceID)
    }

    func clearTokenSnapshots() {
        self.tokenSnapshotPublications.removeAll()
        self.spendDashboardTokenPublications.removeAll()
        self.spendDashboardTokenPublicationRevisions.removeAll()
        self.spendDashboardTokenIncorporatedTriggers.removeAll()
        self.spendDashboardTokenFailedTriggers.removeAll()
    }

    func tokenError(for provider: UsageProvider) -> String? {
        self.tokenErrors[provider.instanceID]
    }

    func tokenLastAttemptAt(for provider: UsageProvider) -> Date? {
        self.lastTokenFetchAt[provider.instanceID]
    }

    @discardableResult
    func hydrateCachedTokenSnapshots(now: Date = Date()) -> Task<Void, Never>? {
        // Provider-specific by design: only the Codex local ledger hydrates a cached snapshot before the first scan.
        guard self.settings.isCostUsageEffectivelyEnabled(for: .codex) else { return nil }
        guard self.settings.enabledProvidersOrdered(metadataByProvider: self.providerMetadata).contains(.codex) else {
            return nil
        }

        return Task { @MainActor [weak self] in
            guard let self else { return }
            let scope = self.tokenCostScope(for: .codex)
            let historyDays = self.settings.costReportingPeriod.days(
                now: now,
                calendar: self.settings.costUsageBucketCalendar)
            let publicationRevision = self.providerPublicationRevision(for: .codex)
            let providerConfigRevision = self.settings.providerConfigRevision(for: .codex)
            let costUsageSettingsRevision = self.settings.costUsageSettingsRevision
            let tokenSnapshotScopeSignature = self.tokenSnapshotScopeSignature(for: .codex)
            let tokenSnapshotPublicationRevision = self.tokenSnapshotPublicationRevision(for: .codex)
            guard self.tokenSnapshotPublicationForCurrentProviderConfig(for: .codex) == nil else { return }
            let result: (
                snapshot: CostUsageTokenSnapshot,
                lastRefreshAt: Date?,
                staleSnapshotUpdatedAt: Date?)? = if let override =
                self._test_cachedCodexTokenSnapshotLoaderOverride
            {
                await override(now, scope.codexHomePath, historyDays).map {
                    ($0.snapshot, $0.lastRefreshAt, $0.staleSnapshotUpdatedAt)
                }
            } else {
                await self.costUsageFetcher.loadCachedCodexTokenSnapshotResult(
                    now: now,
                    codexHomePath: scope.codexHomePath,
                    historyDays: historyDays,
                    calendar: self.settings.costUsageBucketCalendar,
                    environment: self.environmentBase)
                    .map {
                        (
                            snapshot: $0.snapshot,
                            lastRefreshAt: $0.lastRefreshAt,
                            staleSnapshotUpdatedAt: $0.staleSnapshotUpdatedAt)
                    }
            }
            guard let result
            else {
                return
            }
            // Provider-specific by design: cache hydration publishes only after all fixed Codex scope checks pass.
            guard self.providerPublicationRevisionIsCurrent(publicationRevision, for: .codex),
                  self.settings.providerConfigRevision(for: .codex) == providerConfigRevision,
                  self.settings.costUsageSettingsRevision == costUsageSettingsRevision,
                  self.settings.isCostUsageEffectivelyEnabled(for: .codex),
                  self.isEnabled(.codex),
                  self.tokenCostScope(for: .codex).signature == scope.signature,
                  self.settings.costUsageHistoryDays == historyDays,
                  self.tokenSnapshotScopeSignature(for: .codex) == tokenSnapshotScopeSignature,
                  self.tokenSnapshotPublicationRevision(for: .codex) == tokenSnapshotPublicationRevision,
                  self.tokenSnapshotPublicationForCurrentProviderConfig(for: .codex) == nil
            else {
                return
            }
            self.installCachedTokenSnapshot(result.snapshot, for: .codex)
            self.tokenErrors[.codex] = nil
            if result.staleSnapshotUpdatedAt != nil {
                self.startCodexCostCatchUpIfNeeded()
            }
            if let tokenFetchTTL = self.tokenFetchTTL,
               let lastRefreshAt = result.lastRefreshAt,
               now.timeIntervalSince(lastRefreshAt) >= 0,
               now.timeIntervalSince(lastRefreshAt) < tokenFetchTTL
            {
                self.lastTokenFetchAt[.codex] = lastRefreshAt
                self.lastTokenFetchScope[.codex] = tokenSnapshotScopeSignature
            }
        }
    }

    func isTokenRefreshInFlight(for provider: UsageProvider) -> Bool {
        self.tokenRefreshInFlight.contains(provider.instanceID)
    }

    func tokenCostRefreshIsActive(for provider: UsageProvider) -> Bool {
        if self.tokenRefreshInFlight.contains(provider.instanceID) {
            return true
        }
        return provider == .codex && self.codexCostCatchUpActivity?.phase == .indexing
    }

    func tokenCostScope(for provider: UsageProvider) -> (codexHomePath: String?, signature: String) {
        guard provider == .codex else {
            return (nil, provider.rawValue)
        }
        if self.settings.codexLocalSessionCostLedgerEnabled {
            return (nil, "codex:ambient")
        }
        let activeSource = self.settings.codexActiveSource
        switch activeSource {
        case .liveSystem:
            return (nil, "codex:ambient")
        case let .managedAccount(id):
            let homePath = self.settings.managedCodexRemoteHomePath(forActiveSource: activeSource)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let homePath, !homePath.isEmpty {
                return (homePath, "codex:managed:\(homePath)")
            }
            let unavailablePath = Self.costUsageCacheDirectory()
                .appendingPathComponent("unavailable-managed", isDirectory: true)
                .appendingPathComponent(id.uuidString, isDirectory: true)
                .path
            return (unavailablePath, "codex:managed:unavailable:\(id.uuidString)")
        case .profileHome:
            let homePath = self.settings.profileCodexHomePath(forActiveSource: activeSource)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let homePath, !homePath.isEmpty {
                return (homePath, "codex:profile:\(homePath)")
            }
            let unavailablePath = Self.costUsageCacheDirectory()
                .appendingPathComponent("unavailable-profile", isDirectory: true)
                .path
            return (unavailablePath, "codex:profile-unavailable")
        }
    }

    func tokenSnapshotScopeSignature(for provider: UsageProvider) -> String {
        self.tokenSnapshotScopeSignature(
            for: provider,
            historyDays: self.settings.costUsageHistoryDays,
            includeSettingsRevision: true)
    }

    func spendDashboardTokenSnapshotScopeSignature(for provider: UsageProvider) -> String {
        self.tokenSnapshotScopeSignature(
            for: provider,
            historyDays: SpendDashboardSource.scanDays,
            includeSettingsRevision: false)
    }

    func tokenSnapshotScopeSignature(
        for provider: UsageProvider,
        historyDays: Int,
        includeSettingsRevision: Bool) -> String
    {
        let scope = self.tokenCostScope(for: provider)
        var base = "\(scope.signature)|historyDays=\(historyDays)"
        if includeSettingsRevision {
            base += "|settingsRevision=\(self.settings.costUsageSettingsRevision)|"
                + self.settings.costReportingPeriod.identity(
                    now: Date(),
                    calendar: self.settings.costUsageBucketCalendar)
        }
        return base
    }

    func tokenRefreshCanReuseCurrentSnapshot(
        provider: UsageProvider,
        now: Date,
        costScopeSignature: String) -> Bool
    {
        guard self.tokenSnapshotPublicationForCurrentProviderConfig(for: provider) != nil,
              let last = self.lastTokenFetchAt[provider.instanceID],
              self.lastTokenFetchScope[provider.instanceID] == costScopeSignature
        else {
            return false
        }
        guard let tokenFetchTTL = self.tokenFetchTTL else { return false }
        return now.timeIntervalSince(last) < tokenFetchTTL
    }

    struct TokenRefreshPublicationScope {
        let publicationRevision: ProviderPublicationRevision
        let providerConfigRevision: UInt64
        let costSettingsRevision: UInt64
        let historyDays: Int
        let signature: String
    }

    struct TokenFetchFailureCooldown {
        let attemptedAt: Date
        let retryAfter: Date
        let scope: TokenRefreshPublicationScope
    }

    func tokenRefreshFailureIsCoolingDown(provider: UsageProvider, now: Date) -> Bool {
        guard let failure = self.tokenFetchFailureCooldowns[provider.instanceID],
              self.tokenFetchTTL != nil,
              now >= failure.attemptedAt,
              now < failure.retryAfter
        else { return false }
        // A failed query may have no snapshot, but still owns its account, settings, and provider lifecycle scope.
        return self.tokenRefreshPublicationDisposition(provider: provider, scope: failure.scope) == .current
    }

    func tokenRefreshPublicationScope(
        for provider: UsageProvider,
        historyDays: Int,
        costScopeSignature: String) -> TokenRefreshPublicationScope
    {
        TokenRefreshPublicationScope(
            publicationRevision: self.providerPublicationRevision(for: provider),
            providerConfigRevision: self.settings.providerConfigRevision(for: provider),
            costSettingsRevision: self.settings.costUsageSettingsRevision,
            historyDays: historyDays,
            signature: costScopeSignature)
    }

    enum TokenRefreshPublicationDisposition {
        case current
        case scopeChanged
    }

    func tokenRefreshPublicationDisposition(
        provider: UsageProvider,
        scope: TokenRefreshPublicationScope) -> TokenRefreshPublicationDisposition
    {
        guard self.providerPublicationRevisionIsCurrent(scope.publicationRevision, for: provider),
              self.settings.providerConfigRevision(for: provider) == scope.providerConfigRevision,
              self.settings.costUsageSettingsRevision == scope.costSettingsRevision,
              self.settings.isCostUsageEffectivelyEnabled(for: provider),
              self.isEnabled(provider),
              self.settings.costUsageHistoryDays == scope.historyDays
        else {
            return .scopeChanged
        }
        let currentSignature = self.tokenSnapshotScopeSignature(for: provider)
        return currentSignature == scope.signature ? .current : .scopeChanged
    }

    nonisolated static func costUsageCacheDirectory(
        fileManager: FileManager = .default) -> URL
    {
        let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return root
            .appendingPathComponent("CodexBar", isDirectory: true)
            .appendingPathComponent("cost-usage", isDirectory: true)
    }

    func clearCostUsageCache(
        fileManagerFactory: @escaping @Sendable () -> FileManager = { .default }) async -> String?
    {
        let errorMessage: String? = await Task.detached(priority: .utility) {
            let fileManager = fileManagerFactory()
            do {
                try fileManager.removeItem(at: Self.costUsageCacheDirectory(fileManager: fileManager))
            } catch let error as NSError {
                if error.domain == NSCocoaErrorDomain, error.code == NSFileNoSuchFileError {
                    return nil
                }
                return error.localizedDescription
            }
            return nil
        }.value

        guard errorMessage == nil else { return errorMessage }

        self.clearTokenSnapshots()
        self.tokenErrors.removeAll()
        self.lastTokenFetchAt.removeAll()
        self.lastTokenFetchScope.removeAll()
        self.tokenFetchFailureCooldowns.removeAll()
        self.tokenFailureGates[.codex]?.reset()
        self.tokenFailureGates[.claude]?.reset()
        return nil
    }

    /// Descriptors live in CodexBarCore and cannot localize, so the message is resolved here.
    /// `L` returns its argument unchanged for providers whose message is a plain English literal.
    nonisolated static func tokenCostNoDataMessage(for provider: UsageProvider) -> String {
        L(ProviderDescriptorRegistry.descriptor(for: provider).tokenCost.noDataMessage())
    }

    func regularTokenSnapshotIsConfirmedEmpty(
        _ snapshot: CostUsageTokenSnapshot,
        for provider: UsageProvider) throws -> Bool
    {
        guard snapshot.daily.isEmpty else { return false }
        if snapshot.historyCoverageIsEstablished { return true }
        guard self.retainsEstablishedTokenHistory(snapshot, for: provider) else {
            throw TokenSnapshotError.historyUnavailable
        }
        return false
    }

    struct TokenUsageRefreshContext {
        let provider: UsageProvider
        let now: Date
        let historyDays: Int
        let costScopeSignature: String
        let publicationScope: TokenRefreshPublicationScope
        let startedAt: Date
    }

    func commitTokenUsageResult(
        _ snapshot: CostUsageTokenSnapshot,
        context: TokenUsageRefreshContext) throws
    {
        try Task.checkCancellation()
        let completedCostScopeSignature = context.costScopeSignature
        let disposition = self.tokenRefreshPublicationDisposition(
            provider: context.provider,
            scope: context.publicationScope)
        guard disposition == .current else {
            self.clearTokenFetchMetadataIfMatching(
                provider: context.provider,
                attemptedAt: context.now,
                costScopeSignature: context.costScopeSignature)
            if disposition == .scopeChanged {
                self.requestTokenRefreshAfterStaleCompletion(for: context.provider)
            }
            return
        }
        self.lastTokenFetchScope[context.provider.instanceID] = completedCostScopeSignature
        self.startCodexCostCatchUpIfNeeded(afterRefreshing: context.provider)

        if try self.regularTokenSnapshotIsConfirmedEmpty(snapshot, for: context.provider) {
            self.publishConfirmedEmptyTokenSnapshot(for: context.provider)
            self.tokenErrors[context.provider.instanceID] = Self.tokenCostNoDataMessage(for: context.provider)
            self.tokenFailureGates[context.provider.instanceID]?.recordSuccess()
            return
        }
        self.logTokenUsageSuccess(
            provider: context.provider,
            snapshot: snapshot,
            historyDays: context.historyDays,
            startedAt: context.startedAt)
        self.publishTokenSnapshot(snapshot, for: context.provider)
        self.tokenErrors[context.provider.instanceID] = nil
        self.tokenFailureGates[context.provider.instanceID]?.recordSuccess()
        self.persistWidgetSnapshot(reason: "token-usage")
    }

    func resetTokenUsageState(for provider: UsageProvider) {
        // Provider-specific by design: resetting Codex token state also cancels its two ledger catch-up workflows.
        if provider == .codex {
            self.cancelCodexCostCatchUp()
            self.cancelSpendDashboardCodexCostCatchUp()
        }
        self.clearTokenSnapshot(for: provider)
        self.clearSpendDashboardTokenSnapshot(for: provider)
        self.tokenErrors[provider.instanceID] = nil
        self.tokenFailureGates[provider.instanceID]?.reset()
        self.lastTokenFetchAt.removeValue(forKey: provider.instanceID)
        self.lastTokenFetchScope.removeValue(forKey: provider.instanceID)
        self.tokenFetchFailureCooldowns.removeValue(forKey: provider.instanceID)
        self.lastSpendDashboardTokenFetchAt.removeValue(forKey: provider.instanceID)
        self.lastSpendDashboardTokenFetchScope.removeValue(forKey: provider.instanceID)
    }

    func clearTokenFetchMetadataIfMatching(
        provider: UsageProvider,
        attemptedAt: Date,
        costScopeSignature: String)
    {
        guard self.lastTokenFetchAt[provider.instanceID] == attemptedAt,
              self.lastTokenFetchScope[provider.instanceID] == costScopeSignature
        else {
            return
        }
        self.lastTokenFetchAt.removeValue(forKey: provider.instanceID)
        self.lastTokenFetchScope.removeValue(forKey: provider.instanceID)
        self.tokenFetchFailureCooldowns.removeValue(forKey: provider.instanceID)
    }

    /// Timeouts keep the normal cadence; forbidden cost requests wait hours rather than retrying every tick.
    nonisolated static func tokenFetchFailureRetryDelay(_ error: Error, ttl: TimeInterval?) -> TimeInterval? {
        switch error {
        case CostUsageError.timedOut: ttl
        default: nil
        }
    }

    func tokenCostIsAccountAgnostic(for provider: UsageProvider) -> Bool {
        // Provider-specific by design: only Codex's explicit ambient scope spans local accounts.
        provider == .codex && self.tokenCostScope(for: provider).signature == "codex:ambient"
    }
}
