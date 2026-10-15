import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ProviderSessionStoreFileTests {
    private static func cookie(value: String, expires: Date = Date(timeIntervalSinceNow: 3600)) throws -> HTTPCookie {
        try #require(HTTPCookie(properties: [
            .name: "fixture", .value: value, .domain: "session.test", .path: "/", .expires: expires, .secure: true,
        ]))
    }
}
