import Foundation
import Testing
@testable import CodexBar

struct CodexLoginRunnerTests {
    @Test(.timeLimit(.minutes(1)))
    func `login runner returns timeout before hung codex exits`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-login-runner-\(UUID().uuidString)", isDirectory: true)
        let binDir = root.appendingPathComponent("bin", isDirectory: true)
        let homeDir = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codex = binDir.appendingPathComponent("codex")
        let script = """
        #!/bin/sh
        printf 'login-started\\n'
        while :; do /bin/sleep 1; done
        """
        try script.write(to: codex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)

        let result = await CodexLoginRunner.run(
            homePath: homeDir.path,
            timeout: 30,
            environment: ["PATH": binDir.path],
            loginPATH: nil)

        #expect(result.outcome == .timedOut)
        #expect(result.output.contains("login-started"))
    }
}
