import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct SettingsConfigTerminationTests {
    @Test
    func `quit preserves a provider toggle before its debounce expires`() async throws {
        try await self.withSettings { settings in
            let metadata = try #require(ProviderRegistry.shared.metadata[.claude])
            settings.setProviderEnabled(provider: .claude, metadata: metadata, enabled: true)
            #expect(try settings.configStore.load()?.providerConfig(for: .claude)?.enabled == false)

            let approved = try await self.configAtTerminationApproval(settings)

            #expect(approved.providerConfig(for: .claude)?.enabled == true)
        }
    }

    private func makeDelegate(_ settings: SettingsStore) -> AppDelegate {
        let delegate = AppDelegate()
        // Avoid configure's unrelated CloudSyncPersistence reads and lazy UI dependencies.
        delegate._test_configureSettings(settings)
        return delegate
    }

    private func configAtTerminationApproval(_ settings: SettingsStore) async throws -> CodexBarConfig {
        let delegate = self.makeDelegate(settings)
        var approved = false
        var diskConfig: CodexBarConfig?
        delegate.replyToApplicationShouldTerminate = { _, shouldTerminate in
            #expect(shouldTerminate)
            diskConfig = try? settings.configStore.load()
            approved = true
        }
        // The optional protocol call also works on the original implementation, whose absent
        // delegate method permits immediate termination. Never ask NSApplication to terminate.
        let response = (delegate as NSApplicationDelegate)
            .applicationShouldTerminate?(NSApplication.shared) ?? .terminateNow
        if response == .terminateNow {
            diskConfig = try settings.configStore.load()
            approved = true
        } else {
            #expect(response == .terminateLater)
        }
        try await self.waitUntil { approved }
        return try #require(diskConfig)
    }

    private func withSettings(
        fileManager: FileManager? = nil,
        _ operation: (SettingsStore) async throws -> Void) async throws
    {
        let settings: SettingsStore
        if let fileManager {
            let fixture = testConfigStore(suiteName: "SettingsConfigTerminationTests-\(UUID().uuidString)")
            let configStore = CodexBarConfigStore(fileURL: fixture.fileURL, fileManager: fileManager)
            try configStore.save(testConfigWithAllProvidersDisabled())
            settings = SettingsStore(
                userDefaults: InMemoryUserDefaults(),
                configStore: configStore,
                tokenAccountStore: InMemoryTokenAccountStore(),
                keychainAccessPolicy: SettingsStoreKeychainAccessPolicy(
                    setDisabled: { _ in }, isExplicitlyDisabled: { true }))
        } else {
            settings = testSettingsStore(
                suiteName: "SettingsConfigTerminationTests",
                userDefaults: InMemoryUserDefaults(),
                config: testConfigWithAllProvidersDisabled())
        }
        settings._test_configPersistenceUsesDebounce = true
        defer { try? FileManager.default.removeItem(at: settings.configStore.fileURL.deletingLastPathComponent()) }
        do {
            try await operation(settings)
        } catch {
            await self.drainSaves(settings)
            throw error
        }
        await self.drainSaves(settings)
    }

    private func drainSaves(_ settings: SettingsStore) async {
        while let pending = settings.configPersistTask {
            await pending.value
            if settings.configPersistTask == pending { break }
        }
    }

    private func deliverTerminationReplies() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        while !condition() {
            self.deliverTerminationReplies()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class PausingConfigFileManager: FileManager {
    private let lock = NSLock()
    private let resumeWriter = DispatchSemaphore(value: 0)
    private var pauseRequested = false
    private var paused = false
    private var finishedWaiting = false

    var writerIsPaused: Bool {
        self.lock.withLock { self.paused }
    }

    var writerFinishedWaiting: Bool {
        self.lock.withLock { self.finishedWaiting }
    }

    func pauseNextWrite() {
        self.lock.withLock {
            self.pauseRequested = true
            self.finishedWaiting = false
        }
    }

    func releaseWriter() {
        self.resumeWriter.signal()
    }

    func releaseWriterSoon() {
        let semaphore = self.resumeWriter
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            semaphore.signal()
        }
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil) throws
    {
        let shouldPause = self.lock.withLock {
            guard self.pauseRequested else { return false }
            self.pauseRequested = false
            self.paused = true
            return true
        }
        if shouldPause {
            self.resumeWriter.wait()
            self.lock.withLock { self.finishedWaiting = true }
        }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
}
