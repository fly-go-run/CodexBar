import Foundation

public struct ProviderRateWindowLabels: Sendable, Equatable {
    public let primary: String
    public let secondary: String
    public let tertiary: String
    public let showsTertiary: Bool

    public init(primary: String, secondary: String, tertiary: String, showsTertiary: Bool) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.showsTertiary = showsTertiary
    }
}

public struct ProviderIdentityPresentation: Sendable, Equatable {
    public struct Detail: Sendable, Equatable {
        public let label: String
        public let value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public let badge: String?
    public let plan: String?
    public let details: [Detail]

    public init(badge: String?, plan: String?, details: [Detail] = []) {
        self.badge = badge
        self.plan = plan
        self.details = details
    }
}

public enum ProviderCostMenuCardStyle: Sendable, Equatable {
    case generic
    /// Codex extra credits: used vs monthly cap in credit units, optional purchased balance.
    case creditsUsage
    case claude
}

public struct ProviderCostPresentation: Sendable, Equatable {
    public struct Balance: Sendable, Equatable {
        public let label: String
        public let amount: Double
        public let currencyCode: String

        public init(label: String, amount: Double, currencyCode: String) {
            self.label = label
            self.amount = amount
            self.currencyCode = currencyCode
        }
    }

    public let showsGenericFallback: Bool
    public let balances: [Balance]
    public let menuCardStyle: ProviderCostMenuCardStyle

    public init(
        showsGenericFallback: Bool = true,
        balances: [Balance] = [],
        menuCardStyle: ProviderCostMenuCardStyle = .generic)
    {
        self.showsGenericFallback = showsGenericFallback
        self.balances = balances
        self.menuCardStyle = menuCardStyle
    }
}

public struct ProviderOptionalDetailsPresentation: Sendable, Equatable {
    public let hiddenTitlesWithoutOptionalUsage: Set<String>
    public let costSummaryTitles: Set<String>

    public init(
        hiddenTitlesWithoutOptionalUsage: Set<String> = [],
        costSummaryTitles: Set<String> = [])
    {
        self.hiddenTitlesWithoutOptionalUsage = hiddenTitlesWithoutOptionalUsage
        self.costSummaryTitles = costSummaryTitles
    }
}

public enum ProviderUsageLane: Sendable, Hashable {
    case primary
    case secondary
    case tertiary
}

public struct ProviderSemanticWindows: Sendable, Equatable {
    public let session: RateWindow?
    public let weekly: RateWindow?

    public init(session: RateWindow?, weekly: RateWindow?) {
        self.session = session
        self.weekly = weekly
    }
}

public struct ProviderUsageWindowPair: Sendable, Equatable {
    public let primary: RateWindow?
    public let secondary: RateWindow?

    public init(primary: RateWindow?, secondary: RateWindow?) {
        self.primary = primary
        self.secondary = secondary
    }
}

public struct ProviderIconDecorations: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let face = Self(rawValue: 1 << 0)
    public static let notches = Self(rawValue: 1 << 1)
}

public struct ProviderIconWindowContext: Sendable {
    public let snapshot: UsageSnapshot
    public let secondaryOverrideWindowID: String?
    public let now: Date

    public init(snapshot: UsageSnapshot, secondaryOverrideWindowID: String?, now: Date) {
        self.snapshot = snapshot
        self.secondaryOverrideWindowID = secondaryOverrideWindowID
        self.now = now
    }
}

public struct ProviderMenuBarWindowContext: Sendable {
    public let metric: ProviderMenuBarMetric
    public let snapshot: UsageSnapshot
    public let supportsAverage: Bool
    public let prioritizesExhaustedQuotas: Bool
    public let now: Date

    public init(
        metric: ProviderMenuBarMetric,
        snapshot: UsageSnapshot,
        supportsAverage: Bool,
        prioritizesExhaustedQuotas: Bool,
        now: Date)
    {
        self.metric = metric
        self.snapshot = snapshot
        self.supportsAverage = supportsAverage
        self.prioritizesExhaustedQuotas = prioritizesExhaustedQuotas
        self.now = now
    }
}

public enum ProviderMenuBarWindowResolution: Sendable {
    case unhandled
    case resolved(RateWindow?)
}

public enum ProviderPlanUtilizationSeries: Sendable, Hashable {
    case session
    case weekly
    case tertiary
    case monthly
}

public enum ProviderCreditsVisibility: Sendable, Equatable {
    case standard
    case requiresValueOrError
}

public struct ProviderCostVisibilityContext: Sendable {
    public let snapshot: UsageSnapshot?
    public let showOptionalUsage: Bool

    public init(snapshot: UsageSnapshot?, showOptionalUsage: Bool) {
        self.snapshot = snapshot
        self.showOptionalUsage = showOptionalUsage
    }
}

