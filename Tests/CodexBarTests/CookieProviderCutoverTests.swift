import Foundation
import SweetCookieKit
import Testing
@testable import CodexBarCore

enum CookieProviderCutoverTests {
    private static let perplexityBody = """
    {
      "balance_cents": 500,
      "renewal_date_ts": 1893456000,
      "current_period_purchased_cents": 0,
      "credit_grants": [
        {
          "type": "recurring",
          "amount_cents": 1000
        }
      ],
      "total_usage_cents": 500
    }
    """
    private static let qoderBody = #"{"totalQuota":{"quotaSummary":{"usedValue":25,"limitValue":100}}}"#

    private static func isolated<T>(_ service: String, operation: () throws -> T) rethrows -> T {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        return try KeychainCacheStore.withImplicitTestStoreForTesting {
            try KeychainCacheStore.withServiceOverrideForTesting(service) {
                try CookieHeaderCache.withLegacyBaseURLOverrideForTesting(base, operation: operation)
            }
        }
    }
}

extension CookieProviderCutoverTests {}

extension CookieProviderCutoverTests {}
