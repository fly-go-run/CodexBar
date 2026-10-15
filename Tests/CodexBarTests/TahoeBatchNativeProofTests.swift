import AppKit
import XCTest
@testable import CodexBar
@testable import CodexBarCore

@MainActor
final class TahoeBatchNativeProofTests: XCTestCase {
    private static func serverReceipt(_ server: MenuBarStatusItemWindowSnapshot) -> [String: Any] {
        [
            "name": server.name, "owner": server.ownerName,
            "bounds": NSStringFromRect(server.bounds),
            "displayBounds": server.displayBounds.map(NSStringFromRect) ?? "none",
            "coordinateSystem": "Quartz screen, top-left origin",
            "onscreen": server.isOnscreen, "withinDisplay": server.isWithinDisplayBounds,
        ]
    }

    private static func advanceAutomaticProof(
        _ state: TahoeBatchMenuState,
        receipt: [String: Any],
        button: NSButton,
        output: URL)
    {
        state.ticks += 1
        guard state.ticks.isMultiple(of: 4), state.phase < 4 else { return }
        try? JSONSerialization.data(withJSONObject: receipt).write(
            to: output.appendingPathComponent("phase-\(state.phase).json"), options: .atomic)
        state.phase += 1
        switch state.phase {
        case 1: _ = (state.menu.items.first?.view as? ProviderSwitcherView)?.handleKeyboardSelection(at: 1)
        case 2: _ = (state.menu.items.first?.view as? ProviderSwitcherView)?.handleKeyboardSelection(at: 2)
        case 3:
            state.menu.cancelTracking()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { button.performClick(nil) }
        default:
            state.menu.cancelTracking()
            try? Data().write(to: output.appendingPathComponent("done"))
        }
    }

    private static func tables(_ view: NSView) -> [String] {
        let own = view is NSTableView ? [NSStringFromRect(view.frame)] : []
        return own + view.subviews.flatMap(self.tables)
    }
}

@MainActor
private final class TahoeBatchMenuButton: NSButton {
    var menuToOpen: NSMenu?
    @objc func openMenu() {
        self.menuToOpen?.popUp(
            positioning: nil,
            at: NSPoint(
                x: 0,
                y: self.bounds.maxY),
            in: self)
    }
}

@MainActor
private final class TahoeBatchMenuState {
    let menu: NSMenu
    var previousCommand = ""
    var phase = 0
    var ticks = 0
    init(menu: NSMenu) {
        self.menu = menu
    }
}
