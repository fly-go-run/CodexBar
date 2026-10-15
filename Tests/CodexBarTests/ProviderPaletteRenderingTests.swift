import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarWidget

@MainActor
struct ProviderPaletteRenderingTests {
    private static func color(_ color: ProviderColor) -> Color {
        Color(red: color.red, green: color.green, blue: color.blue)
    }
}
