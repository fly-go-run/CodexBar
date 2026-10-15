import CryptoKit
import Foundation

extension CookieHeaderCache {
    /// Stable, non-reversible identifier for a normalized credential. Safe for cache-scope
    /// comparisons; never expose the cookie header itself to UI, logs, or persisted reports.
    public static func credentialFingerprint(_ cookieHeader: String) -> String {
        let normalized = CookieHeaderNormalizer.normalize(cookieHeader) ?? cookieHeader
        return SHA256.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
