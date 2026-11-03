import CommonCrypto
import CryptoKit
import Foundation
import os.lock
import Security
import SQLite3

/// The claude.ai session the Claude desktop app keeps in its own Chromium cookie store.
///
/// The desktop app renews this session whenever it is used, so it stays current without a browser visit.
/// Decrypting it needs the app's "Claude Safe Storage" Keychain secret. The opt-in exempts exactly that item
/// from "Disable Keychain access": background reads never show UI, a user-initiated refresh may ask macOS once,
/// and the derived key is reused for the rest of the process.
public enum ClaudeDesktopSession {
    public static let sourceLabel = "Claude Desktop"
    public static let preferenceKey = "claudeDesktopSessionEnabled"
    static let safeStorageService = "Claude Safe Storage"
    private static let denialCooldown: TimeInterval = 6 * 60 * 60
    private static let log = CodexBarLog.logger(LogCategories.browserCookieGate)

    struct SafeStorageRead {
        let status: OSStatus
        let password: String?
    }

    private struct KeyState {
        var derivedKey: Data?
        var interactiveReadInFlight = false
        var deniedUntil: Date?
    }

    private static let state = OSAllocatedUnfairLock(initialState: KeyState())

    #if DEBUG
    struct TestHooks: Sendable {
        var isEnabled: Bool
        var databaseURL: URL
        var preflight: @Sendable () -> KeychainAccessPreflight.Outcome
        var readSafeStorage: @Sendable (_ allowInteraction: Bool) -> SafeStorageRead
    }

    @TaskLocal static var testHooks: TestHooks?
    #endif

    // MARK: - Preference

    public static func isEnabled(userDefaults: UserDefaults? = nil) -> Bool {
        #if DEBUG
        if let testHooks { return testHooks.isEnabled }
        // Unit tests must not inherit the developer's persisted opt-in.
        if userDefaults == nil, KeychainTestSafety.shouldIsolateUserStateUnderTests() { return false }
        #endif
        let defaults = userDefaults ?? ClaudeOAuthApplicationDefaults.resolve(
            domain: ClaudeOAuthKeychainPromptPreference.applicationDefaultsDomain)
        return defaults.bool(forKey: self.preferenceKey)
    }

    // MARK: - Session

