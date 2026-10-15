import CodexBarCore
import Testing
@testable import CodexBar

struct ClaudeSwapMenuPrecedenceTests {
    @Test
    func `multiple Claude swap accounts take precedence by default`() {
        #expect(ClaudeSwapMenuPrecedence.prefersClaudeSwap(
            provider: .claude,
            accountCount: 2,
            showSingleAccount: false))
    }

    @Test
    func `single Claude swap account requires opt in`() {
        #expect(!ClaudeSwapMenuPrecedence.prefersClaudeSwap(
            provider: .claude,
            accountCount: 1,
            showSingleAccount: false))
        #expect(ClaudeSwapMenuPrecedence.prefersClaudeSwap(
            provider: .claude,
            accountCount: 1,
            showSingleAccount: true))
    }
}
