import AppKit
import CodexBarCore
import SwiftUI
import XCTest
@testable import CodexBar

/// Developer tool, skipped by default: renders the per-provider usage selector and the resulting
/// shared provider-card/Overview projection with entirely synthetic data.
///
/// Run with:
///   CODEXBAR_USAGE_ITEMS_SCREENSHOT_DIR=.github/pr-proof \
///     swift test --filter ProviderUsageItemVisibilityScreenshotRenderTests
@MainActor
final class ProviderUsageItemVisibilityScreenshotRenderTests: XCTestCase {
    private static let cardWidth: CGFloat = 360

    private static func metric(
        id: String,
        title: String,
        percent: Double) -> UsageMenuCardView.Model.Metric
    {
        .init(
            id: id,
            title: title,
            percent: percent,
            percentStyle: .used,
            resetText: id == "secondary" ? "Resets Aug 30" : nil,
            detailText: nil,
            detailLeftText: nil,
            detailRightText: nil,
            pacePercent: nil,
            paceOnTop: true)
    }

    private static func pngData(for view: AnyView) -> Data? {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return nil }
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        return representation.representation(using: .png, properties: [:])
    }
}
