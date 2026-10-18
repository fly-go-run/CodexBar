import Foundation

public enum ProviderNetworkFailure {
    /// URL-loading failures that mean "this device cannot reach the network right now".
    public static let offlineURLErrorCodes: Set<Int> = [
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

    /// True for a raw URL-loading error whose code says the device is offline. Timeouts are not offline.
    public static func isOfflineURLError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && self.offlineURLErrorCodes.contains(nsError.code)
    }
}
