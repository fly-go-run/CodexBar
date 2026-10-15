import Foundation
import Testing
@testable import CodexBarCore

struct CodexHomeScopeTests {
    private let home = URL(fileURLWithPath: "/fixture/home", isDirectory: true)

    @Test
    func `ambient home prefers trimmed CODEX_HOME`() {
        let url = CodexHomeScope.ambientHomeURL(env: ["CODEX_HOME": "  /fixture/codex  "], homeDirectory: self.home)
        #expect(url.path == "/fixture/codex")
    }

    @Test(arguments: [nil, "", "   "])
    func `ambient home falls back to dot codex under the home directory`(codexHome: String?) {
        let env = codexHome.map { ["CODEX_HOME": $0] } ?? [:]
        let url = CodexHomeScope.ambientHomeURL(env: env, homeDirectory: self.home)
        #expect(url.path == "/fixture/home/.codex")
    }

    @Test
    func `sessions roots sit under the home`() {
        #expect(CodexHomeScope.sessionsRoot(home: self.home).path == "/fixture/home/sessions")
        #expect(CodexHomeScope.sessionsRoot(homePath: " /fixture/profile ")?.path == "/fixture/profile/sessions")
        #expect(CodexHomeScope.sessionsRoot(homePath: "  ") == nil)
        #expect(CodexHomeScope.sessionsRoot(homePath: nil) == nil)
    }

    @Test
    func `archived sessions sit beside a sessions root only`() {
        let sessions = CodexHomeScope.sessionsRoot(home: self.home)
        #expect(CodexHomeScope.archivedSessionsRoot(sessionsRoot: sessions)?.path == "/fixture/home/archived_sessions")
        let custom = URL(fileURLWithPath: "/fixture/custom-root", isDirectory: true)
        #expect(CodexHomeScope.archivedSessionsRoot(sessionsRoot: custom) == nil)
    }
}
