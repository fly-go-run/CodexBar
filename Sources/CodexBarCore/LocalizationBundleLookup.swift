import Foundation

/// `.lproj` lookup shared by the app and the widget resource bundles.
public enum LocalizationBundleLookup {
    /// Native SwiftPM builds lowercase language-directory names, including region and script suffixes,
    /// so the exact spelling is tried first and the lowercased one second.
    public static func lprojBundle(named language: String, in resourceBundle: Bundle) -> Bundle? {
        for candidate in [language, language.lowercased()] where !candidate.isEmpty {
            if let path = resourceBundle.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path)
            {
                return bundle
            }
        }
        return nil
    }
}
