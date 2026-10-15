import AppKit
import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarTestSupport

@MainActor
struct CompactOverviewTests {
    @Test
    func `layout defaults to detailed and unknown values fail back to detailed`() {
        let defaults = InMemoryUserDefaults()
        #expect(Self.settings(defaults).mergedOverviewLayout == .detailed)
        defaults.set("unsupported-layout", forKey: "mergedOverviewLayout")
        #expect(Self.settings(defaults).mergedOverviewLayout == .detailed)
    }

    @Test
    func `compact layout persists independently of icon merging`() {
        let defaults = InMemoryUserDefaults()
        let settings = Self.settings(defaults)
        settings.mergedOverviewLayout = .compact
        settings.mergeIcons = false

        let reloaded = Self.settings(defaults)
        #expect(reloaded.mergedOverviewLayout == .compact)
        #expect(!reloaded.mergeIcons)
        reloaded.mergeIcons = true
        #expect(reloaded.mergedOverviewLayout == .compact)
        reloaded.mergedOverviewLayout = .detailed
        #expect(Self.settings(defaults).mergedOverviewLayout == .detailed)
    }

    private static func height(_ model: UsageMenuCardView.Model, layout: MergedOverviewLayout) -> CGFloat {
        NSHostingController(rootView: OverviewMenuCardRowView(
            model: model, storageText: nil, width: 340, layout: layout))
            .sizeThatFits(in: CGSize(width: 340, height: CGFloat.greatestFiniteMagnitude)).height
    }

    private static func settings(_ defaults: InMemoryUserDefaults) -> SettingsStore {
        ProviderUsageItemVisibilityTests.settings(
            defaults: defaults,
            configStore: testConfigStore(suiteName: "CompactOverviewTests-\(UUID().uuidString)"))
    }
}
