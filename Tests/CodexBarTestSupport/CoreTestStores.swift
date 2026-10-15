// SwiftBuild also compiles this test-support target for `swift build -c release`,
// where CodexBarCore is not built for testing.
#if DEBUG
import CodexBarCore
import Foundation

/// No Foundation search-domain fallback or persistent writes, including for absent keys.
final class InMemoryUserDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any]

    init(values: [String: Any] = [:]) {
        self.values = values
        super.init(suiteName: "InMemoryUserDefaults-\(UUID().uuidString)")!
    }

    override func object(forKey defaultName: String) -> Any? {
        self.lock.withLock { self.values[defaultName] }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        self.lock.withLock { self.values[defaultName] = value }
    }

    override func removeObject(forKey defaultName: String) {
        self.set(nil as Any?, forKey: defaultName)
    }

    override func bool(forKey defaultName: String) -> Bool {
        (self.object(forKey: defaultName) as? NSNumber)?.boolValue ?? false
    }

    override func integer(forKey defaultName: String) -> Int {
        (self.object(forKey: defaultName) as? NSNumber)?.intValue ?? 0
    }

    override func float(forKey defaultName: String) -> Float {
        (self.object(forKey: defaultName) as? NSNumber)?.floatValue ?? 0
    }

    override func double(forKey defaultName: String) -> Double {
        (self.object(forKey: defaultName) as? NSNumber)?.doubleValue ?? 0
    }

    override func string(forKey defaultName: String) -> String? {
        self.object(forKey: defaultName) as? String
    }

    override func array(forKey defaultName: String) -> [Any]? {
        self.object(forKey: defaultName) as? [Any]
    }

    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        self.object(forKey: defaultName) as? [String: Any]
    }

    override func data(forKey defaultName: String) -> Data? {
        self.object(forKey: defaultName) as? Data
    }

    override func stringArray(forKey defaultName: String) -> [String]? {
        self.object(forKey: defaultName) as? [String]
    }

    override func url(forKey defaultName: String) -> URL? {
        self.object(forKey: defaultName) as? URL
    }

    override func set(_ value: Bool, forKey defaultName: String) {
        self.set(value as Any, forKey: defaultName)
    }

    override func set(_ value: Int, forKey defaultName: String) {
        self.set(value as Any, forKey: defaultName)
    }

    override func set(_ value: Float, forKey defaultName: String) {
        self.set(value as Any, forKey: defaultName)
    }

    override func set(_ value: Double, forKey defaultName: String) {
        self.set(value as Any, forKey: defaultName)
    }

    override func set(_ url: URL?, forKey defaultName: String) {
        self.set(url as Any?, forKey: defaultName)
    }

    override func dictionaryRepresentation() -> [String: Any] {
        self.lock.withLock { self.values }
    }
}

final class InMemoryTokenAccountStore: ProviderTokenAccountStoring, @unchecked Sendable {
    var accounts: [UsageProvider: ProviderTokenAccountData] = [:]
    private let fileURL: URL

    init(fileURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "token-accounts-\(UUID().uuidString).json"))
    {
        self.fileURL = fileURL
    }

    func loadAccounts() throws -> [UsageProvider: ProviderTokenAccountData] {
        self.accounts
    }

    func storeAccounts(_ accounts: [UsageProvider: ProviderTokenAccountData]) throws {
        self.accounts = accounts
    }

    func ensureFileExists() throws -> URL {
        self.fileURL
    }
}

private let testConfigStoreProcessRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("codexbar-tests", isDirectory: true)
    .appendingPathComponent(UUID().uuidString, isDirectory: true)

func testConfigStore(suiteName: String, reset: Bool = true) -> CodexBarConfigStore {
    let sanitized = suiteName.replacingOccurrences(of: "/", with: "-")
    let base = testConfigStoreProcessRoot
        .appendingPathComponent(sanitized, isDirectory: true)
    let url = base.appendingPathComponent("config.json")
    if reset {
        try? FileManager.default.removeItem(at: url)
    }
    return CodexBarConfigStore(fileURL: url)
}
#endif
