import Darwin
import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct BoundedChildProcessProofTests {
    @Test
    func `synthetic PTY child overflow propagates and cleans up the process`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBarBoundedProcessProof-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pidURL = directory.appendingPathComponent("child.pid")
        let scriptURL = directory.appendingPathComponent("overflow-child.sh")
        // Keep one unbounded block writer in the tracked process so PTY pipeline behavior cannot affect the proof.
        let script = """
        #!/bin/sh
        printf '%s\\n' "$$" > "$CODEXBAR_PROOF_PID_FILE"
        exec /bin/dd if=/dev/zero bs=1048576
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        var environment = ProcessInfo.processInfo.environment
        environment["CODEXBAR_PROOF_PID_FILE"] = pidURL.path
        let runner = TTYCommandRunner()
        let start = ContinuousClock.now
        do {
            _ = try TTYCommandRunner.withOutputLimitOverrideForTesting(64 * 1024) {
                try runner.run(
                    binary: scriptURL.path,
                    send: "",
                    options: .init(timeout: 60, baseEnvironment: environment, initialDelay: 0))
            }
            Issue.record("Expected the synthetic child to exceed the PTY output limit")
        } catch TTYCommandRunner.Error.outputTooLarge {
            // Expected: the production runner propagated the bounded-output error.
        } catch {
            Issue.record("Unexpected overflow error: \(error)")
        }
        // A small test-only limit isolates abort latency from the host's PTY throughput.
        #expect(start.duration(to: .now) < .seconds(15))

        let pidText = try String(contentsOf: pidURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try #require(pid_t(pidText))
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }
}
