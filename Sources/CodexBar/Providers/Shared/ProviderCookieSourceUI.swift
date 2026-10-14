import CodexBarCore

enum ProviderCookieSourceUI {
    struct Subtitles {
        let auto: String
        let manual: String
        let off: String
    }

    @MainActor
    static func picker(
        id: String,
        context: ProviderSettingsContext,
        source: ReferenceWritableKeyPath<SettingsStore, ProviderCookieSource>,
        allowsOff: Bool,
        subtitles: @escaping () -> Subtitles,
        title: String = "Cookie source",
        subtitle: String? = nil,
        isVisible: (() -> Bool)? = nil,
        onChange: ((String) async -> Void)? = nil,
        trailingText: (() -> String?)? = nil,
        trailingActions: [ProviderSettingsActionDescriptor] = []) -> ProviderSettingsPickerDescriptor
    {
        ProviderSettingsPickerDescriptor(
            id: id,
            title: title,
            subtitle: subtitle ?? subtitles().auto,
            dynamicSubtitle: {
                let text = subtitles()
                return self.subtitle(
                    source: context.settings[keyPath: source],
                    keychainDisabled: context.settings.debugDisableKeychainAccess,
                    auto: text.auto,
                    manual: text.manual,
                    off: text.off)
            },
            binding: context.rawValueBinding(source, fallback: .auto),
            options: self.options(
                allowsOff: allowsOff,
                keychainDisabled: context.settings.debugDisableKeychainAccess),
            isVisible: isVisible,
            onChange: onChange,
            trailingText: trailingText,
            trailingActions: trailingActions)
    }

    static let keychainDisabledAutoNoteKey =
        "Keychain access is disabled, so only Safari and Firefox cookies are imported."

    @MainActor
    static func cachedTrailingText(provider: UsageProvider, scope: CookieHeaderCache.Scope? = nil) -> String? {
        guard let entry = CookieHeaderCache.loadForDisplay(provider: provider, scope: scope) else { return nil }
        return self.cachedTrailingText(entry: entry)
    }

    @MainActor
    static func cachedTrailingText(entry: CookieHeaderCache.Entry) -> String {
        let when = entry.storedAt.relativeDescription()
        return L("Cached: %1$@ • %2$@", entry.sourceLabel, when)
    }

    static func options(allowsOff: Bool, keychainDisabled: Bool) -> [ProviderSettingsPickerOption] {
        var options: [ProviderSettingsPickerOption] = [ProviderSettingsPickerOption(
            id: ProviderCookieSource.auto.rawValue,
            title: ProviderCookieSource.auto.displayName)]
        options.append(ProviderSettingsPickerOption(
            id: ProviderCookieSource.manual.rawValue,
            title: ProviderCookieSource.manual.displayName))
        if allowsOff {
            options.append(ProviderSettingsPickerOption(
                id: ProviderCookieSource.off.rawValue,
                title: ProviderCookieSource.off.displayName))
        }
        return options
    }

    static func subtitle(
        source: ProviderCookieSource,
        keychainDisabled: Bool,
        auto: String,
        manual: String,
        off: String) -> String
    {
        switch source {
        case .auto: keychainDisabled ? "\(auto) \(L(self.keychainDisabledAutoNoteKey))" : auto
        case .manual: manual
        case .off: off
        }
    }
}
