import CodexBarCore
import Foundation
import Network

// MARK: - Offline classification

extension UsageStore {
    /// Prior data older than this stops being quietly kept: the card shows a calm offline notice instead.
    static let offlineStaleSurfaceInterval: TimeInterval = 6 * 60 * 60
    /// Connectivity must stay restored this long before a recovery refresh starts, so flapping links do not storm.
    static let networkRecoveryDebounce: TimeInterval = 2

    /// URL-loading failures that mean "this device cannot reach the network right now".
    nonisolated static let offlineURLErrorCodes: Set<Int> = [
        NSURLErrorNotConnectedToInternet,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorCannotFindHost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorDNSLookupFailed,
        NSURLErrorDataNotAllowed,
        NSURLErrorInternationalRoamingOff,
        NSURLErrorCallIsActive,
        // Captive portals and half-open links commonly surface as TLS failures.
        NSURLErrorSecureConnectionFailed,
    ]

    /// Offline codes plus timeouts: failures a later retry on a healthy network is expected to fix.
    nonisolated static let transientURLErrorCodes: Set<Int> = UsageStore.offlineURLErrorCodes
        .union([NSURLErrorTimedOut])

    nonisolated static func messageIndicatesOffline(_ message: String) -> Bool {
        let message = message.lowercased()
        return message.contains("not connected to the internet") ||
            message.contains("appears to be offline") ||
            message.contains("network connection was lost")
    }

    nonisolated static func messageIndicatesTimeout(_ message: String) -> Bool {
        let message = message.lowercased()
        return message.contains("timed out") || message.contains("timeout")
    }

    /// True when the failure says the device is offline (as opposed to the provider rejecting or timing out).
    nonisolated static func isOfflineNetworkError(_ error: Error) -> Bool {
        let transportError = self.underlyingProviderTransportError(error)
        if transportError is CancellationError { return false }
        let nsError = transportError as NSError
        if nsError.domain == NSURLErrorDomain {
            return self.offlineURLErrorCodes.contains(nsError.code)
        }
        return self.messageIndicatesOffline(error.localizedDescription)
    }

    /// Offline failures plus timeouts. Cancellation is never transient connectivity.
    nonisolated static func isTransientNetworkError(_ error: Error) -> Bool {
        let transportError = self.underlyingProviderTransportError(error)
        if transportError is CancellationError { return false }
        let nsError = transportError as NSError
        if nsError.domain == NSURLErrorDomain {
            return self.transientURLErrorCodes.contains(nsError.code)
        }
        let message = error.localizedDescription
        return self.messageIndicatesOffline(message) || self.messageIndicatesTimeout(message)
    }

    /// Offline either by the error itself, or because the network path is down and the error is a transient one.
    func isOfflineRefreshFailure(_ error: Error) -> Bool {
        Self.isOfflineNetworkError(error) || (self.networkPathUnsatisfied && Self.isTransientNetworkError(error))
    }

    enum OfflineDisposition {
        /// Not a connectivity failure: normal error handling applies.
        case none
        /// Connectivity failure that still needs the normal surfacing path (cold start, or data not preservable).
        case offline
        /// Connectivity failure fully handled here: the snapshot stays and the provider is marked offline.
        case absorbed
    }

    /// Classifies a refresh failure and, when prior data exists, absorbs it as an offline state: the snapshot stays,
    /// no error is published, and a calm notice appears only once the data is very stale.
    func offlineDisposition(
        for error: Error,
        id instanceID: ProviderInstanceID,
        prior: (hadData: Bool, preserved: Bool),
        now: Date = Date()) -> OfflineDisposition
    {
        self.offlineProviders.remove(instanceID)
        guard self.isOfflineRefreshFailure(error) else { return .none }
        guard prior.hadData, prior.preserved, let snapshot = self.snapshots[instanceID] else { return .offline }
        self.offlineProviders.insert(instanceID)
        if now.timeIntervalSince(snapshot.updatedAt) > Self.offlineStaleSurfaceInterval {
            self.errors[instanceID] = L("Offline · data may be outdated")
        } else {
            self.errors[instanceID] = nil
        }
        return .absorbed
    }
}

// MARK: - Network path monitoring

extension UsageStore {
    func startNetworkPathMonitor() {
        guard self.networkPathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handleNetworkPathChange(isSatisfied: satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.steipete.codexbar.network-path", qos: .utility))
        self.networkPathMonitor = monitor
    }

    /// Tracks connectivity and, on an unsatisfied -> satisfied transition, schedules one debounced recovery refresh.
    func handleNetworkPathChange(isSatisfied: Bool) {
        let wasUnsatisfied = self.networkPathUnsatisfied
        self.networkPathUnsatisfied = !isSatisfied
        guard isSatisfied else {
            // Went (or stayed) offline: a recovery that was waiting out the debounce is no longer valid.
            self.networkRecoveryTask?.cancel()
            self.networkRecoveryTask = nil
            return
        }
        guard wasUnsatisfied, self.networkRecoveryTask == nil, self.hasProviderAwaitingNetworkRecovery() else {
            return
        }
        self.networkRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // A cancelled task was already replaced or cleared by whoever cancelled it.
            defer { if !Task.isCancelled { self.networkRecoveryTask = nil } }
            do {
                try await self.sleepForNetworkRecovery(Self.networkRecoveryDebounce)
            } catch {
                return
            }
            guard !Task.isCancelled, !self.networkPathUnsatisfied else { return }
            await self.refreshAfterNetworkRecovery()
        }
    }

    func hasProviderAwaitingNetworkRecovery() -> Bool {
        self.enabledProviders().contains { self.offlineProviders.contains($0) || self.errors[$0] != nil }
    }

    private func refreshAfterNetworkRecovery() async {
        if let override = self._test_networkRecoveryRefresh {
            await override()
            return
        }
        // Reuse the startup retry chain: if providers still fail it keeps retrying with backoff.
        // Required refreshes coalesce with any refresh already queued or running.
        await self.runRefresh(startupConnectivityRetryAttempt: 1, waitForRefreshAvailability: true)
    }

    private func sleepForNetworkRecovery(_ delay: TimeInterval) async throws {
        if let override = self._test_networkRecoverySleepOverride {
            try await override(delay)
            return
        }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}
