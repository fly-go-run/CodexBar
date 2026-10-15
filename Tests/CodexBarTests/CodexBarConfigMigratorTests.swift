import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore
@testable import CodexBarTestSupport

@Suite(.serialized)
struct CodexBarConfigMigratorTests {
    @Test(arguments: [false, true])
    @MainActor
    func `settings applies stored keychain policy at startup`(disabled: Bool) throws {
        let suite = "CodexBarConfigMigratorTests-keychain-startup-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(disabled, forKey: "debugDisableKeychainAccess")

        let previousOverride = KeychainAccessGate.currentOverrideForTesting
        defer {
            if let previousOverride {
                KeychainAccessGate.isDisabled = previousOverride
            } else {
                KeychainAccessGate.resetOverrideForTesting()
            }
        }
        KeychainAccessGate.isDisabled = !disabled
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            tokenAccountStore: CountingTokenAccountStore(),
            performInitialProviderDetection: false)

        #expect(store.debugDisableKeychainAccess == disabled)
        #expect(KeychainAccessGate.currentOverrideForTesting == disabled)
    }

    @Test
    func `legacy migration completion flag skips repeated scans`() throws {
        let suite = "CodexBarConfigMigratorTests-skip-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let accountStore = CountingTokenAccountStore()
        let stores = CodexBarConfigMigrator.LegacyStores(tokenAccountStore: accountStore)
        let configStore = testConfigStore(suiteName: suite)

        _ = Self.migrate(configStore: configStore, defaults: defaults, stores: stores)

        let firstAccountLoads = accountStore.loadCount
        #expect(firstAccountLoads == 1)
        #expect(defaults.bool(forKey: Self.legacyMigrationCompletedKey) == true)

        _ = Self.migrate(configStore: configStore, defaults: defaults, stores: stores)

        #expect(accountStore.loadCount == firstAccountLoads)
    }

    @Test
    func `legacy load failures defer completion and retry on the next launch`() throws {
        let suite = "CodexBarConfigMigratorTests-load-failure-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let accountStore = CountingTokenAccountStore(throwOnLoad: true)
        let stores = CodexBarConfigMigrator.LegacyStores(tokenAccountStore: accountStore)
        let configStore = testConfigStore(suiteName: suite)

        _ = Self.migrate(configStore: configStore, defaults: defaults, stores: stores)

        let failedAccountLoads = accountStore.loadCount
        #expect(failedAccountLoads == 1)
        #expect(defaults.bool(forKey: Self.legacyMigrationCompletedKey) == false)

        accountStore.throwOnLoad = false
        _ = Self.migrate(configStore: configStore, defaults: defaults, stores: stores)

        #expect(accountStore.loadCount > failedAccountLoads)
        #expect(defaults.bool(forKey: Self.legacyMigrationCompletedKey))
    }

    private static let legacyMigrationCompletedKey = "codexbar.legacySecretsMigrationCompleted"

    private static func migrate(
        configStore: CodexBarConfigStore,
        defaults: UserDefaults,
        stores: CodexBarConfigMigrator.LegacyStores) -> CodexBarConfig
    {
        CodexBarConfigMigrator.loadOrMigrate(
            configStore: configStore,
            userDefaults: defaults,
            stores: stores)
    }
}

private final class CountingTokenAccountStore: ProviderTokenAccountStoring, @unchecked Sendable {
    private let lock = NSLock()
    var throwOnLoad: Bool
    private(set) var loadCount = 0

    init(throwOnLoad: Bool = false) {
        self.throwOnLoad = throwOnLoad
    }

    func loadAccounts() throws -> [UsageProvider: ProviderTokenAccountData] {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.loadCount += 1
        if self.throwOnLoad {
            throw TestStoreError.loadFailed
        }
        return [:]
    }

    func storeAccounts(_: [UsageProvider: ProviderTokenAccountData]) throws {}

    func ensureFileExists() throws -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("codexbar-empty-accounts.json")
    }
}

private enum TestStoreError: Error {
    case loadFailed
}
