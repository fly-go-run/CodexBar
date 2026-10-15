import AppKit
import CodexBarCore
import Testing
@testable import CodexBar
@testable import CodexBarTestSupport

@Suite(.serialized)
@MainActor
struct StatusItemBalanceDisplayTests {
    @Test
    func `button title spacing only applies when image is present`() {
        #expect(StatusItemController.buttonTitle("42%", hasImage: true) == " 42%")
        #expect(StatusItemController.buttonTitle("42%", hasImage: false) == "42%")
        #expect(StatusItemController.buttonTitle(nil, hasImage: true).isEmpty)
        #expect(StatusItemController.buttonTitle("", hasImage: true).isEmpty)
    }

    @Test
    func `debug button title stays visible with or without a usage value`() {
        #expect(StatusItemController.buttonTitle(nil, hasImage: true, isDebugApp: true) == " D")
        #expect(StatusItemController.buttonTitle("42%", hasImage: true, isDebugApp: true) == " 42% D")
        #expect(StatusItemController.buttonTitle("42%", hasImage: false, isDebugApp: true) == "42% D")
    }

    @Test
    func `high contrast button title embeds image and metric in attributed content`() throws {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true

        let title = StatusItemController.highContrastButtonTitle(image: image, title: " 42%")

        #expect(title.string == "\u{FFFC} 42%")
        let attachment = try #require(title.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        #expect(attachment.image === image)
        #expect(attachment.bounds.width == 18)
        #expect(attachment.bounds.height == 18)
        #expect(title.attribute(.font, at: 1, effectiveRange: nil) is NSFont)
        #expect(title.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor == .labelColor)
    }

    @Test
    func `debug bundle identity updates status item accessibility`() {
        #expect(StatusItemController.isDebugApp(bundleIdentifier: "com.steipete.codexbar.debug"))
        #expect(!StatusItemController.isDebugApp(bundleIdentifier: "com.steipete.codexbar"))
        #expect(!StatusItemController.isDebugApp(bundleIdentifier: nil))
        #expect(StatusItemController.statusItemAccessibilityTitle(isDebugApp: true) == "CodexBar Debug")
        #expect(StatusItemController.statusItemAccessibilityTitle(isDebugApp: false) == "CodexBar")
    }

    func makeSettings(suiteName: String, provider: UsageProvider) -> SettingsStore {
        let settings = testSettingsStore(suiteName: suiteName, userDefaults: InMemoryUserDefaults())
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = provider.instanceID
        settings.menuBarDisplayMode = .both
        settings.usageBarsShowUsed = true

        let registry = ProviderRegistry.shared
        if let metadata = registry.metadata[provider] {
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: true)
        }
        return settings
    }

    func makeStoreAndController(settings: SettingsStore) -> (UsageStore, StatusItemController) {
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = makeStatusItemControllerForTesting(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            statusBar: testStatusBar())
        return (store, controller)
    }
}

extension StatusItemBalanceDisplayTests {
    @Test
    func `Codex direct layout lanes suppress exhausted windows after reset in status item and preview`() {
        let settings = self.makeSettings(
            suiteName: "StatusItemBalanceDisplayTests-codex-direct-lane-expired",
            provider: .codex)
        let layout = MenuBarLayout(lines: [[.lanePercent(lane: .primary), .lanePercent(lane: .secondary)]])
        let (store, controller) = self.makeStoreAndController(settings: settings)
        defer { controller.releaseStatusItemsForTesting() }
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 100,
                windowMinutes: 300,
                resetsAt: Date(timeIntervalSince1970: 1),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 40,
                windowMinutes: 10080,
                resetsAt: Date().addingTimeInterval(3600),
                resetDescription: nil),
            updatedAt: Date())

        store._setSnapshotForTesting(snapshot, provider: .codex)
        store._setErrorForTesting(nil, provider: .codex)

        let statusItemData = controller.menuBarLayoutRenderData(
            provider: .codex,
            snapshot: snapshot,
            warningFlash: false)
        let previewData = MenuBarLayoutPreview(
            layout: layout,
            provider: .codex,
            settings: settings,
            store: store)
            .liveData(provider: .codex, snapshot: snapshot)

        for data in [statusItemData, previewData] {
            #expect(data.primary == nil)
            #expect(data.secondary?.usedPercent == 40)
        }
    }

    @Test
    func `Codex direct primary lane preserves binding weekly cap in status item and preview`() throws {
        let settings = self.makeSettings(
            suiteName: "StatusItemBalanceDisplayTests-codex-direct-lane-cap",
            provider: .codex)
        let layout = MenuBarLayout(lines: [[.lanePercent(lane: .primary)]])
        let (store, controller) = self.makeStoreAndController(settings: settings)
        defer { controller.releaseStatusItemsForTesting() }
        let now = Date()
        let weeklyReset = now.addingTimeInterval(4 * 24 * 3600)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 1,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(3 * 3600),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 100,
                windowMinutes: 10080,
                resetsAt: weeklyReset,
                resetDescription: nil),
            updatedAt: now)

        store._setSnapshotForTesting(snapshot, provider: .codex)
        store._setErrorForTesting(nil, provider: .codex)

        let statusItemData = controller.menuBarLayoutRenderData(
            provider: .codex,
            snapshot: snapshot,
            warningFlash: false,
            now: now)
        let previewData = MenuBarLayoutPreview(
            layout: layout,
            provider: .codex,
            settings: settings,
            store: store)
            .liveData(provider: .codex, snapshot: snapshot)

        for data in [statusItemData, previewData] {
            let primary = try #require(data.primary)
            #expect(primary.usedPercent == 100)
            #expect(primary.resetsAt == weeklyReset)
        }
    }
}

extension StatusItemBalanceDisplayTests {}
