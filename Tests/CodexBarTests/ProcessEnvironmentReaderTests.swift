import Foundation
import Testing
@testable import CodexBarCore

struct ProcessEnvironmentReaderTests {
    private static let names: Set<String> = ["HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR"]

    @Test
    func `NUL environment parsing retains only requested names and preserves their exact values`() {
        let expected = [
            "HOME": "/synthetic/home",
            "CODEX_HOME": "/synthetic/codex=work",
            "CLAUDE_CONFIG_DIR": "",
        ]
        let records = expected.keys.sorted().map { "\($0)=\(expected[$0] ?? "")" } + [
            "OPENAI_API_KEY=synthetic-secret",
            "PATH=/synthetic/bin",
        ]
        let data = Data((records.joined(separator: "\0") + "\0").utf8)

        #expect(ProcessEnvironmentReader.parseNULSeparated(data, names: Self.names) == expected)
        #expect(ProcessEnvironmentReader.parseNULSeparated(Data(), names: Self.names) == [:])
        #expect(ProcessEnvironmentReader.parseNULSeparated(Data([0, 0]), names: Self.names) == [:])
        #expect(ProcessEnvironmentReader.parseNULSeparated(Data("PATH=/synthetic/bin\0".utf8), names: Self.names)
            == [:])
        #expect(ProcessEnvironmentReader.parseNULSeparated(
            Data("HOME=/synthetic/home\0HOME=/synthetic/home\0".utf8),
            names: Self.names) == ["HOME": "/synthetic/home"])
    }

    @Test(arguments: [
        "HOME=/synthetic/home",
        "HOME=/synthetic/home\0partial",
        "HOME\0",
        "HOME=/synthetic/home\0HOME=/synthetic/other\0",
    ])
    func `incomplete or conflicting environment records remain unavailable`(_ payload: String) {
        #expect(ProcessEnvironmentReader.parseNULSeparated(Data(payload.utf8), names: Self.names) == nil)
    }

    @Test
    func `invalid UTF8 in a requested value remains unavailable without decoding unrelated values`() {
        let invalidValue = Data("HOME=".utf8) + Data([0xFF, 0])
        #expect(ProcessEnvironmentReader.parseNULSeparated(invalidValue, names: Self.names) == nil)
        let unrelated = Data("UNRELATED=".utf8) + Data([0xFF, 0])
        #expect(ProcessEnvironmentReader.parseNULSeparated(unrelated, names: Self.names) == [:])
    }

    @Test
    func `Linux environment fixtures distinguish empty missing truncated and oversized reads`() throws {
        let procRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProcessEnvironmentReaderTests-\(UUID().uuidString)", isDirectory: true)
        let processRoot = procRoot.appendingPathComponent("101", isDirectory: true)
        try FileManager.default.createDirectory(at: processRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: procRoot) }
        let file = processRoot.appendingPathComponent("environ")

        try Data("CODEX_HOME=/synthetic/codex\0PATH=/synthetic/bin\0".utf8).write(to: file)
        #expect(ProcessEnvironmentReader.readLinuxEnvironment(pid: 101, procRoot: procRoot, names: Self.names) == [
            "CODEX_HOME": "/synthetic/codex",
        ])
        try Data().write(to: file)
        #expect(ProcessEnvironmentReader.readLinuxEnvironment(pid: 101, procRoot: procRoot, names: Self.names) == [:])
        #expect(ProcessEnvironmentReader.readLinuxEnvironment(pid: 102, procRoot: procRoot, names: Self.names) == nil)
        #expect(ProcessEnvironmentReader.readLinuxEnvironment(pid: 0, procRoot: procRoot, names: Self.names) == nil)
        #expect(ProcessEnvironmentReader.readLinuxEnvironment(pid: -1, procRoot: procRoot, names: Self.names) == nil)

        try Data("CODEX_HOME=/synthetic/codex".utf8).write(to: file)
        #expect(ProcessEnvironmentReader.readLinuxEnvironment(pid: 101, procRoot: procRoot, names: Self.names) == nil)

        let valueByteCount = ProcessEnvironmentReader.maxEnvironmentBytes - 6
        let atLimit = Data("HOME=".utf8) + Data(repeating: 120, count: valueByteCount) + Data([0])
        try atLimit.write(to: file)
        let parsed = ProcessEnvironmentReader.readLinuxEnvironment(pid: 101, procRoot: procRoot, names: Self.names)
        #expect(parsed?["HOME"]?.utf8.count == valueByteCount)
        let oversized = atLimit + Data([0])
        try oversized.write(to: file)
        #expect(ProcessEnvironmentReader.readLinuxEnvironment(pid: 101, procRoot: procRoot, names: Self.names) == nil)
        #expect(ProcessEnvironmentReader.parseNULSeparated(oversized, names: Self.names) == nil)
    }
}
