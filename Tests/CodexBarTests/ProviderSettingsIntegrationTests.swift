import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct ProviderSettingsIntegrationTests {
    @Test
    func `settings links resolve their destination only when clicked`() async {
        var resolutions = 0
        let destination: () -> URL? = {
            resolutions += 1
            return nil
        }
        let action = ProviderSettingsActionDescriptor.openURL(id: "fixture", title: "Fixture", url: destination())
        #expect(resolutions == 0)
        await action.perform()
        #expect(resolutions == 1)
    }
}
