import Commander
import Foundation
import SweetCookieKit
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

@Suite(.serialized, ProviderTransportRegressionFixtures())
struct CLICookieRefreshTests {
    @Test
    func `cookie refresh parses explicit keychain acknowledgement`() throws {
        let parser = CommandParser(signature: CommandSignature.describe(CookieOptions()))
        let parsed = try parser.parse(arguments: [
            "--provider", "opencodego", "--allow-keychain-prompt", "--json",
        ])

        #expect(parsed.options["provider"] == ["opencodego"])
        #expect(parsed.flags.contains("allowKeychainPrompt"))
        #expect(parsed.flags.contains("jsonShortcut"))
    }
}
