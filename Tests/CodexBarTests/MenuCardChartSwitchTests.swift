import AppKit
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct MenuCardChartSwitchTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func `hosted chart picker reserves its interactive region and changes selection synchronously`() {
        var mode = ProviderMenuChartMode.live
        let binding = Binding(get: { mode }, set: { mode = $0 })
        var rowClicked = false
        let row = MenuRowContainerView(
            payload: MenuCardRowPayload(
                content: AnyView(ProviderMenuChartPicker(selection: binding)
                    .frame(width: 320, height: 44, alignment: .trailing)),
                showsSubmenuIndicator: false,
                submenuIndicatorAlignment: .trailing,
                submenuIndicatorTopPadding: 0,
                allowsMenuHighlight: true,
                containsInteractiveControls: true,
                usesGPUSelection: false,
                onClick: { rowClicked = true }),
            refreshMonitor: nil)
        row.frame = NSRect(x: 0, y: 0, width: 320, height: 51)
        row.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        row.layoutSubtreeIfNeeded()
        let point = NSPoint(x: 280, y: 25)
        #expect(row._test_hitsHostedInteractiveControl(at: point))
        #expect(!row._test_simulateRuntimeClick(at: point))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1)
            else { continue }
            if type == .leftMouseDown { row.mouseDown(with: event) } else { row.mouseUp(with: event) }
        }
        #expect(row._test_forwardedHostedControlEvents.mouseDown)
        #expect(row._test_forwardedHostedControlEvents.mouseUp)
        #expect(!rowClicked)
        binding.wrappedValue = .spend
        #expect(mode == .spend)
    }

    private static func host(
        model: UsageMenuCardView.Model,
        mode: ProviderMenuChartMode,
        highlighted: Bool,
        selected: String? = nil) -> NSHostingView<AnyView>
    {
        let hosting = NSHostingView(rootView: AnyView(UsageMenuCardView(model: model, width: 350)
                .environment(\.providerMenuChartSelection, .constant(mode))
                .environment(\.menuUsageBarSelection, .constant(selected))
                .environment(\.menuItemHighlighted, highlighted)
                .environment(\.colorScheme, .dark)
                .background(highlighted ? MenuHighlightStyle.selectionBackground(true)
                    : Color(nsColor: .windowBackgroundColor))))
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 350, height: 400)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private static func capture(_ hosting: NSHostingView<AnyView>, to url: URL) throws -> CGFloat {
        let height = ceil(hosting.fittingSize.height)
        hosting.frame.size.height = height
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.close() }
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return height
    }
}
