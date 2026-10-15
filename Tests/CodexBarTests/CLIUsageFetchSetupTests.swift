import CodexBarCore
import Commander
import Testing
@testable import CodexBarCLI

struct CLIUsageFetchSetupTests {
    @Test(arguments: ["usage", "cards"])
    func `shared validation keeps error precedence`(name: String) throws {
        let cases: [([String], String)] = [
            (["--source", "invalid", "--web-timeout", "invalid"], "--source must be auto|web|cli|oauth|api."),
            (
                ["--web-timeout", "nan", "--account-index", "0"],
                "--web-timeout must be a finite, nonnegative number within the supported range."),
            (["--account-index", "0", "--all-accounts"], "--account-index must be a positive integer."),
            (
                ["--account", "fixture", "--all-accounts"],
                "--all-accounts cannot be combined with --account or --account-index."),
        ]
        for (arguments, expected) in cases {
            do {
                _ = try Self.decode(name, arguments: arguments)
                Issue.record("Expected argument failure")
            } catch let error as CLIArgumentError {
                #expect(error.message == expected)
            }
        }
        #expect(throws: CLIArgumentError.self) {
            try Self.decode(name, arguments: ["--all-accounts"], providers: [.codex, .claude])
        }
        let all = try Self.decode(name, arguments: ["--all-accounts"])
        #expect(all.command.includeAllCodexAccounts)
    }

    @Test
    func `usage retains JSON credits and verifier policy`() throws {
        let json = try Self.decode("usage", arguments: ["--json", "--no-credits", "--json-only"])
        #expect(json.command.format == .json)
        #expect(json.command.includeCredits)
        #expect(json.command.jsonOnly)
        #expect(!json.command.useColor)
        let verifier = try Self.decode(
            "usage", arguments: ["--app-auto-verifier", "--source", "auto"], providers: [.claude])
        #expect(verifier.command.providerRuntime == .app)
        #expect(throws: CLIArgumentError.self) {
            try Self.decode("usage", arguments: ["--app-auto-verifier", "--source", "auto"])
        }
        #expect(throws: CLIArgumentError.self) {
            try Self.decode("usage", arguments: ["--app-auto-verifier", "--account", "fixture"], providers: [.claude])
        }
    }

    private static func decode(
        _ name: String,
        arguments: [String],
        providers: [UsageProvider] = [.codex]) throws -> CLIUsageFetchSetup
    {
        let values = try Program(descriptors: CodexBarCLI.commandDescriptors())
            .resolve(argv: [name] + arguments).parsedValues
        return try CLIUsageFetchSetup(
            values: values,
            providers: providers,
            output: CLIOutputPreferences.from(values: values, allowsToon: name == "usage"),
            cardsLayout: name == "cards")
    }
}
