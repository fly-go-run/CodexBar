import SweetCookieKit
import Testing
@testable import CodexBarCore

struct BrowserCookieOrderStatusStringTests {
    #if os(macOS)
    @Test
    func `codex cookie import order keeps firefox ahead of extra chromium browsers`() {
        let order = ProviderDefaults.metadata[.codex]?.browserCookieOrder ?? Browser.defaultImportOrder
        #expect(Array(order.prefix(3)) == [.safari, .chrome, .firefox])
    }

    @Test
    func `automatic cookie import includes newly supported chromium browsers`() {
        #expect(Browser.defaultImportOrder.contains(.comet))
        #expect(Browser.defaultImportOrder.contains(.yandex))
    }

    @Test
    func `claude cookie import prefers chrome without dropping fallback browsers`() throws {
        let order = try #require(ProviderDefaults.metadata[.claude]?.browserCookieOrder)

        #expect(order.first == .chrome)
        #expect(order.count == Browser.defaultImportOrder.count)
        #expect(Set(order) == Set(Browser.defaultImportOrder))
    }

    @Test
    func `orders listing firefox also include its release channels`() {
        // Channel-owned profiles share `Firefox/Profiles` but only import through their own
        // `Browser` case, so an order that stops at `.firefox` can never reach them.
        let family: Set<Browser> = [.firefox, .firefoxBeta, .firefoxDeveloperEdition, .firefoxNightly]
        let violators = ProviderDefaults.metadata.compactMap { provider, metadata -> UsageProvider? in
            guard let order = metadata.browserCookieOrder, order.contains(where: family.contains) else { return nil }
            return family.isSubset(of: Set(order)) ? nil : provider
        }
        #expect(violators.isEmpty, "orders missing Firefox release channels: \(violators)")
    }
    #endif
}
