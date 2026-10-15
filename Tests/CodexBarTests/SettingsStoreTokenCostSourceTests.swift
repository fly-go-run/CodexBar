import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct SettingsStoreTokenCostSourceTests {
    @Test
    func `token cost source detection includes codex sessions and claude projects`() throws {
        let fileManager = FileManager.default

        let emptyHome = fileManager.temporaryDirectory.appendingPathComponent(
            "empty-token-cost-\(UUID().uuidString)",
            isDirectory: true)
        try fileManager.createDirectory(at: emptyHome, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: emptyHome) }
        #expect(!SettingsStore.hasAnyTokenCostUsageSources(
            env: ["HOME": emptyHome.path],
            fileManager: fileManager,
            homeDirectory: emptyHome))

        let codexHome = fileManager.temporaryDirectory.appendingPathComponent(
            "codex-token-cost-\(UUID().uuidString)",
            isDirectory: true)
        let codexSessions = codexHome
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        try fileManager.createDirectory(at: codexSessions, withIntermediateDirectories: true)
        fileManager.createFile(
            atPath: codexSessions.appendingPathComponent("session.jsonl").path,
            contents: Data("{}".utf8))
        defer { try? fileManager.removeItem(at: codexHome) }

        #expect(SettingsStore.hasAnyTokenCostUsageSources(
            env: ["HOME": codexHome.path],
            fileManager: fileManager,
            homeDirectory: codexHome))

        let claudeHome = fileManager.temporaryDirectory.appendingPathComponent(
            "claude-token-cost-\(UUID().uuidString)",
            isDirectory: true)
        let claudeProjects = claudeHome
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        try fileManager.createDirectory(at: claudeProjects, withIntermediateDirectories: true)
        fileManager.createFile(
            atPath: claudeProjects.appendingPathComponent("session.jsonl").path,
            contents: Data("{}".utf8))
        defer { try? fileManager.removeItem(at: claudeHome) }

        #expect(SettingsStore.hasAnyTokenCostUsageSources(
            env: ["HOME": claudeHome.path],
            fileManager: fileManager,
            homeDirectory: claudeHome))
    }
}
