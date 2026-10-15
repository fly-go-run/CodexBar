// SwiftBuild also compiles this test-support target for `swift build -c release`,
// where CodexBarCore is not built for testing.
#if DEBUG
import Darwin
import Foundation
import Testing
@testable import CodexBarCore

struct CostUsageTestEnvironment {
    let root: URL
    let cacheRoot: URL
    let codexHomeRoot: URL
    let codexSessionsRoot: URL
    let codexArchivedSessionsRoot: URL
    let claudeProjectsRoot: URL

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "codexbar-cost-usage-\(UUID().uuidString)",
            isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        self.cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
        self.codexHomeRoot = root.appendingPathComponent("codex-home", isDirectory: true)
        self.codexSessionsRoot = self.codexHomeRoot.appendingPathComponent("sessions", isDirectory: true)
        self.codexArchivedSessionsRoot = self.codexHomeRoot
            .appendingPathComponent("archived_sessions", isDirectory: true)
        self.claudeProjectsRoot = root.appendingPathComponent("claude-projects", isDirectory: true)
        try FileManager.default.createDirectory(at: self.cacheRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.codexSessionsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.codexArchivedSessionsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.claudeProjectsRoot, withIntermediateDirectories: true)
    }

    func cleanup() {
        for provider in [UsageProvider.claude] {
            for context in [CostUsageReportContext.regular, .spendDashboard] {
                CostUsageScanner.evictClaudeReportMemoForTesting(
                    provider: provider, cacheRoot: self.cacheRoot, reportContext: context)
                CostUsageClaudeCacheIO.evictArtifactMemoForTesting(at: CostUsageClaudeCacheIO.cacheFileURL(
                    provider: provider, cacheRoot: self.cacheRoot, reportContext: context))
            }
        }
        try? FileManager.default.removeItem(at: self.root)
    }

    func makeLocalNoon(year: Int, month: Int, day: Int) throws -> Date {
        var comps = DateComponents()
        comps.calendar = Calendar.current
        comps.timeZone = TimeZone.current
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        guard let date = comps.date else { throw NSError(domain: "CostUsageTestEnvironment", code: 1) }
        return date
    }

    func isoString(for date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.string(from: date)
    }

    func writeCodexSessionFile(day: Date, filename: String, contents: String) throws -> URL {
        let url = try self.codexSessionFileURL(day: day, filename: filename)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func seedCodexSessionFile(day: Date, filename: String, contents: String) throws -> URL {
        let url = try self.codexSessionFileURL(day: day, filename: filename)
        // Initial corpus files have no readers until setup returns; no atomic publication or fsync is needed.
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o666)
        guard descriptor >= 0 else {
            let code = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data(contents.utf8))
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        return url
    }

    private func codexSessionFileURL(day: Date, filename: String) throws -> URL {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        let y = String(format: "%04d", comps.year ?? 1970)
        let m = String(format: "%02d", comps.month ?? 1)
        let d = String(format: "%02d", comps.day ?? 1)

        let dir = self.codexSessionsRoot
            .appendingPathComponent(y, isDirectory: true)
            .appendingPathComponent(m, isDirectory: true)
            .appendingPathComponent(d, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        return dir.appendingPathComponent(filename, isDirectory: false)
    }

    func writeClaudeProjectFile(relativePath: String, contents: String) throws -> URL {
        let url = self.claudeProjectsRoot.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func writeClaudeDesktopLocalAgentFile(relativePath: String, contents: String) throws -> URL {
        let localAgentRoot = self.root
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Claude", isDirectory: true)
            .appendingPathComponent("local-agent-mode-sessions", isDirectory: true)
            .appendingPathComponent("workspace-id", isDirectory: true)
            .appendingPathComponent("session-id", isDirectory: true)
            .appendingPathComponent("local_agent", isDirectory: true)
        let url = localAgentRoot.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func writeClaudeDesktopLocalAgentProjectFile(relativePath: String, contents: String) throws -> URL {
        try self.writeClaudeDesktopLocalAgentFile(
            relativePath: ".claude/projects/\(relativePath)",
            contents: contents)
    }

    func writeClaudeDesktopCodeSessionProjectFile(relativePath: String, contents: String) throws -> URL {
        let projectsRoot = self.root
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Claude", isDirectory: true)
            .appendingPathComponent("claude-code-sessions", isDirectory: true)
            .appendingPathComponent("account-id", isDirectory: true)
            .appendingPathComponent("org-id", isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        let url = projectsRoot.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func writeClaudeDesktopSharedProjectFile(relativePath: String, contents: String) throws -> URL {
        let projectsRoot = self.root
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        let url = projectsRoot.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func writeNestedClaudeDesktopLocalAgentProjectFile(relativePath: String, contents: String) throws -> URL {
        let projectsRoot = self.root
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Claude", isDirectory: true)
            .appendingPathComponent("local-agent-mode-sessions", isDirectory: true)
            .appendingPathComponent("workspace-id", isDirectory: true)
            .appendingPathComponent("session-id", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("local_agent", isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        let url = projectsRoot.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func writeCodexArchivedSessionFile(filename: String, contents: String) throws -> URL {
        let url = self.codexArchivedSessionsRoot.appendingPathComponent(filename, isDirectory: false)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func jsonl(_ objects: [Any]) throws -> String {
        let lines = try objects.map { obj in
            let data = try JSONSerialization.data(withJSONObject: obj)
            guard let text = String(bytes: data, encoding: .utf8) else {
                throw NSError(domain: "CostUsageTestEnvironment", code: 2)
            }
            return text
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
#endif
