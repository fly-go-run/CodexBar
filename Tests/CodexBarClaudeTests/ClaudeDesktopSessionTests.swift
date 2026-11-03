import CommonCrypto
import CryptoKit
import Foundation
import os.lock
import Security
import SQLite3
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeDesktopSessionTests {
    private static let password = "synthetic-safe-storage-password"
    private static let sessionKey = "sk-ant-sid01-synthetic-desktop-session"

    @Test
    func `opted in desktop session decrypts the claude ai session key`() throws {
        let fixture = try CookieStoreFixture(rows: [.init(value: Self.sessionKey, expiresIn: 86400)])
        let keychain = KeychainRecorder(
            preflight: .allowed,
            read: .init(status: errSecSuccess, password: Self.password))

        let info = self.withHooks(fixture: fixture, keychain: keychain) {
            ClaudeDesktopSession.sessionKeyInfo(logger: { _ in })
        }

        #expect(info?.key == Self.sessionKey)
        #expect(info?.sourceLabel == ClaudeDesktopSession.sourceLabel)
        #expect(keychain.reads == [false])
    }

    @Test
    func `disabled preference never touches the keychain`() throws {
        let fixture = try CookieStoreFixture(rows: [.init(value: Self.sessionKey, expiresIn: 86400)])
        let keychain = KeychainRecorder(
            preflight: .allowed,
            read: .init(status: errSecSuccess, password: Self.password))

        let info = self.withHooks(fixture: fixture, keychain: keychain, enabled: false) {
            ClaudeDesktopSession.sessionKeyInfo(logger: { _ in })
        }

        #expect(info == nil)
        #expect(keychain.preflights == 0)
        #expect(keychain.reads.isEmpty)
    }

    @Test
    func `background refresh skips a safe storage item that would prompt`() throws {
        let fixture = try CookieStoreFixture(rows: [.init(value: Self.sessionKey, expiresIn: 86400)])
        let keychain = KeychainRecorder(
            preflight: .interactionRequired,
            read: .init(status: errSecSuccess, password: Self.password))

        let info = self.withHooks(fixture: fixture, keychain: keychain) {
            ClaudeDesktopSession.sessionKeyInfo(logger: { _ in })
        }

        #expect(info == nil)
        #expect(keychain.reads.isEmpty)
    }

    @Test
    func `user refresh prompts once and reuses the derived key`() throws {
        let fixture = try CookieStoreFixture(rows: [.init(value: Self.sessionKey, expiresIn: 86400)])
        let keychain = KeychainRecorder(
            preflight: .interactionRequired,
            read: .init(status: errSecSuccess, password: Self.password))

        let (first, second) = self.withHooks(fixture: fixture, keychain: keychain) {
            ProviderInteractionContext.$current.withValue(.userInitiated) {
                (
                    ClaudeDesktopSession.sessionKeyInfo(logger: { _ in }),
                    ClaudeDesktopSession.sessionKeyInfo(logger: { _ in }))
            }
        }

        #expect(first?.key == Self.sessionKey)
        #expect(second?.key == Self.sessionKey)
        #expect(keychain.reads == [true])
    }

    @Test
    func `denied prompt is not repeated on the next user refresh`() throws {
        let fixture = try CookieStoreFixture(rows: [.init(value: Self.sessionKey, expiresIn: 86400)])
        let keychain = KeychainRecorder(
            preflight: .interactionRequired,
            read: .init(status: errSecUserCanceled, password: nil))

        let results = self.withHooks(fixture: fixture, keychain: keychain) {
            ProviderInteractionContext.$current.withValue(.userInitiated) {
                [
                    ClaudeDesktopSession.sessionKeyInfo(logger: { _ in }),
                    ClaudeDesktopSession.sessionKeyInfo(logger: { _ in }),
                ]
            }
        }

        #expect(results.allSatisfy { $0 == nil })
        #expect(keychain.reads == [true])
    }

    @Test
    func `expired desktop session is ignored`() throws {
        let fixture = try CookieStoreFixture(rows: [.init(value: Self.sessionKey, expiresIn: -60)])
        let keychain = KeychainRecorder(
            preflight: .allowed,
            read: .init(status: errSecSuccess, password: Self.password))

        let info = self.withHooks(fixture: fixture, keychain: keychain) {
            ClaudeDesktopSession.sessionKeyInfo(logger: { _ in })
        }

        #expect(info == nil)
    }

    @Test
    func `exemption lifts the user preference for one service only`() {
        KeychainAccessGate.withStoredOverrideForTesting(true) {
            #expect(KeychainAccessGate.isDisabled(forService: "Claude Safe Storage"))
            KeychainAccessGate.withUserExemption(forService: "Claude Safe Storage") {
                #expect(!KeychainAccessGate.isDisabled(forService: "Claude Safe Storage"))
                #expect(KeychainAccessGate.isDisabled(forService: "Chrome Safe Storage"))
                #expect(KeychainAccessGate.isDisabled(forService: nil))
            }
        }
    }

    @Test
    func `exempted service stays blocked in test processes`() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Safe Storage",
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = KeychainAccessGate.withUserExemption(forService: "Claude Safe Storage") {
            KeychainSecurity.copyMatching(query as CFDictionary, &result)
        }
        #expect(status == errSecInteractionNotAllowed)
        #expect(result == nil)
    }

    // MARK: - Helpers

    private func withHooks<T>(
        fixture: CookieStoreFixture,
        keychain: KeychainRecorder,
        enabled: Bool = true,
        _ operation: () -> T) -> T
    {
        ClaudeDesktopSession.resetForTesting()
        defer { ClaudeDesktopSession.resetForTesting() }
        let hooks = ClaudeDesktopSession.TestHooks(
            isEnabled: enabled,
            databaseURL: fixture.databaseURL,
            preflight: { keychain.recordPreflight() },
            readSafeStorage: { keychain.recordRead(allowInteraction: $0) })
        return ClaudeDesktopSession.$testHooks.withValue(hooks, operation: operation)
    }
}

