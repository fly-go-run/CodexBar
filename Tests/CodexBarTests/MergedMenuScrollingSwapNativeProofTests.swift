import AppKit
import XCTest
@testable import CodexBar
@testable import CodexBarCore

/// Native proof for #3549: merged-menu tab swaps between cards of different heights.
///
/// Opens the production merged menu with six synthetic providers whose cards deliberately differ in height (Overview
/// also exceeds the screen and scrolls), then switches tabs from a common-modes timer while the menu tracks. AppKit's
/// table-backed menu keeps a reused row's measured height, so an in-place payload swap into a row of another height
/// left empty space or clipped cards. Each phase records menu, table and row geometry with item identity, asserts
/// that no row keeps a stale height, and captures the menu window. Opt-in via `CODEXBAR_MENU_SWAP_PROOF_DIR`;
/// `CODEXBAR_MENU_SWAP_COST=1` adds cost sections and `CODEXBAR_MENU_SWAP_POPUP=1` opens from a window popUp instead of
/// the status item.
/// Synthetic accounts only; no provider transport, credential or Keychain access.
@MainActor
final class MergedMenuScrollingSwapNativeProofTests: XCTestCase {
    // MARK: - Fixture

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Geometry

    static func phaseReceipt(menu: NSMenu, label: String, settings: SettingsStore) -> [String: Any] {
        let anyView = menu.items.lazy.compactMap(\.view).first { $0.window != nil }
        let window = anyView?.window
        var receipt: [String: Any] = [
            "phase": label,
            "selectedProvider": settings.selectedMenuProvider?.rawValue ?? "none",
            "overviewSelected": settings.mergedMenuLastSelectedWasOverview,
            "items": menu.numberOfItems,
            "menuSize": NSStringFromSize(menu.size),
            "window": window.map { NSStringFromRect($0.frame) } ?? "none",
        ]
        guard let anyView else { return receipt }
        var chain: [String] = []
        var representation: NSView?
        var clip: NSView?
        var node: NSView? = anyView.superview
        while let current = node {
            let name = String(describing: type(of: current))
            chain.append("\(name) \(NSStringFromRect(current.frame)) bounds=\(NSStringFromRect(current.bounds))")
            if representation == nil, name.contains("MenuRepresentation") { representation = current }
            if clip == nil, current is NSClipView { clip = current }
            node = current.superview
        }
        receipt["ancestorChain"] = chain
        receipt["menuItems"] = menu.items.enumerated().compactMap { index, item -> [String: Any]? in
            guard let view = item.view else { return nil }
            var rowFrame = "none"
            var node: NSView? = view.superview
            while let current = node {
                if current is NSTableRowView {
                    rowFrame = NSStringFromRect(current.frame)
                    break
                }
                node = current.superview
            }
            return [
                "index": index,
                "itemObject": String(UInt(bitPattern: ObjectIdentifier(item).hashValue), radix: 16),
                "viewObject": String(UInt(bitPattern: ObjectIdentifier(view).hashValue), radix: 16),
                "id": (item.representedObject as? String) ?? item.title,
                "view": String(describing: type(of: view)),
                "isCard": view is ErasedMenuCardHostingView,
                "viewFrame": NSStringFromRect(view.frame),
                "intrinsic": NSStringFromSize(view.intrinsicContentSize),
                "fitting": NSStringFromSize(view.fittingSize),
                "row": rowFrame,
            ]
        }
        receipt["tableHeight"] = representation.map { Double($0.frame.height) } ?? -1
        receipt["clipHeight"] = clip.map { Double($0.frame.height) } ?? -1
        receipt["clipOffsetY"] = clip.map { Double($0.bounds.minY) } ?? -1
        if let representation {
            let rows = representation.subviews.sorted { $0.frame.minY < $1.frame.minY }
            receipt["rowCount"] = rows.count
            receipt["rowHeightSum"] = Double(rows.reduce(0) { $0 + $1.frame.height })
            receipt["rows"] = rows.map { row -> [String: Any] in
                let content = Self.deepestCustomView(in: row)
                var entry: [String: Any] = [
                    "class": String(describing: type(of: row)),
                    "frame": NSStringFromRect(row.frame),
                ]
                if let content {
                    entry["content"] = String(describing: type(of: content))
                    entry["contentFrame"] = NSStringFromRect(content.frame)
                    entry["contentFitting"] = NSStringFromSize(content.fittingSize)
                    entry["contentIntrinsic"] = NSStringFromSize(content.intrinsicContentSize)
                    entry["rowMinusContentHeight"] = Double(row.frame.height - content.frame.height)
                }
                return entry
            }
        }
        return receipt
    }

    /// The menu item's own view inside a custom row (skipping AppKit's wrapper views).
    private static func deepestCustomView(in row: NSView) -> NSView? {
        var queue = row.subviews
        while !queue.isEmpty {
            let view = queue.removeFirst()
            let name = String(describing: type(of: view))
            if !name.hasPrefix("NS") || name.contains("Hosting") { return view }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    static func capture(menu: NSMenu, to url: URL) {
        guard let window = menu.items.lazy.compactMap({ $0.view?.window }).first else { return }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try? capture.run()
        capture.waitUntilExit()
        if capture.terminationStatus != 0 {
            let note = "screencapture exit \(capture.terminationStatus) window \(window.windowNumber) " +
                "frame \(NSStringFromRect(window.frame))"
            try? note.write(to: url.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        }
    }
}

/// Runs the swap script from inside the menu's tracking run loop, recording each phase after it settles.
@MainActor
private final class MergedMenuSwapDriver {
    /// (label, switcher segment title to select before recording; nil records the initial state)
    static let script: [(String, String?)] = [
        ("01-codex-open", nil),
        ("02-overview", "Overview"),
        ("03-claude", "Claude"),
        ("04-overview-again", "Overview"),
        ("05-codex-again", "Codex"),
        ("06-copilot", "Copilot"),
        ("07-zai", "z.ai / GLM"),
        ("08-claude-again", "Claude"),
        ("09-cursor", "Cursor"),
        ("10-overview-final", "Overview"),
        ("11-copilot-final", "Copilot"),
    ]
    private static let settleTicks = 6

    private let menu: NSMenu
    private let output: URL
    private let settings: SettingsStore
    private var ticks = 0
    private var step = 0
    private(set) var phases: [[String: Any]] = []

    init(menu: NSMenu, output: URL, settings: SettingsStore) {
        self.menu = menu
        self.output = output
        self.settings = settings
    }

    func tick() {
        self.ticks += 1
        guard self.ticks.isMultiple(of: Self.settleTicks) else { return }
        guard self.step < Self.script.count else {
            self.menu.cancelTracking()
            return
        }
        let (label, _) = Self.script[self.step]
        self.phases.append(MergedMenuScrollingSwapNativeProofTests.phaseReceipt(
            menu: self.menu, label: label, settings: self.settings))
        MergedMenuScrollingSwapNativeProofTests.capture(
            menu: self.menu, to: self.output.appendingPathComponent("\(label).png"))
        self.step += 1
        guard self.step < Self.script.count, let title = Self.script[self.step].1 else { return }
        guard let switcher = self.menu.items.lazy.compactMap({ $0.view as? ProviderSwitcherView }).first,
              let index = switcher._test_segmentTitles().firstIndex(of: title)
        else {
            self.phases.append(["error": "segment \(title) not found"])
            return
        }
        _ = switcher.handleKeyboardSelection(at: index)
    }
}
