import Commander
import Testing
@testable import CodexBarCLI

struct CLICommonOptionsTests {
    private static let paths = [
        ["cache", "clear"], ["cost"], ["config", "validate"], ["config", "dump"],
        ["config", "providers"], ["config", "enable"], ["config", "disable"], ["config", "set-api-key"],
    ]

    @Test(arguments: Self.paths)
    func `common flags survive real command resolution`(path: [String]) throws {
        let program = Program(descriptors: CodexBarCLI.commandDescriptors())
        let parsed = try program.resolve(argv: path + [
            "-v", "--json-output", "--log-level", "debug", "--format", "json", "--json", "--json-only", "--pretty",
        ]).parsedValues
        #expect(parsed.flags == ["verbose", "jsonOutput", "jsonShortcut", "jsonOnly", "pretty"])
        #expect(parsed.options == ["logLevel": ["debug"], "format": ["json"]])
        #expect(CLIOutputPreferences.from(values: parsed).format == .json)
        #expect(CLIOutputPreferences.from(values: parsed).pretty)

        let defaults = try program.resolve(argv: path).parsedValues
        #expect(defaults.flags.isEmpty)
        #expect(defaults.options.isEmpty)
        #expect(CLIOutputPreferences.from(values: defaults).format == .text)
        #expect(!CLIOutputPreferences.from(values: defaults).pretty)
        let logs = try program.resolve(argv: path + ["--json-output", "--verbose"]).parsedValues
        #expect(logs.flags == ["jsonOutput", "verbose"])
        #expect(CLIOutputPreferences.from(values: logs).format == .text)
    }
}

extension CLICommonOptionsTests {
    @Test(arguments: ["usage", "cards"])
    func `shared fetch flags retain labels and command specific options`(command: String) throws {
        let program = Program(descriptors: CodexBarCLI.commandDescriptors())
        let invocation = try program.resolve(argv: [
            command, "--provider", "codex", "--account", "fixture", "--account-index", "2", "--all-accounts",
            "--source", "api", "--web-timeout", "12", "--no-credits", "--no-color", "--status", "--web",
            "--web-debug-dump-html", "--log-level", "info", "-v",
        ])
        #expect(invocation.descriptor.signature.optionGroups.isEmpty)
        #expect(invocation.parsedValues.options == [
            "provider": ["codex"], "account": ["fixture"], "accountIndex": ["2"],
            "source": ["api"], "webTimeout": ["12"], "logLevel": ["info"],
        ])
        #expect(invocation.parsedValues.flags == [
            "allAccounts", "noCredits", "noColor", "status", "web", "webDebugDumpHtml", "verbose",
        ])
        let ownFlag = command == "usage" ? "--app-auto-verifier" : "--brief"
        let otherFlag = command == "usage" ? "--brief" : "--app-auto-verifier"
        #expect(try program.resolve(argv: [command, ownFlag]).parsedValues.flags.count == 1)
        #expect(throws: CommanderProgramError.self) {
            try program.resolve(argv: [command, otherFlag])
        }
    }

    @Test(arguments: [["hooks", "test", "quota_reached"], ["hooks", "watch"]])
    func `hooks output groups retain their own help and flags`(path: [String]) throws {
        let invocation = try Program(descriptors: CodexBarCLI.commandDescriptors()).resolve(argv: path + [
            "--format", "json", "--json", "--json-only", "--pretty",
        ])
        #expect(invocation.parsedValues.options == ["format": ["json"]])
        #expect(invocation.parsedValues.flags == ["jsonShortcut", "jsonOnly", "pretty"])
        #expect(invocation.descriptor.signature.optionGroups.isEmpty)
        #expect(invocation.descriptor.signature.flags.first { $0.label == "jsonShortcut" }?.help == "Emit JSON")
        #expect(invocation.parsedValues.positional == (path[1] == "test" ? ["quota_reached"] : []))
    }
}
