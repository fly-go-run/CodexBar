import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct MenuCardThroughputTests {
    private static func render(
        _ view: some View,
        width: CGFloat,
        to url: URL) throws
    {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        try self.capture(
            hosting,
            width: width,
            to: url)
    }

    private static func capture(
        _ hosting: NSView,
        width: CGFloat,
        appearance: NSAppearance.Name = .darkAqua,
        to url: URL) throws
    {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        hosting.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: 400)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        defer { window.close() }
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let height = ceil(hosting.fittingSize.height)
        hosting.frame.size = NSSize(
            width: width,
            height: max(30, height))
        window.setContentSize(hosting.frame.size)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(
            in: hosting.bounds,
            to: bitmap)
        try #require(bitmap.representation(
            using: .png,
            properties: [:])).write(to: url)
    }
}

private struct NativeLayoutProofView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context _: Context) -> NSView { self.view }
    func updateNSView(_: NSView, context _: Context) {}
}
