import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct FrontmostProviderMonitorTests {
    @Test
    func `monitor only runs while frontmost source can affect the collapsed merged icon`() {
        #expect(FrontmostProviderMonitoringPolicy.shouldRun(
            source: .frontmostApp, mergeIcons: true, isStacked: false))
        for source in [UnifiedIconSource.currentSelection, .highestUsage] {
            #expect(!FrontmostProviderMonitoringPolicy.shouldRun(
                source: source, mergeIcons: true, isStacked: false))
        }
        #expect(!FrontmostProviderMonitoringPolicy.shouldRun(
            source: .frontmostApp, mergeIcons: false, isStacked: false))
        #expect(!FrontmostProviderMonitoringPolicy.shouldRun(
            source: .frontmostApp, mergeIcons: true, isStacked: true))
    }

    @Test
    func `presentation changes unregister and reseed the focus observer`() {
        let source = FakeFrontmostApplicationEventSource(bundleIdentifier: "com.openai.codex")
        var changes: [UsageProvider?] = []
        let monitor = FrontmostProviderMonitor(
            source: source,
            enabledProviders: { [.codex, .claude] },
            onChange: { changes.append($0) })

        func synchronize(_ iconSource: UnifiedIconSource, mergeIcons: Bool, isStacked: Bool) {
            monitor.synchronize(shouldRun: FrontmostProviderMonitoringPolicy.shouldRun(
                source: iconSource, mergeIcons: mergeIcons, isStacked: isStacked))
        }

        synchronize(.frontmostApp, mergeIcons: true, isStacked: false)
        #expect(source.startCount == 1)
        #expect(monitor.currentProvider == .codex)

        synchronize(.frontmostApp, mergeIcons: false, isStacked: false)
        #expect(source.stopCount == 1)
        #expect(!monitor.isRunning)
        source.activate("com.anthropic.claudefordesktop")
        #expect(changes == [.codex, nil])

        synchronize(.frontmostApp, mergeIcons: true, isStacked: false)
        #expect(source.startCount == 2)
        #expect(monitor.currentProvider == .claude)

        synchronize(.frontmostApp, mergeIcons: true, isStacked: true)
        #expect(source.stopCount == 2)
        synchronize(.currentSelection, mergeIcons: true, isStacked: false)
        #expect(source.startCount == 2)

        synchronize(.frontmostApp, mergeIcons: true, isStacked: false)
        #expect(source.startCount == 3)
        #expect(monitor.currentProvider == .claude)
        monitor.stop()
        #expect(source.stopCount == 3)
    }

    @Test
    func `monitor seeds coalesces refreshes and unregisters on stop`() {
        let source = FakeFrontmostApplicationEventSource(bundleIdentifier: "com.openai.codex")
        var enabled: Set<UsageProvider> = [.codex, .claude]
        var changes: [UsageProvider?] = []
        let monitor = FrontmostProviderMonitor(
            source: source,
            enabledProviders: { enabled },
            onChange: { changes.append($0) })

        monitor.synchronize(shouldRun: true)
        #expect(source.startCount == 1)
        #expect(monitor.currentProvider == .codex)
        #expect(changes == [.codex])

        source.activate("com.openai.codex")
        monitor.synchronize(shouldRun: true)
        #expect(source.startCount == 1)
        #expect(changes == [.codex])

        source.activate("com.anthropic.claudefordesktop")
        #expect(changes == [.codex, .claude])
        source.activate("com.apple.Safari")
        #expect(changes == [.codex, .claude, nil])
        source.activate("com.openai.codex")
        enabled.remove(.codex)
        monitor.refresh()
        #expect(changes == [.codex, .claude, nil, .codex, nil])

        monitor.stop()
        #expect(source.stopCount == 1)
        #expect(!monitor.isRunning)
        source.activate("com.anthropic.claudefordesktop")
        #expect(changes == [.codex, .claude, nil, .codex, nil])
    }

    @Test
    func `termination falls back and a new activation restores the match`() {
        let source = FakeFrontmostApplicationEventSource(bundleIdentifier: "com.openai.codex")
        var changes: [UsageProvider?] = []
        let monitor = FrontmostProviderMonitor(
            source: source,
            enabledProviders: { [.codex, .claude] },
            onChange: { changes.append($0) })

        monitor.synchronize(shouldRun: true)
        source.terminateFrontmost()
        source.activate("com.anthropic.claudefordesktop")

        #expect(changes == [.codex, nil, .claude])
        monitor.stop()
        #expect(changes == [.codex, nil, .claude, nil])
    }
}

@MainActor
private final class FakeFrontmostApplicationEventSource: FrontmostApplicationEventSource {
    var frontmostBundleIdentifier: String?
    var startCount = 0
    var stopCount = 0
    private var onChange: (@MainActor () -> Void)?

    init(bundleIdentifier: String?) {
        self.frontmostBundleIdentifier = bundleIdentifier
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        self.startCount += 1
        self.onChange = onChange
    }

    func stop() {
        self.stopCount += 1
        self.onChange = nil
    }

    func activate(_ bundleIdentifier: String?) {
        self.frontmostBundleIdentifier = bundleIdentifier
        self.onChange?()
    }

    func terminateFrontmost() {
        self.activate(nil)
    }
}
