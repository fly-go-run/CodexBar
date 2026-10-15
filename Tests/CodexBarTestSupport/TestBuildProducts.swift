// SwiftBuild also compiles this test-support target for `swift build -c release`,
// where CodexBarCore is not built for testing.
#if DEBUG
import Foundation

enum TestBuildProducts {
    static func executableURL(named name: String) -> URL {
        // Scratch and release builds must launch their own products, not stale checkout helpers.
        Bundle(for: TestBundleMarker.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(name)
    }
}

private final class TestBundleMarker: NSObject {}
#endif