    /// The desktop app's claude.ai session key, or nil when the opt-in is off, the app has no session,
    /// or the Safe Storage secret is not readable without a prompt this refresh may not show.
    static func sessionKeyInfo(logger: (String) -> Void) -> ClaudeWebAPIFetcher.SessionKeyInfo? {
        guard self.isEnabled() else { return nil }
        let databaseURL = self.cookieDatabaseURL()
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        // Resolve the key before touching the cookie store so an unauthorized background tick costs one preflight.
        guard let key = self.decryptionKey(logger: logger) else { return nil }
        do {
            guard let cookie = try self.readSessionCookie(databaseURL: databaseURL) else {
                logger("Claude Desktop has no claude.ai session")
                return nil
            }
            let value: String? = if let plain = cookie.plainValue, !plain.isEmpty {
                plain
            } else {
                self.decrypt(cookie.encryptedValue, key: key, hostKey: cookie.hostKey, databaseVersion: cookie.version)
            }
            guard let sessionKey = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  sessionKey.hasPrefix("sk-ant-")
            else {
                logger("Claude Desktop session could not be decrypted")
                return nil
            }
            return ClaudeWebAPIFetcher.SessionKeyInfo(key: sessionKey, sourceLabel: self.sourceLabel, cookieCount: 1)
        } catch {
            logger("Claude Desktop cookie read failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func cookieDatabaseURL() -> URL {
        #if DEBUG
        if let testHooks { return testHooks.databaseURL }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/Cookies")
    }

    // MARK: - Safe Storage key

    private static func decryptionKey(logger: (String) -> Void) -> Data? {
        if let cached = self.state.withLock({ $0.derivedKey }) { return cached }
        guard let password = self.safeStoragePassword(logger: logger),
              let key = self.deriveKey(password: password)
        else {
            return nil
        }
        self.state.withLock { $0.derivedKey = key }
        return key
    }

    private static func safeStoragePassword(logger: (String) -> Void) -> String? {
        KeychainAccessGate.withUserExemption(forService: self.safeStorageService) {
            switch self.preflight() {
            case .allowed:
                self.readSafeStorage(allowInteraction: false).password
            case .notFound, .failure:
                nil
            case .interactionRequired, .temporarilyUnavailable:
                self.interactiveSafeStoragePassword(logger: logger)
            }
        }
    }

    /// At most one prompt at a time, only from a user action, and none for six hours after a denial.
    private static func interactiveSafeStoragePassword(logger: (String) -> Void) -> String? {
        guard ProviderInteractionContext.current == .userInitiated else {
            logger("Claude Desktop needs a one-time Keychain approval; click Refresh to allow it")
            return nil
        }
        let now = Date()
        let claimed = self.state.withLock { state -> Bool in
            if let deniedUntil = state.deniedUntil, deniedUntil > now { return false }
            guard !state.interactiveReadInFlight else { return false }
            state.interactiveReadInFlight = true
            return true
        }
        guard claimed else { return nil }
        let read = self.readSafeStorage(allowInteraction: true)
        self.state.withLock { state in
            state.interactiveReadInFlight = false
            if read.status == errSecUserCanceled || read.status == errSecAuthFailed {
                state.deniedUntil = now.addingTimeInterval(self.denialCooldown)
            }
        }
        if read.password == nil {
            self.log.info("Claude Safe Storage was not approved", metadata: ["status": "\(read.status)"])
        }
        return read.password
    }

    private static func preflight() -> KeychainAccessPreflight.Outcome {
        #if DEBUG
        if let testHooks { return testHooks.preflight() }
        #endif
        return KeychainAccessPreflight.checkGenericPassword(service: self.safeStorageService, account: nil)
    }

    private static func readSafeStorage(allowInteraction: Bool) -> SafeStorageRead {
        #if DEBUG
        if let testHooks { return testHooks.readSafeStorage(allowInteraction) }
        #endif
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.safeStorageService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        if !allowInteraction {
            KeychainNoUIQuery.apply(to: &query)
        }
        var result: CFTypeRef?
        let status = KeychainSecurity.copyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return SafeStorageRead(status: status, password: nil)
        }
        return SafeStorageRead(status: status, password: String(data: data, encoding: .utf8))
    }

    static func deriveKey(password: String) -> Data? {
        let salt = Data("saltysalt".utf8)
        let passwordBytes = Array(password.utf8)
        var key = Data(count: kCCKeySizeAES128)
        let keyLength = key.count
        let status = key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.map { Int8(bitPattern: $0) },
                    passwordBytes.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    1003,
                    keyBytes.bindMemory(to: UInt8.self).baseAddress,
                    keyLength)
            }
        }
        return status == kCCSuccess ? key : nil
    }

    // MARK: - Cookie store

    struct StoredCookie {
        let hostKey: String
        let plainValue: String?
        let encryptedValue: Data
        let version: Int
    }

    enum ReadError: LocalizedError {
        case sqlite(String)

        var errorDescription: String? {
            switch self {
            case let .sqlite(message): "SQLite error: \(message)"
            }
        }
    }

    /// Reads a private copy so the running desktop app's lock and journal never block or corrupt the read.
    static func readSessionCookie(databaseURL: URL, now: Date = Date()) throws -> StoredCookie? {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-claude-desktop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let copiedDB = tempDir.appendingPathComponent("Cookies")
        try FileManager.default.copyItem(at: databaseURL, to: copiedDB)
        for suffix in ["-wal", "-shm"] {
            let source = URL(fileURLWithPath: databaseURL.path + suffix)
            if FileManager.default.fileExists(atPath: source.path) {
                try? FileManager.default.copyItem(at: source, to: URL(fileURLWithPath: copiedDB.path + suffix))
            }
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copiedDB.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            defer { sqlite3_close(db) }
            throw ReadError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_close(db) }

        let version = try self.databaseVersion(db)
        let sql = """
        SELECT host_key, value, encrypted_value FROM cookies
        WHERE name = 'sessionKey' AND host_key IN ('claude.ai', '.claude.ai')
          AND (expires_utc = 0 OR expires_utc > ?)
        ORDER BY expires_utc DESC
        LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ReadError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, self.chromiumTimestamp(now))

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let hostKey = String(cString: sqlite3_column_text(stmt, 0))
        let plainValue = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
        let encryptedValue = if let bytes = sqlite3_column_blob(stmt, 2) {
            Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 2)))
        } else {
            Data()
        }
        return StoredCookie(hostKey: hostKey, plainValue: plainValue, encryptedValue: encryptedValue, version: version)
    }

    private static func databaseVersion(_ db: OpaquePointer?) throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = 'version'", -1, &stmt, nil) == SQLITE_OK
        else {
            throw ReadError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw ReadError.sqlite("Cookie database version is missing.") }
        return Int(sqlite3_column_int(stmt, 0))
    }

    /// Chromium stores times as microseconds since 1601-01-01 UTC.
    static func chromiumTimestamp(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 + 11_644_473_600) * 1_000_000)
    }

    // MARK: - Decryption

    /// Chromium's macOS `v10` scheme: AES-128-CBC with a space-filled IV. Version 24+ stores prefix the
    /// plaintext with SHA-256 of the cookie's host.
    static func decrypt(_ encrypted: Data, key: Data, hostKey: String, databaseVersion: Int) -> String? {
        guard encrypted.count > 3, encrypted.prefix(3) == Data("v10".utf8) else { return nil }
        let ciphertext = Data(encrypted.dropFirst(3))
        guard !ciphertext.isEmpty, ciphertext.count.isMultiple(of: kCCBlockSizeAES128) else { return nil }
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: ciphertext.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            ciphertext.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.count = outputLength
        if databaseVersion >= 24 {
            let hostHash = Data(SHA256.hash(data: Data(hostKey.utf8)))
            guard output.starts(with: hostHash) else { return nil }
            output = Data(output.dropFirst(hostHash.count))
        }
        return String(data: output, encoding: .utf8)
    }

    #if DEBUG
    static func resetForTesting() {
        self.state.withLock { $0 = KeyState() }
    }
    #endif
}
