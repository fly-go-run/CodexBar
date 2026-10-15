import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct MetricTextUpdateLayoutTests {
    enum TextKind: String, CaseIterable {
        case pace
        case detail

        var initialText: String {
            switch self {
            case .pace: "On pace · Lasts until reset"
            case .detail: "100 credits remaining"
            }
        }

        var updatedText: String {
            switch self {
            case .pace: "32% in deficit · Runs out in 1d 11m"
            case .detail: "1234 credits remaining this week"
            }
        }
    }

    private struct RenderedSection {
        let size: CGSize
        let pixels: Data
        let png: Data
    }

    private static func render(
        model: UsageMenuCardView.Model,
        layoutModel: UsageMenuCardView.Model) throws -> RenderedSection
    {
        let view = UsageMenuCardUsageSectionView(
            model: model,
            layoutModel: layoutModel,
            showBottomDivider: false,
            bottomPadding: 6,
            width: 320)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.colorScheme, .light)
            .environment(\.displayScale, 2)
            .background(Color.white)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        let size = hosting.fittingSize
        #expect(size.width == 320)
        #expect(size.height > 0)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        let pixelWidth = Int(ceil(size.width * scale))
        let pixelHeight = Int(ceil(size.height * scale))
        let representation = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixelWidth * 4,
            bitsPerPixel: 32))
        representation.size = size
        let pixels = try #require(representation.bitmapData)
        let byteCount = representation.bytesPerRow * pixelHeight
        pixels.initialize(repeating: 0, count: byteCount)
        let context = try #require(NSGraphicsContext(bitmapImageRep: representation))
        hosting.displayIgnoringOpacity(hosting.bounds, in: context)
        return try RenderedSection(
            size: size,
            pixels: Data(bytes: pixels, count: byteCount),
            png: #require(representation.representation(using: .png, properties: [:])))
    }

    private static func export(_ rendered: RenderedSection, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_FORECAST_LAYOUT_PROOF_DIR"] else { return }
        let directory = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try rendered.png.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }
}
