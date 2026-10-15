import Foundation
import Testing
@testable import CodexBar

struct MenuBarResetTokenPersistenceTests {
    @Test
    func `historical reset JSON keeps automatic semantics and spelling`() throws {
        let fixtures: [(String, MenuBarLayoutToken, Bool)] = [
            (#"{"resetCountdown":{}}"#, .resetCountdown, false),
            (#"{"resetAbsolute":{}}"#, .resetAbsolute, true),
        ]
        for (json, expected, absolute) in fixtures {
            let token = try JSONDecoder().decode(MenuBarLayoutToken.self, from: Data(json.utf8))
            #expect(token == expected)
            #expect(token.resetWindow == .automatic)
            #expect(token.resetIsAbsolute == absolute)
            #expect(try String(bytes: JSONEncoder().encode(token), encoding: .utf8) == json)
        }
        #expect(MenuBarLayoutToken.icon.resetWindow == nil)
    }

    @Test(arguments: PercentWindow.allCases)
    func `selected reset windows round trip without changing automatic tokens`(window: PercentWindow) throws {
        let layout = MenuBarLayout(lines: [[
            .resetCountdown,
            .windowResetCountdown(window: window),
            .resetAbsolute,
            .windowResetAbsolute(window: window),
        ]])
        let encoded = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(MenuBarLayout.self, from: encoded)
        #expect(decoded == layout)
        #expect(decoded.lines[0][1].resetWindow == window)
        #expect(!decoded.lines[0][1].resetIsAbsolute)
        #expect(decoded.lines[0][3].resetWindow == window)
        #expect(decoded.lines[0][3].resetIsAbsolute)
    }
}
