import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore
@testable import CodexBarTestSupport

@Suite(.serialized)
struct CodexBarConfigMigratorTests {
    @Test(arguments: [false, true])
    @MainActor
    func `settings applies stored keychain policy before legacy migration`(disabled: Bool) throws {
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
        let secrets = CountingLegacySecretStore()
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            codexCookieStore: secrets,
            claudeCookieStore: secrets,
            tokenAccountStore: CountingTokenAccountStore(),
            performInitialProviderDetection: false)

        #expect(store.debugDisableKeychainAccess == disabled)
        #expect(!secrets.keychainAccessOverridesAtLoad.isEmpty)
        #expect(secrets.keychainAccessOverridesAtLoad.allSatisfy { $0 == disabled })
    }

    @Test
    func `legacy secret migration completion flag skips repeated scans`() throws {
        let suite = "CodexBarConfigMigratorTests-skip-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let secrets = CountingLegacySecretStore()
        let accountStore = CountingTokenAccountStore()
        let stores = Self.legacyStores(secrets: secrets, accountStore: accountStore)
        let configStore = testConfigStore(suiteName: suite)

        _ = Self.migrate(configStore: configStore, defaults: defaults, stores: stores)

        let firstSecretLoads = secrets.loadCount
        let firstAccountLoads = accountStore.loadCount
        #expect(firstSecretLoads > 0)
        #expect(firstAccountLoads == 1)
        #expect(defaults.bool(forKey: Self.legacyMigrationCompletedKey) == true)

        _ = Self.migrate(configStore: configStore, defaults: defaults, stores: stores)

        #expect(secrets.loadCount == firstSecretLoads)
        #expect(accountStore.loadCount == firstAccountLoads)
    }

    @Test
    func `legacy migration completion waits for successful cleanup`() throws {
        let suite = "CodexBarConfigMigratorTests-cleanup-failure-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let secrets = CountingLegacySecretStore(token: "legacy-token", throwOnStore: true)
        let accountStore = CountingTokenAccountStore()
        let stores = Self.legacyStores(secrets: secrets, accountStore: accountStore)
        let configStore = testConfigStore(suiteName: suite)

        _ = Self.migrate(configStore: configStore, defaults: defaults, stores: stores)

        let firstSecretLoads = secrets.loadCount
        #expect(firstSecretLoads > 0)
        #expect(secrets.clearAttempts > 0)
        #expect(defaults.bool(forKey: Self.legacyMigrationCompletedKey) == false)

        secrets.throwOnStore = false
        _ = Self.migrate(configStore: configStore, defaults: defaults, stores: stores)

        #expect(secrets.loadCount > firstSecretLoads)
        #expect(defaults.bool(forKey: Self.legacyMigrationCompletedKey) == true)
    }

    @Test
    func `all legacy load failures defer cleanup and retry on the next launch`() throws {
        let suite = "CodexBarConfigMigratorTests-load-failure-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let secrets = CountingLegacySecretStore(throwOnLoad: true)
        let accountStore = CountingTokenAccountStore(throwOnLoad: true)
        let stores = Self.legacyStores(secrets: secrets, accountStore: accountStore)
        let configStore = testConfigStore(suiteName: suite)

        _ = CodexBarConfigMigrator.loadOrMigrate(
            configStore: configStore,
            userDefaults: defaults,
            keychainAccessDisabled: false,
            stores: stores)

        let failedSecretLoads = secrets.loadCount
        let failedAccountLoads = accountStore.loadCount
        #expect(failedSecretLoads > 0)
        #expect(failedAccountLoads == 1)
        #expect(secrets.clearAttempts == 0)
        #expect(defaults.bool(forKey: Self.legacyMigrationCompletedKey) == false)

        secrets.throwOnLoad = false
        accountStore.throwOnLoad = false
        _ = CodexBarConfigMigrator.loadOrMigrate(
            configStore: configStore,
            userDefaults: defaults,
            keychainAccessDisabled: false,
            stores: stores)

        #expect(secrets.loadCount > failedSecretLoads)
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
            keychainAccessDisabled: false,
            stores: stores)
    }

    private static func legacyStores(
        secrets: CountingLegacySecretStore,
        accountStore: CountingTokenAccountStore) -> CodexBarConfigMigrator.LegacyStores
    {
        CodexBarConfigMigrator.LegacyStores(
            codexCookieStore: secrets,
            claudeCookieStore: secrets,
            tokenAccountStore: accountStore)
    }
}

private final class CountingLegacySecretStore: CookieHeaderStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    var throwOnLoad: Bool
    var throwOnStore: Bool
    var hideTokenOnLoad = false
    private(set) var loadCount = 0
    private(set) var clearAttempts = 0
    private(set) var keychainAccessOverridesAtLoad: [Bool?] = []

    init(token: String? = nil, throwOnLoad: Bool = false, throwOnStore: Bool = false) {
        self.token = token
        self.throwOnLoad = throwOnLoad
        self.throwOnStore = throwOnStore
    }

    func loadCookieHeader() throws -> String? {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.loadCount += 1
        self.keychainAccessOverridesAtLoad.append(KeychainAccessGate.currentOverrideForTesting)
        if self.throwOnLoad {
            throw TestStoreError.loadFailed
        }
        return self.hideTokenOnLoad ? nil : self.token
    }

    func storeCookieHeader(_ header: String?) throws {
        try self.store(header)
    }

    private func store(_ value: String?) throws {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.clearAttempts += value == nil ? 1 : 0
        if self.throwOnStore {
            throw TestStoreError.storeFailed
        }
        self.token = value
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
    case storeFailed
}