public struct ProviderMenuCardPresentation: Sendable {
    public typealias CostVisibilityResolver = @Sendable (ProviderCostVisibilityContext) -> Bool

    private let costVisibilityResolver: CostVisibilityResolver
    public let creditsVisibility: ProviderCreditsVisibility
    public let supportsInlineTokenCostDashboard: Bool
    /// Codex and Claude local cost dashboards split spend by live Weekly quota windows.
    public let showsQuotaWeekCost: Bool

    public init(
        creditsVisibility: ProviderCreditsVisibility = .standard,
        costVisibilityResolver: @escaping CostVisibilityResolver = { _ in true },
        supportsInlineTokenCostDashboard: Bool = false,
        showsQuotaWeekCost: Bool = false)
    {
        self.creditsVisibility = creditsVisibility
        self.costVisibilityResolver = costVisibilityResolver
        self.supportsInlineTokenCostDashboard = supportsInlineTokenCostDashboard
        self.showsQuotaWeekCost = showsQuotaWeekCost
    }

    public func showsProviderCost(context: ProviderCostVisibilityContext) -> Bool {
        self.costVisibilityResolver(context)
    }
}

public struct ProviderUsagePresentation: Sendable {
    public typealias IdentityPresenter = @Sendable (
        _ provider: UsageProvider,
        _ snapshot: UsageSnapshot) -> ProviderIdentityPresentation
    public typealias CostPresenter = @Sendable (_ snapshot: UsageSnapshot) -> ProviderCostPresentation
    public typealias CreditResolver = @Sendable (_ credits: CreditsSnapshot) -> Double?
    public typealias IconWindowResolver = @Sendable (ProviderIconWindowContext) -> ProviderUsageWindowPair
    public typealias MenuBarWindowResolver = @Sendable (
        ProviderMenuBarWindowContext) -> ProviderMenuBarWindowResolution
    public typealias PlanUtilizationSeriesResolver = @Sendable (
        _ snapshot: UsageSnapshot) -> Set<ProviderPlanUtilizationSeries>?
    public typealias PlanUtilizationSeriesNormalizer = @Sendable (
        _ series: ProviderPlanUtilizationSeries,
        _ windowMinutes: Int) -> ProviderPlanUtilizationSeries

    private let identityPresenter: IdentityPresenter?
    private let costPresenter: CostPresenter
    private let creditResolver: CreditResolver?
    private let iconWindowResolver: IconWindowResolver
    private let menuBarWindowResolver: MenuBarWindowResolver
    private let planUtilizationSeriesResolver: PlanUtilizationSeriesResolver
    private let planUtilizationSeriesNormalizer: PlanUtilizationSeriesNormalizer
    public let iconDecorations: ProviderIconDecorations
    public let reservesMissingSecondaryIconLane: Bool
    /// Menu bar Balance elements read `ProviderCostSnapshot.balance` as the remaining prepaid amount.
    public let menuBarBalanceUsesPrepaidCost: Bool
    public let automaticSelectionPrioritizesExhaustedWindow: Bool
    public let secondaryGloballyCapsPrimary: Bool
    /// Longer quota lanes that must have room before the primary session lane is usable.
    /// Kept separate from widget policy until those surfaces adopt the same multi-lane projection.
    public let primaryBindingQuotaLanes: Set<ProviderUsageLane>
    public let menuCard: ProviderMenuCardPresentation
    public let optionalDetails: ProviderOptionalDetailsPresentation

