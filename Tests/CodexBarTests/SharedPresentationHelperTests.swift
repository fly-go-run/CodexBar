import Foundation
import Testing
@testable import CodexBarCore

struct SharedPresentationHelperTests {
    @Test
    func `relative luminance follows the sRGB curve`() {
        #expect(ProviderColor(red: 0, green: 0, blue: 0).relativeLuminance == 0)
        #expect(abs(ProviderColor(red: 1, green: 1, blue: 1).relativeLuminance - 1) < 1e-12)
        #expect(abs(ProviderColor(red: 0.5, green: 0.5, blue: 0.5).relativeLuminance - 0.214_041) < 1e-6)
        #expect(abs(ProviderColor(red: 0.02, green: 0.02, blue: 0.02).relativeLuminance - 0.02 / 12.92) < 1e-12)
        #expect(ProviderColor(red: 2, green: -1, blue: 0).relativeLuminance
            == ProviderColor(red: 1, green: 0, blue: 0).relativeLuminance)
    }

    @Test
    func `lproj lookup tries the exact then lowercased language`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lproj-lookup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["en.lproj", "zz-yy.lproj"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true)
        }
        let resources = try #require(Bundle(path: root.path))

        let english = LocalizationBundleLookup.lprojBundle(named: "en", in: resources)
        #expect(english?.bundleURL.lastPathComponent == "en.lproj")
        let lowered = LocalizationBundleLookup.lprojBundle(named: "ZZ-YY", in: resources)
        #expect(lowered?.bundleURL.lastPathComponent.lowercased() == "zz-yy.lproj")
        #expect(LocalizationBundleLookup.lprojBundle(named: "fr", in: resources) == nil)
        #expect(LocalizationBundleLookup.lprojBundle(named: "", in: resources) == nil)
    }
}

struct StringTrimmingTests {
    @Test
    func `trimmed non empty strips whitespace and drops blanks`() {
        #expect(" value \n".trimmedNonEmpty == "value")
        #expect("value".trimmedNonEmpty == "value")
        #expect(" \t\n".trimmedNonEmpty == nil)
        #expect("".trimmedNonEmpty == nil)
        let missing: String? = nil
        #expect(missing.trimmedNonEmpty == nil)
        let present: String? = "  inner  "
        #expect(present.trimmedNonEmpty == "inner")
    }
}
