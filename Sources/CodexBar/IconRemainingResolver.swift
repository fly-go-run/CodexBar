import CodexBarCore
import Foundation

enum IconRemainingResolver {
    static func resolvedWindows(
        snapshot: UsageSnapshot,
        style: IconStyle,
        secondaryOverrideWindowID: String? = nil,
        now: Date = Date())
        -> (primary: RateWindow?, secondary: RateWindow?)
    {
        guard let provider = UsageProvider(rawValue: style.rawValue) else {
            return (primary: snapshot.primary, secondary: snapshot.secondary)
        }
        let windows = ProviderDescriptorRegistry.descriptor(for: provider).presentation.iconWindows(
            context: ProviderIconWindowContext(
                snapshot: snapshot,
                secondaryOverrideWindowID: secondaryOverrideWindowID,
                now: now))
        return (primary: windows.primary, secondary: windows.secondary)
    }

    static func resolvedPercents(
        snapshot: UsageSnapshot,
        style: IconStyle,
        showUsed: Bool,
        secondaryOverrideWindowID: String? = nil,
        now: Date = Date())
        -> (primary: Double?, secondary: Double?)
    {
        let windows = Self.resolvedWindows(
            snapshot: snapshot,
            style: style,
            secondaryOverrideWindowID: secondaryOverrideWindowID,
            now: now)
        return (
            primary: showUsed ? windows.primary?.usedPercent : windows.primary?.remainingPercent,
            secondary: showUsed ? windows.secondary?.usedPercent : windows.secondary?.remainingPercent)
    }
}
