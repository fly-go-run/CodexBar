import Foundation
import Testing
@testable import CodexBarCore

struct AgentProcessBasenameTests {
    @Test(arguments: [
        "", "~", "~/", "~/pi", "~/~", "~/pi/~", "~root", "~root/", "~root/..", "/", "//", "///",
        ".", "..", "./", "../", "~no-such-synthetic-user/..",
        "pi", "./pi", "../bin/pi", "pi/", "pi///", "/usr/local/bin/pi/", "foo/.", "foo/..",
        "a//..", "a//../..", "..//..", "/foo/.", "/foo/..", "~/.", "~/..", "~/pi/..",
        "/Applications/Claude.app/Contents/MacOS/Claude", "Application Support/Claude/claude-code/claude",
        "/path with spaces/omp", "./path with spaces/bun/", "a%2Fb", "a\\b", "a/\u{301}", " pi ",
    ])
    func `string basenames preserve file URL semantics`(path: String) {
        #expect(AgentProcessPath.basename(path) == URL(fileURLWithPath: path).lastPathComponent)
    }

    @Test
    func `ordinary basenames never consult directory context`() {
        var directoryReads = 0
        func directory() -> String {
            directoryReads += 1
            return "/synthetic/omp"
        }
        for index in 0..<2500 {
            #expect(AgentProcessPath.basename(
                "/synthetic/process-\(index)/node/",
                currentDirectory: directory(),
                expandTilde: { _ in directory() }) == "node")
        }
        #expect(directoryReads == 0)
        #expect(AgentProcessPath.basename("", currentDirectory: directory()) == "omp")
        #expect(directoryReads == 1)
        #expect(AgentProcessPath.basename("..", currentDirectory: directory()) == "synthetic")
        #expect(directoryReads == 2)
        #expect(AgentProcessPath.basename("~/", expandTilde: { _ in directory() }) == "omp")
        #expect(directoryReads == 3)
    }

    @Test
    func `both Foundation tilde dialects preserve relative and absolute dot semantics`() {
        let cases = [
            ("~", "~", "home"), ("~/", "home", "home"), ("~root", "~root", "root"),
            ("~root/", "~root", "root"), ("~root/..", "omp", ".."), ("~/pi/..", "..", ".."),
            ("~unknown/..", "omp", "omp"), ("foo/../~", "~", "~"),
        ]
        for (path, modern, legacy) in cases {
            for expandsBareTilde in [false, true] {
                let basename = AgentProcessPath.basename(
                    path,
                    currentDirectory: "/work/omp",
                    expandTilde: { path in
                        if path == "~root" || path.hasPrefix("~root/") {
                            return "/synthetic/root" + path.dropFirst(5)
                        }
                        if path == "~" || path.hasPrefix("~/") {
                            return "/synthetic/home" + path.dropFirst()
                        }
                        return path
                    },
                    expandsBareTilde: expandsBareTilde)
                #expect(basename == (expandsBareTilde ? legacy : modern))
            }
        }
    }

    @Test
    func `parser has no filesystem probing URL constructors`() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexBarCore/AgentSession.swift"),
            encoding: .utf8)
        let start = try #require(source.range(of: "enum AgentProcessPath {"))
        let end = try #require(source.range(of: "public enum LSOFCWDOutputParser {"))
        let parser = String(source[start.lowerBound..<end.lowerBound])
        let hintedProbe = "URL(fileURLWithPath: \"~\", isDirectory: false)"
        #expect(parser.components(separatedBy: hintedProbe).count - 1 == 1)
        #expect(parser.replacingOccurrences(of: hintedProbe, with: "").contains("URL(fileURLWithPath:") == false)
        #expect(!parser.contains("fileExists"))
        #expect(!parser.contains("attributesOfItem"))
        #expect(!parser.contains("lstat("))
        let enumerator = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexBarCore/DarwinProcessEnumerator.swift"),
            encoding: .utf8)
        #expect(enumerator.components(separatedBy: "AgentProcessRecord(").count - 1 == 0)
    }

    @Test
    func `agent selection retains ordering helpers wrappers and app servers`() {
        let commands = [
            "node /opt/pi/index.js", "bun /opt/omp", "pi/", "./omp/", "codex exec", "claude",
            "omp --version", "bun omp --help", "codex app-server", "claude --help",
            "/Applications/Claude.app/Contents/MacOS/Claude",
            "disclaimer /Users/test/Library/Application Support/Claude/claude-code/claude --resume",
            "/Users/test/Library/Application Support/Claude/claude-code/claude --resume",
        ]
        let records = commands.enumerated().map { index, command in
            AgentProcessRecord(pid: Int32(index + 1), ppid: index == 12 ? 12 : 0, startedAt: nil, command: command)
        }
        #expect(AgentPSOutputParser.agentProcesses(from: records).map(\.pid) == [5, 6, 13])
    }
}
