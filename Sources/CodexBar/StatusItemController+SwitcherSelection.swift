import CodexBarCore

extension StatusItemController {
    var shouldMergeIcons: Bool {
        self.settings.mergeIcons && self.store.enabledProvidersForDisplay().count > 1
    }

    func switcherProviderIDs(enabledFirstPartyProviders: [UsageProvider]) -> [ProviderInstanceID] {
        enabledFirstPartyProviders.map(\.instanceID)
    }

    static func resolvedSwitcherProviderID(
        providerIDs: [ProviderInstanceID],
        selectedProviderID: ProviderInstanceID?,
        fallbackProviderID: ProviderInstanceID) -> ProviderInstanceID
    {
        if let selectedProviderID, providerIDs.contains(selectedProviderID) {
            return selectedProviderID
        }
        return providerIDs.contains(fallbackProviderID) ? fallbackProviderID : providerIDs.first ?? fallbackProviderID
    }

    func includesOverviewTab(enabledProviders: [UsageProvider]) -> Bool {
        enabledProviders.count > 1 &&
            !self.settings.resolvedMergedOverviewProviders(
                activeProviders: enabledProviders,
                maxVisibleProviders: SettingsStore.mergedOverviewProviderLimit).isEmpty
    }

    func resolvedSwitcherSelection(
        enabledProviders: [UsageProvider],
        includesOverview: Bool) -> ProviderSwitcherSelection
    {
        if includesOverview, self.settings.mergedMenuLastSelectedWasOverview {
            return .overview
        }
        let providerIDs = self.switcherProviderIDs(enabledFirstPartyProviders: enabledProviders)
        let fallbackProviderID = (self.resolvedMenuProvider(enabledProviders: enabledProviders) ?? .codex).instanceID
        return .provider(Self.resolvedSwitcherProviderID(
            providerIDs: providerIDs,
            selectedProviderID: self.selectedMenuProvider,
            fallbackProviderID: fallbackProviderID))
    }

    func resolvedMergedMenuSelection(enabledProviders: [UsageProvider]) -> ProviderSwitcherSelection? {
        guard self.shouldMergeIcons,
              !self.switcherProviderIDs(enabledFirstPartyProviders: enabledProviders).isEmpty
        else { return nil }
        return self.resolvedSwitcherSelection(
            enabledProviders: enabledProviders,
            includesOverview: self.includesOverviewTab(enabledProviders: enabledProviders))
    }
}
