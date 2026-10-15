import AppKit
import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

struct MenuBarExtraMetricPickerTests {
    @Test
    func `metric table offers each provider owned named allowance before fetching`() {
        for descriptor in ProviderDescriptorRegistry.all {
            let labels = MenuBarPercentWindowPreference.available(for: descriptor.id)
                .map { $0.label(for: descriptor.id) }
            for title in descriptor.menuBarMetrics.namedExtras.values {
                #expect(labels.contains(title))
            }
        }
        #expect(!MenuBarPercentWindowPreference.available(for: .codex)
            .map { $0.label(for: .codex) }.contains("Grok Bot"))
    }
}
