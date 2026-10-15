import Foundation
import Testing
@testable import CodexBarCore

struct AgentSessionParserTests {
    @Test
    func `chatgpt bundled codex app server is recognized without becoming a live agent`() {
        let records = AgentPSOutputParser.parse("""
        4234 1 Mon Jul 6 09:03:00 2026 /Applications/ChatGPT.app/Contents/Resources/codex \
        -c features.code_mode_host=true app-server --analytics-default-enabled
        20409 1 Mon Jul 6 09:04:00 2026 /Applications/ChatGPT.app/Contents/Resources/codex-code-mode-host
        """)

        #expect(records.count == 2)
        #expect(AgentPSOutputParser.agentProcesses(from: records).isEmpty)
        #expect(AgentPSOutputParser.hasCodexAppServer(in: records))
    }

    @Test
    func `lsof parser maps batched cwd records`() throws {
        let output = try Self.fixtureString("agent-sessions-lsof", extension: "txt")
        let paths = LSOFCWDOutputParser.parse(output)

        #expect(paths[102] == "/Users/test/Projects/alpha")
        #expect(paths[201] == "/Users/test/Projects/project with spaces")
    }

    @Test
    func `same cwd processes remain uncorrelated when ownership is ambiguous`() {
        let olderStart = Date(timeIntervalSince1970: 100)
        let newerStart = Date(timeIntervalSince1970: 200)
        let older = AgentProcessRecord(pid: 10, ppid: 1, startedAt: olderStart, command: "claude")
        let newer = AgentProcessRecord(pid: 20, ppid: 1, startedAt: newerStart, command: "claude")
        let olderTranscript = ClaudeSessionProjectMapper.Transcript(
            url: URL(fileURLWithPath: "/tmp/older.jsonl"),
            modifiedAt: Date(timeIntervalSince1970: 150))
        let newerTranscript = ClaudeSessionProjectMapper.Transcript(
            url: URL(fileURLWithPath: "/tmp/newer.jsonl"),
            modifiedAt: Date(timeIntervalSince1970: 250))

        let assignments = AgentSessionCorrelation.assignClaudeTranscripts(
            processes: [older, newer],
            cwdByPID: [10: "/project", 20: "/project"],
            transcriptsByCWD: ["/project": [newerTranscript, olderTranscript]])

        #expect(assignments.isEmpty)
    }

    @Test
    func `newest process sorts first for rollout correlation`() {
        let older = AgentProcessRecord(
            pid: 10,
            ppid: 1,
            startedAt: Date(timeIntervalSince1970: 100),
            command: "codex exec")
        let newer = AgentProcessRecord(
            pid: 20,
            ppid: 1,
            startedAt: Date(timeIntervalSince1970: 200),
            command: "codex exec")

        #expect(AgentSessionCorrelation.newestProcessesFirst([older, newer]).map(\ .pid) == [20, 10])
    }

    static func fixtureURL(_ name: String, extension fileExtension: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Fixtures"))
    }

    static func fixtureString(_ name: String, extension fileExtension: String) throws -> String {
        try String(contentsOf: self.fixtureURL(name, extension: fileExtension), encoding: .utf8)
    }
}

struct ChatGPTCodexProcessTrustTests {
    private static let nested =
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"

    @Test(arguments: [
        "/Applications/ChatGPT.app/Contents/Resources/codex",
        Self.nested,
    ])
    func `signed process validates outer ChatGPT bundle rather than nested CLI bundle`(path: String) {
        let trusted = ChatGPTCodexProcessTrust.isTrusted(
            123,
            executablePath: { pid in
                #expect(pid == 123)
                return path
            },
            resolvePath: { $0 },
            processIsTrusted: { $0 == 123 },
            appIsTrusted: { bundle in
                #expect(bundle == "/Applications/ChatGPT.app")
                return true
            })
        #expect(trusted)
    }

    @Test(arguments: [
        nil,
        "/tmp/codex",
        "/Users/test/Applications/ChatGPT.app/Contents/Resources/codex",
        "/Applications/ChatGPT-copy.app/Contents/Resources/codex",
    ] as [String?])
    func `claimed command cannot replace kernel executable identity`(actualPath: String?) {
        #expect(!ChatGPTCodexProcessTrust.isTrusted(
            123,
            executablePath: { _ in actualPath },
            resolvePath: { $0 },
            processIsTrusted: { _ in
                Issue.record("Unrecognized paths must be rejected before signature inspection")
                return true
            },
            appIsTrusted: { _ in true }))
    }

    @Test(arguments: [false, true], [false, true])
    func `running signature and outer bundle assessment must both succeed`(processTrusted: Bool, bundleTrusted: Bool) {
        let trusted = ChatGPTCodexProcessTrust.isTrusted(
            123,
            executablePath: { _ in Self.nested },
            resolvePath: { $0 },
            processIsTrusted: { _ in processTrusted },
            appIsTrusted: { _ in bundleTrusted })
        #expect(trusted == (processTrusted && bundleTrusted))
    }

    @Test(arguments: [
        "/Users/test/Downloads/codex",
        "/tmp/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        "/Applications/ChatGPT.app/Contents/Resources/other-codex",
    ])
    func `symlink redirects cannot authorize scanning even with trusted signatures`(resolvedPath: String) {
        #expect(!ChatGPTCodexProcessTrust.isTrusted(
            123,
            executablePath: { _ in Self.nested },
            resolvePath: { _ in resolvedPath },
            processIsTrusted: { _ in true },
            appIsTrusted: { _ in true }))
    }

    @Test
    func `untrusted first candidate cannot hide a later trusted app server`() {
        let records = AgentPSOutputParser.parse("""
        123 1 Mon Jul 6 09:03:00 2026 \(Self.nested) app-server
        124 1 Mon Jul 6 09:03:00 2026 /Applications/ChatGPT.app/Contents/Resources/codex app-server
        """)
        #expect(AgentPSOutputParser.hasTrustedChatGPTCodexAppServer(in: records, validator: { $0.pid == 124 }))
    }

    @Test(arguments: ["exec", "app-server-helper", "--help"])
    func `nested executable requires app server argument and cannot bypass trust as a CLI`(argument: String) {
        let records = AgentPSOutputParser.parse("123 1 Mon Jul 6 09:03:00 2026 \(Self.nested) \(argument)")
        #expect(!AgentPSOutputParser.hasTrustedChatGPTCodexAppServer(in: records, validator: { _ in
            Issue.record("Non-server processes must not reach the app-server validator")
            return true
        }))
        #expect(AgentPSOutputParser.agentProcesses(from: records).isEmpty)
    }

    @Test
    func `forged app server command cannot borrow installed ChatGPT identity`() throws {
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["30"]
        try sleeper.run()
        defer {
            sleeper.terminate()
            sleeper.waitUntilExit()
        }
        let records = AgentPSOutputParser.parse(
            "\(sleeper.processIdentifier) 1 Mon Jul 6 09:03:00 2026 \(Self.nested) app-server")
        #expect(!AgentPSOutputParser.hasTrustedChatGPTCodexAppServer(in: records, validator: {
            ChatGPTCodexProcessTrust.isTrusted($0.pid)
        }))
    }
}
