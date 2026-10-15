import AppKit

/// Shared AppKit helpers for tests that inspect rendered SwiftUI hosting views.
@MainActor
enum MenuRenderTestSupport {
    static func accessibilityText(_ element: Any, depth: Int = 0) -> String {
        guard depth < 30, let accessible = element as? NSObject else { return "" }
        // SwiftUI nodes implement these public selectors without adopting the full NSAccessibility protocol.
        let fields = [
            #selector(NSAccessibilityProtocol.accessibilityRole),
            #selector(NSAccessibilityProtocol.accessibilityLabel),
            #selector(NSAccessibilityProtocol.accessibilityValue),
            #selector(NSAccessibilityProtocol.accessibilityValueDescription),
            #selector(NSAccessibilityProtocol.accessibilityHelp),
        ].compactMap { selector in
            self.accessibilityProperty(accessible, selector: selector).map { String(describing: $0) }
        }.joined(separator: " | ")
        let children = self.accessibilityProperty(
            accessible, selector: #selector(NSAccessibilityProtocol.accessibilityChildren)) as? [Any] ?? []
        return ([fields] + children.map {
            self.accessibilityText($0, depth: depth + 1)
        }).joined(separator: "\n")
    }

    private static func accessibilityProperty(_ element: NSObject, selector: Selector) -> Any? {
        guard element.responds(to: selector) else { return nil }
        return element.perform(selector)?.takeUnretainedValue()
    }

    static func pngDataWithWindow(hosting: NSView) -> Data? {
        // Native List rows need a window to materialize, but it never needs to be ordered onscreen.
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = hosting.appearance
        window.contentView = hosting
        defer {
            window.contentView = nil
            window.close()
        }
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        return representation.representation(using: .png, properties: [:])
    }
}