private final class KeychainRecorder: Sendable {
    private struct State {
        var preflights = 0
        var reads: [Bool] = []
    }

    private let preflight: KeychainAccessPreflight.Outcome
    private let read: ClaudeDesktopSession.SafeStorageRead
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(preflight: KeychainAccessPreflight.Outcome, read: ClaudeDesktopSession.SafeStorageRead) {
        self.preflight = preflight
        self.read = read
    }

    var preflights: Int {
        self.state.withLock { $0.preflights }
    }

    var reads: [Bool] {
        self.state.withLock { $0.reads }
    }

    func recordPreflight() -> KeychainAccessPreflight.Outcome {
        self.state.withLock { $0.preflights += 1 }
        return self.preflight
    }

    func recordRead(allowInteraction: Bool) -> ClaudeDesktopSession.SafeStorageRead {
        self.state.withLock { $0.reads.append(allowInteraction) }
        return self.read
    }
}

/// A Chromium version-24 cookie store holding synthetic, encrypted claude.ai session rows.
private struct CookieStoreFixture {
    struct Row {
        let value: String
        let expiresIn: TimeInterval
    }

    let databaseURL: URL

    init(rows: [Row], password: String = "synthetic-safe-storage-password") throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-desktop-session-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.databaseURL = directory.appendingPathComponent("Cookies")

        var db: OpaquePointer?
        guard sqlite3_open(self.databaseURL.path, &db) == SQLITE_OK else { throw FixtureError.sqlite }
        defer { sqlite3_close(db) }
        let schema = """
        CREATE TABLE meta(key TEXT, value TEXT);
        INSERT INTO meta VALUES('version', '24');
        CREATE TABLE cookies(host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, expires_utc INTEGER);
        """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else { throw FixtureError.sqlite }

        guard let key = ClaudeDesktopSession.deriveKey(password: password) else { throw FixtureError.encryption }
        for row in rows {
            let encrypted = try Self.encrypt(row.value, key: key, hostKey: ".claude.ai")
            var stmt: OpaquePointer?
            let insert = "INSERT INTO cookies VALUES('.claude.ai', 'sessionKey', '', ?, ?)"
            guard sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK else { throw FixtureError.sqlite }
            defer { sqlite3_finalize(stmt) }
            _ = encrypted.withUnsafeBytes { bytes in
                sqlite3_bind_blob(stmt, 1, bytes.baseAddress, Int32(encrypted.count), nil)
            }
            let expires = ClaudeDesktopSession.chromiumTimestamp(Date().addingTimeInterval(row.expiresIn))
            sqlite3_bind_int64(stmt, 2, expires)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw FixtureError.sqlite }
        }
    }

    private enum FixtureError: Error {
        case sqlite
        case encryption
    }

    private static func encrypt(_ value: String, key: Data, hostKey: String) throws -> Data {
        let plaintext = Data(SHA256.hash(data: Data(hostKey.utf8))) + Data(value.utf8)
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: plaintext.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            plaintext.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            plaintext.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw FixtureError.encryption }
        output.count = outputLength
        return Data("v10".utf8) + output
    }
}