    public init(
        identityPresenter: IdentityPresenter? = nil,
        costPresenter: @escaping CostPresenter = { _ in ProviderCostPresentation() },
        creditResolver: CreditResolver? = nil,
        iconWindowResolver: @escaping IconWindowResolver = { context in
            ProviderUsageWindowPair(primary: context.snapshot.primary, secondary: context.snapshot.secondary)
        },
        iconDecorations: ProviderIconDecorations = [],
        reservesMissingSecondaryIconLane: Bool = false,
        menuBarBalanceUsesPrepaidCost: Bool = false,
        automaticSelectionPrioritizesExhaustedWindow: Bool = true,
        menuBarWindowResolver: @escaping MenuBarWindowResolver = { _ in .unhandled },
        planUtilizationSeriesResolver: @escaping PlanUtilizationSeriesResolver = Self.standardPlanUtilizationSeries,
        planUtilizationSeriesNormalizer: @escaping PlanUtilizationSeriesNormalizer = { series, _ in series },
        secondaryGloballyCapsPrimary: Bool = false,
        primaryBindingQuotaLanes: Set<ProviderUsageLane> = [],
        menuCard: ProviderMenuCardPresentation = ProviderMenuCardPresentation(),
        optionalDetails: ProviderOptionalDetailsPresentation = ProviderOptionalDetailsPresentation())
    {
        self.identityPresenter = identityPresenter
        self.costPresenter = costPresenter
        self.creditResolver = creditResolver
        self.iconWindowResolver = iconWindowResolver
        self.iconDecorations = iconDecorations
        self.reservesMissingSecondaryIconLane = reservesMissingSecondaryIconLane
        self.menuBarBalanceUsesPrepaidCost = menuBarBalanceUsesPrepaidCost
        self.automaticSelectionPrioritizesExhaustedWindow = automaticSelectionPrioritizesExhaustedWindow
        self.menuBarWindowResolver = menuBarWindowResolver
        self.planUtilizationSeriesResolver = planUtilizationSeriesResolver
        self.planUtilizationSeriesNormalizer = planUtilizationSeriesNormalizer
        self.secondaryGloballyCapsPrimary = secondaryGloballyCapsPrimary
        self.primaryBindingQuotaLanes = primaryBindingQuotaLanes
        self.menuCard = menuCard
        self.optionalDetails = optionalDetails
    }

    public func rateWindowLabels(metadata: ProviderMetadata, snapshot _: UsageSnapshot) -> ProviderRateWindowLabels {
        ProviderRateWindowLabels(
            primary: metadata.sessionLabel,
            secondary: metadata.weeklyLabel,
            tertiary: metadata.opusLabel ?? "Sonnet",
            showsTertiary: metadata.supportsOpus)
    }

    public func identity(provider: UsageProvider, snapshot: UsageSnapshot) -> ProviderIdentityPresentation {
        if let identityPresenter {
            return identityPresenter(provider, snapshot)
        }
        guard let plan = snapshot.loginMethod(for: provider), !plan.isEmpty else {
            return ProviderIdentityPresentation(badge: nil, plan: nil)
        }
        let display = plan.capitalized
        return ProviderIdentityPresentation(badge: display, plan: display)
    }

    public func cost(snapshot: UsageSnapshot) -> ProviderCostPresentation {
        self.costPresenter(snapshot)
    }

    public func creditRemaining(_ credits: CreditsSnapshot) -> Double? {
        self.creditResolver?(credits)
    }

    public func iconWindows(context: ProviderIconWindowContext) -> ProviderUsageWindowPair {
        self.iconWindowResolver(context)
    }

    public func semanticWindows(snapshot: UsageSnapshot) -> ProviderSemanticWindows {
        Self.standardSemanticWindows(snapshot: snapshot)
    }

    public func menuBarWindow(context: ProviderMenuBarWindowContext) -> ProviderMenuBarWindowResolution {
        self.menuBarWindowResolver(context)
    }

    public func planUtilizationSeries(snapshot: UsageSnapshot) -> Set<ProviderPlanUtilizationSeries>? {
        self.planUtilizationSeriesResolver(snapshot)
    }

    public func normalizePlanUtilizationSeries(
        _ series: ProviderPlanUtilizationSeries,
        windowMinutes: Int) -> ProviderPlanUtilizationSeries
    {
        self.planUtilizationSeriesNormalizer(series, windowMinutes)
    }

    public static func window(in snapshot: UsageSnapshot, following lanes: [ProviderUsageLane]) -> RateWindow? {
        for lane in lanes {
            let window = switch lane {
            case .primary: snapshot.primary
            case .secondary: snapshot.secondary
            case .tertiary: snapshot.tertiary
            }
            if let window {
                return window
            }
        }
        return nil
    }

    public static func mostConstrained(_ windows: RateWindow?...) -> RateWindow? {
        windows.compactMap(\.self).max(by: { $0.usedPercent < $1.usedPercent })
    }

    public static func standardSemanticWindows(snapshot: UsageSnapshot) -> ProviderSemanticWindows {
        let usable = snapshot.measuredRateWindows
        return ProviderSemanticWindows(
            session: usable.first { window in
                guard let minutes = window.windowMinutes else { return false }
                return (60...(12 * 60)).contains(minutes)
            },
            weekly: usable.first { $0.windowMinutes == 7 * 24 * 60 })
    }

    public static func standardPlanUtilizationSeries(
        snapshot: UsageSnapshot) -> Set<ProviderPlanUtilizationSeries>?
    {
        let windows = [snapshot.primary, snapshot.secondary, snapshot.tertiary].compactMap(\.self)
            + (snapshot.extraRateWindows?.filter(\.usageKnown).map(\.window) ?? [])
        guard windows.contains(where: { $0.windowMinutes == 7 * 24 * 60 }) else { return nil }
        return [.weekly]
    }
}
