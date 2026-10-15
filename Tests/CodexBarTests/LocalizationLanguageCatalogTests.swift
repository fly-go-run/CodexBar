import Foundation
import Testing
@testable import CodexBar

struct LocalizationLanguageCatalogTests {
    @Test
    func `language picker labels use stable native names`() {
        let expected: [AppLanguage: String] = [
            .system: "System",
            .english: "English",
            .chineseSimplified: "简体中文",
            .chineseTraditional: "繁體中文",
            .japanese: "日本語",
            .spanish: "Español",
            .portugueseBrazilian: "Português (Brasil)",
            .korean: "한국어",
            .german: "Deutsch",
            .french: "Français",
            .arabic: "العربية",
            .italian: "Italiano",
            .vietnamese: "Tiếng Việt",
            .dutch: "Nederlands",
            .turkish: "Türkçe",
            .ukrainian: "Українська",
            .russian: "Русский",
            .indonesian: "Bahasa Indonesia",
            .polish: "Polski",
            .persian: "فارسی",
            .thai: "ไทย",
            .galician: "Galego",
            .catalan: "Català",
            .swedish: "Svenska",
        ]

        #expect(expected.count == AppLanguage.allCases.count)

        let japaneseLabels = CodexBarLocalizationOverride.$appLanguage.withValue("ja") {
            Dictionary(uniqueKeysWithValues: AppLanguage.allCases.map { ($0, $0.label) })
        }
        let arabicLabels = CodexBarLocalizationOverride.$appLanguage.withValue("ar") {
            Dictionary(uniqueKeysWithValues: AppLanguage.allCases.map { ($0, $0.label) })
        }

        #expect(japaneseLabels == expected)
        #expect(arabicLabels == expected)
    }

    @Test
    func `system language preserves an external Apple Languages override`() {
        Self.withTemporaryDefaults(for: #function) { defaults, _ in
            defaults.set(["de"], forKey: "AppleLanguages")

            AppLanguagePreferenceMigration.clearLegacyOverrideIfOwned(
                storedAppLanguage: "",
                defaults: defaults)

            #expect(defaults.stringArray(forKey: "AppleLanguages") == ["de"])
        }
    }

    @Test
    func `matching legacy language override is cleared`() {
        Self.withTemporaryDefaults(for: #function) { defaults, suiteName in
            defaults.set(["ja"], forKey: "AppleLanguages")

            AppLanguagePreferenceMigration.clearLegacyOverrideIfOwned(
                storedAppLanguage: "ja",
                defaults: defaults)

            #expect(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] == nil)
        }
    }

    @Test
    func `unrelated external language override is preserved`() {
        Self.withTemporaryDefaults(for: #function) { defaults, _ in
            defaults.set(["de"], forKey: "AppleLanguages")

            AppLanguagePreferenceMigration.clearLegacyOverrideIfOwned(
                storedAppLanguage: "ja",
                defaults: defaults)

            #expect(defaults.stringArray(forKey: "AppleLanguages") == ["de"])
        }
    }

    private static func withTemporaryDefaults(
        for testName: String,
        _ body: (UserDefaults, String) -> Void)
    {
        let suiteName = "LocalizationLanguageCatalogTests.\(testName).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults, suiteName)
    }
}
