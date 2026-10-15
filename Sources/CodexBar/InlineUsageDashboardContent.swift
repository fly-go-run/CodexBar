import CodexBarCore
import SwiftUI

struct InlineUsageDashboardModel: Equatable {
    struct HoverDetail: Equatable {
        let dateLabel: String
        let cost: Double?
        let tokenCount: Int?
        let currencyCode: String
        var incompleteRequestCount: Int = 0
        var tokensOnly = false

        var summary: String {
            let cost = self.cost.map { UsageFormatter.currencyString($0, currencyCode: self.currencyCode) } ?? "—"
            let tokens = self.tokenCount.map(UsageFormatter.tokenCountString) ?? "—"
            if self.tokensOnly {
                return L("%@: %@", self.dateLabel, L("%@ tokens", tokens))
                    + UsageFormatter.incompleteUsageSuffix(self.incompleteRequestCount)
            }
            return L("%@: %@ · %@ tokens", self.dateLabel, cost, tokens)
                + UsageFormatter.incompleteUsageSuffix(self.incompleteRequestCount)
        }
    }

    struct KPI: Equatable {
        let title: String
        let value: String
        let emphasis: Bool
        var detail: String?
    }

    struct Point: Equatable, Identifiable {
        let id: String
        let label: String
        let value: Double?
        let accessibilityValue: String
        var hoverDetail: HoverDetail?
    }

    enum ValueStyle: Equatable {
        case currencyUSD
        case currency(symbol: String)
        case tokens
        case points
    }

    struct QuotaWindow: Equatable, Identifiable {
        let id: String
        let title: String
        let range: String
        let value: String
        var note: String?
    }

    let accessibilityLabel: String
    let valueStyle: ValueStyle
    let kpis: [KPI]
    let points: [Point]
    let detailLines: [String]
    /// Codex/Claude weekly quota windows, newest first. Empty for other cost dashboards.
    var quotaWindows: [QuotaWindow] = []
    /// Provider branding color used to fill the mini usage bars. When nil the bars fall back to a
    /// neutral palette derived from `valueStyle`.
    var barColor: Color?
    /// ISO 4217 currency code for cost dashboards. When non-nil, `MiniUsageBars` shows a max-cost scale label.
    /// Nil for token/points dashboards.
    var currencyCode: String?
    var chartTitle: String?
    var tokenSpeed: TokenSpeedSummary?
    /// One-line history summary shown above the chart, e.g. "近 30 天  $2,909 · 12B tokens".
    var chartCaption: String?
    /// Cost-estimate disclaimer, shown as the chart's hover help instead of a footnote row.
    var chartHelp: String?
}

extension UsageMenuCardView.Model {
    static func inlineUsageDashboard(input: Input) -> InlineUsageDashboardModel? {
        guard var model = self.resolveInlineUsageDashboard(input: input) else { return nil }
        model.barColor = Self.inlineDashboardBarColor(for: input.provider)
        return model
    }

    /// Provider branding color for the inline usage bars, matching the provider's switcher tab and
    /// detailed cost-history chart.
    static func inlineDashboardBarColor(for provider: UsageProvider) -> Color {
        let color = ProviderAccentPalette.color(for: provider)
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    private static func resolveInlineUsageDashboard(input: Input) -> InlineUsageDashboardModel? {
        let menuCard = ProviderDescriptorRegistry.descriptor(for: input.provider).presentation.menuCard
        if menuCard.usesProviderCostHistoryAsPrimaryDashboard,
           input.costSummaryInlineEnabled,
           let tokenSnapshot = primaryCostHistorySnapshot(input: input),
           !tokenSnapshot.daily.isEmpty
        {
            return self.costHistoryInlineDashboard(input: input, snapshot: tokenSnapshot)
        }
        if menuCard.supportsInlineTokenCostDashboard,
           input.costSummaryInlineEnabled,
           let tokenSnapshot = input.tokenSnapshot,
           !tokenSnapshot.daily.isEmpty
        {
            return Self.costHistoryInlineDashboard(input: input, snapshot: tokenSnapshot)
        }
        return nil
    }

    static func usesProviderCostHistoryAsPrimaryDashboard(_ provider: UsageProvider) -> Bool {
        ProviderDescriptorRegistry.descriptor(for: provider).presentation.menuCard
            .usesProviderCostHistoryAsPrimaryDashboard
    }

    static func primaryCostHistorySnapshot(input: Input) -> CostUsageTokenSnapshot? {
        ProviderDescriptorRegistry.descriptor(for: input.provider).presentation.menuCard.primaryCostHistory(
            snapshot: input.snapshot,
            tokenSnapshot: input.tokenSnapshot)
    }

    static func showsQuotaWeekCost(for provider: UsageProvider) -> Bool {
        self.menuCardPresentation(for: provider).showsQuotaWeekCost
    }

    static func menuCardPresentation(for provider: UsageProvider) -> ProviderMenuCardPresentation {
        ProviderDescriptorRegistry.descriptor(for: provider).presentation.menuCard
    }

    private static func weeklyQuotaWindow(from input: Input) -> RateWindow? {
        guard let snapshot = input.snapshot else { return nil }
        return ProviderDescriptorRegistry.descriptor(for: input.provider)
            .presentation.semanticWindows(snapshot: snapshot).weekly
    }

    private struct CostHistoryQuotaPresentation {
        let rows: [InlineUsageDashboardModel.QuotaWindow]
        let insertsKPIs: Bool
        let relabelsHistory: Bool
        let boundariesAreEstimated: Bool
        let costValue: String
        let tokenValue: String
    }

    private static func costHistoryQuotaPresentation(
        input: Input,
        snapshot: CostUsageTokenSnapshot,
        historyDays: Int,
        convertedString: (Double) -> String) -> CostHistoryQuotaPresentation
    {
        let weeklyWindow = Self.weeklyQuotaWindow(from: input)
        // A provider whose surfaced reset is not one stable account-wide quota cannot derive past
        // boundaries from observed resets: those instants belong to different quotas. Nominal
        // weekly strides from the live reset remain correct, so only the observations are dropped.
        let ignoresObservedResets = Self.menuCardPresentation(for: input.provider)
            .ignoresObservedQuotaResetBoundaries
        var observations = ignoresObservedResets ? [] : input.observedWeeklyResets
        if !ignoresObservedResets,
           let resetAt = CostUsageTokenSnapshot.quotaWeekReset(from: weeklyWindow),
           let capturedAt = input.snapshot?.updatedAt
        {
            observations.append(.init(capturedAt: capturedAt, resetsAt: resetAt))
        }
        let quotaWeeks = Self.showsQuotaWeekCost(for: input.provider) && historyDays >= 7
            ? snapshot.quotaWeekSummaries(
                resetAt: CostUsageTokenSnapshot.quotaWeekReset(from: weeklyWindow),
                windowMinutes: weeklyWindow?.windowMinutes,
                observedResetInstants: ignoresObservedResets
                    ? [] : Self.redeemedWeeklyResetInstants(from: input.snapshot),
                resetObservations: observations,
                now: input.now,
                calendar: input.costUsageBucketCalendar)
            : []
        let currentWeek = quotaWeeks.first { $0.isCurrent }
        let rows = quotaWeeks.compactMap { week -> InlineUsageDashboardModel.QuotaWindow? in
            guard week.isCurrent || week.entryCount > 0 else { return nil }
            return Self.quotaWindowRow(
                week: week,
                cost: week.totalCostUSD.map(convertedString) ?? "—",
                calendar: input.costUsageBucketCalendar)
        }
        return CostHistoryQuotaPresentation(
            rows: rows,
            insertsKPIs: currentWeek != nil && historyDays > 7 && snapshot.last30DaysRequests == nil,
            relabelsHistory: currentWeek != nil && historyDays == 7 && snapshot.last30DaysRequests == nil,
            boundariesAreEstimated: currentWeek?.boundariesAreEstimated == true,
            costValue: Self.quotaMetricValue(
                currentWeek?.totalCostUSD.map(convertedString), complete: currentWeek?.costIsComplete == true),
            tokenValue: Self.quotaMetricValue(
                currentWeek?.totalTokens.map(UsageFormatter.tokenCountString),
                complete: currentWeek?.tokensAreComplete == true))
    }

    private static func costHistoryDetailLines(
        input: Input,
        snapshot: CostUsageTokenSnapshot,
        requestHistoryTitle: String,
        displayCurrencyCode: String) -> [String]
    {
        let incompleteCount = CostUsageIncompleteRequests.sum(snapshot.daily.map(\.incompleteRequestCount))
        let unpricedCount = snapshot.daily.reduce(0) { $0 + max(0, $1.unpricedRequestCount ?? 0) }
        var details: [String] = []
        if input.costComparisonPeriodsEnabled {
            details.append(contentsOf: snapshot.comparisonSummaries(calendar: input.costUsageBucketCalendar).map {
                Self.costWindowLine(
                    summary: $0,
                    currencyCode: displayCurrencyCode,
                    sourceCurrencyCode: snapshot.currencyCode)
            })
        }
        if let coverage = Self.tokenHistoryCoverageHint(snapshot) { details.append(coverage) }
        if unpricedCount > 0 { details.append("\(L("Partial estimate")) · \(L("Unpriced")) \(unpricedCount)") }
        if let note = UsageFormatter.incompleteUsageNote(incompleteCount) { details.append(note) }
        // The top model is visible in the chart's per-day breakdown and the estimate hint moved to the
        // chart's hover help, so the card keeps only lines that change what the numbers mean.
        let tokenCost = ProviderDescriptorRegistry.descriptor(for: input.provider).tokenCost
        if tokenCost.showsRequestHistory, let requestCount = snapshot.last30DaysRequests {
            details
                .append("\(requestHistoryTitle): \(UsageFormatter.tokenCountString(requestCount)) \(L("requests"))")
        }
        return details
    }

    private static func costHistoryInlineDashboard(
        input: Input,
        snapshot: CostUsageTokenSnapshot) -> InlineUsageDashboardModel
    {
        if ProviderDescriptorRegistry.descriptor(for: input.provider).tokenCost.presentation == .tokensOnly {
            return self.tokenHistoryInlineDashboard(
                provider: input.provider,
                snapshot: snapshot,
                comparisonPeriodsEnabled: input.costComparisonPeriodsEnabled,
                calendar: input.costUsageBucketCalendar)
        }
        let displayCurrencyCode = UsageFormatter.convertedCost(
            0,
            preferredCurrency: input.preferredCurrencyCode,
            providerCurrency: snapshot.currencyCode).currencyCode
        func convertedValue(_ value: Double) -> Double {
            UsageFormatter.convertedCost(
                value,
                preferredCurrency: input.preferredCurrencyCode,
                providerCurrency: snapshot.currencyCode).value
        }
        func convertedString(_ value: Double) -> String {
            let converted = UsageFormatter.convertedCost(
                value,
                preferredCurrency: input.preferredCurrencyCode,
                providerCurrency: snapshot.currencyCode)
            return Self.menuCurrencyString(converted.value, currencyCode: converted.currencyCode)
        }

        let historyDays = snapshot.displayHistoryDays(calendar: input.costUsageBucketCalendar)
        let explicitLabel = snapshot.historyLabel.map { L($0) }
        let period = explicitLabel ?? (historyDays == 1 ? L("Today") : String(format: L("Last %d days"), historyDays))
        let legacyMonth = explicitLabel == nil && historyDays == 30
        let tokenCost = ProviderDescriptorRegistry.descriptor(for: input.provider).tokenCost
        let historyTitle = tokenCost.historyTitleStyle == .compact
            ? (legacyMonth ? "30d" : period)
            :
            (explicitLabel ??
                (legacyMonth ? L("30d cost") : historyDays == 1 ? L("Today") : "\(period) \(L("Cost"))"))
        let tokenHistoryTitle = legacyMonth ? L("30d tokens") : String(format: L("%@ tokens"), period)
        let requestHistoryTitle = legacyMonth ? L("30d requests") : String(format: L("%@ requests"), period)
        let accessibilityCostLabel = legacyMonth ? L("30d cost") : L("%@ cost", period)
        let points = Self.inlineCostHistoryPoints(
            days: Self.inlineCostHistoryDays(
                snapshot: snapshot,
                historyDays: historyDays,
                preservesCalendarDays: tokenCost.preservesCalendarDaysInCharts,
                calendar: input.costUsageBucketCalendar),
            displayCurrencyCode: displayCurrencyCode,
            convertedValue: convertedValue)
        let latest = CostUsageTokenSnapshot.latestEntry(in: snapshot.daily)
        let usesLatestPrimary = tokenCost.primaryValue == .latestDaily
        let primaryCostUSD = usesLatestPrimary ? latest?.costUSD : snapshot.sessionCostUSD
        let incompleteCount = CostUsageIncompleteRequests.sum(snapshot.daily.map(\.incompleteRequestCount))
        let primaryIncompleteCount = usesLatestPrimary ? latest?.incompleteRequestCount ?? 0
            : snapshot.summary(forLastDays: 1, calendar: input.costUsageBucketCalendar).incompleteRequestCount
        let primarySuffix = UsageFormatter.incompleteUsageSuffix(primaryIncompleteCount)
        let historySuffix = UsageFormatter.incompleteUsageSuffix(incompleteCount)
        let quota = Self.costHistoryQuotaPresentation(
            input: input,
            snapshot: snapshot,
            historyDays: historyDays,
            convertedString: convertedString)
        let weekCostTitle = L("Current window")
        let weekTokenTitle = L("%@ tokens", L("Current window"))
        var details = Self.costHistoryDetailLines(
            input: input,
            snapshot: snapshot,
            requestHistoryTitle: requestHistoryTitle,
            displayCurrencyCode: displayCurrencyCode)
        let providerName = ProviderDefaults.metadata[input.provider]?.displayName ?? input.provider.rawValue
        let accessibilityLabel = L(
            "%@: %@",
            providerName,
            accessibilityCostLabel)
        let todayKPI = InlineUsageDashboardModel.KPI(
            title: usesLatestPrimary ? L("Latest") : L("Today"),
            value: (primaryCostUSD.map(convertedString) ?? "—") + primarySuffix,
            emphasis: true)
        let historyCostKPI = InlineUsageDashboardModel.KPI(
            title: quota.relabelsHistory ? weekCostTitle : historyTitle,
            value: quota.relabelsHistory
                ? quota.costValue
                : (snapshot.last30DaysCostUSD.map(convertedString) ?? "—") + historySuffix,
            emphasis: quota.relabelsHistory)
        let tokenHistoryKPI = InlineUsageDashboardModel.KPI(
            title: quota.relabelsHistory ? weekTokenTitle : tokenHistoryTitle,
            value: quota.relabelsHistory
                ? quota.tokenValue
                : (snapshot.last30DaysTokens.map(UsageFormatter.tokenCountString) ?? "—") + historySuffix,
            emphasis: false)
        let trailingKPIs = Self.costHistoryTrailingKPIs(snapshot: snapshot, latest: latest)
        var kpis: [InlineUsageDashboardModel.KPI]
        var chartCaption: String?
        if quota.insertsKPIs, let latestTokensKPI = trailingKPIs.first {
            // Two headline numbers; token counts ride underneath, the 30d totals caption the chart.
            var today = todayKPI
            today.detail = L("menu_tokens_short", latestTokensKPI.value)
            kpis = [
                today,
                .init(
                    title: weekCostTitle,
                    value: quota.costValue,
                    emphasis: true,
                    detail: L("menu_tokens_short", quota.tokenValue)),
            ]
            chartCaption = "\(period)  \(historyCostKPI.value) · \(L("menu_tokens_short", tokenHistoryKPI.value))"
        } else {
            kpis = [todayKPI, historyCostKPI]
            if snapshot.last30DaysRequests == nil {
                kpis.append(contentsOf: trailingKPIs)
                kpis.append(tokenHistoryKPI)
            } else {
                kpis.append(tokenHistoryKPI)
                kpis.append(contentsOf: trailingKPIs)
            }
        }
        var model = InlineUsageDashboardModel(
            accessibilityLabel: accessibilityLabel,
            valueStyle: Self.costValueStyle(currencyCode: displayCurrencyCode),
            kpis: kpis,
            points: points,
            detailLines: details)
        model.quotaWindows = quota.rows
        model.chartCaption = chartCaption
        model.chartHelp = Self.tokenUsageHintLines(provider: input.provider).joined(separator: "\n")
        model.tokenSpeed = Self.tokenSpeedSummary(input.tokenOutputSpeed)
        model.currencyCode = displayCurrencyCode
        model.chartTitle = L("Daily spend · %@", period)
        return model
    }

    private static func redeemedWeeklyResetInstants(from snapshot: UsageSnapshot?) -> [Date] {
        snapshot?.codexResetCredits?.credits.compactMap { credit in
            guard credit.status == .redeemed else { return nil }
            return credit.redeemedAt
        } ?? []
    }

    static func quotaMetricValue(_ value: String?, complete: Bool) -> String {
        guard let value else { return "—" }
        return complete ? value : "≥ \(value)"
    }

    static func quotaWindowRow(
        week: CostUsageQuotaWeek,
        cost: String,
        calendar: Calendar) -> InlineUsageDashboardModel.QuotaWindow
    {
        let costValue = Self.quotaMetricValue(week.totalCostUSD == nil ? nil : cost, complete: week.costIsComplete)
        let tokenValue = Self.quotaMetricValue(
            week.totalTokens.map(UsageFormatter.tokenCountString), complete: week.tokensAreComplete)
        let value: String = if week.totalTokens != nil {
            "\(costValue) · \(tokenValue)"
        } else {
            costValue
        }
        let range = Self.quotaWindowRangeLabel(start: week.start, end: week.end, calendar: calendar)
        return InlineUsageDashboardModel.QuotaWindow(
            id: "\(week.offset)-\(Int(week.start.timeIntervalSince1970))",
            title: Self.quotaWeekHistoryLabel(week: week),
            range: week.boundariesAreEstimated ? L("Estimated: %@", range) : range,
            value: value,
            note: (!week.costIsComplete && week.totalCostUSD != nil)
                || (!week.tokensAreComplete && week.totalTokens != nil) ? L("Partial estimate") : nil)
    }

    static func quotaWindowRangeLabel(
        start: Date,
        end: Date,
        calendar: Calendar,
        locale: Locale = codexBarLocalizedResourceLocale()) -> String
    {
        let startDay = calendar.dateComponents([.year, .month, .day], from: start)
        let endDay = calendar.dateComponents([.year, .month, .day], from: end)
        let sameDay = startDay.year == endDay.year
            && startDay.month == endDay.month
            && startDay.day == endDay.day
        let sameYear = startDay.year == endDay.year
        func formatter(template: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter
        }
        if sameDay {
            let startText = formatter(template: "MMMdjmm").string(from: start)
            let endText = formatter(template: "jmm").string(from: end)
            return "\(startText) – \(endText)"
        }
        let template = sameYear ? "MMMdjmm" : "yMMMdjmm"
        let rangeFormatter = formatter(template: template)
        return "\(rangeFormatter.string(from: start)) – \(rangeFormatter.string(from: end))"
    }

    private static func quotaWeekHistoryLabel(week: CostUsageQuotaWeek) -> String {
        switch week.offset {
        case 0:
            L("Current window")
        case 1:
            L("Previous window")
        default:
            L("%d windows ago", week.offset)
        }
    }

    private static func tokenHistoryInlineDashboard(
        provider: UsageProvider,
        snapshot: CostUsageTokenSnapshot,
        comparisonPeriodsEnabled: Bool,
        calendar: Calendar) -> InlineUsageDashboardModel
    {
        let config = ProviderDescriptorRegistry.descriptor(for: provider).tokenCost
        let historyDays = snapshot.displayHistoryDays(calendar: calendar)
        let historyLabel = snapshot.historyLabel.map { L($0) } ?? Self.costHistoryWindowLabel(days: historyDays)
        var kpis = [InlineUsageDashboardModel.KPI(
            title: L("Today"),
            value: L("%@ tokens", snapshot.sessionTokens.map(UsageFormatter.tokenCountString) ?? "—"),
            emphasis: true)]
        if historyDays > 1 {
            kpis.append(.init(
                title: historyLabel,
                value: L("%@ tokens", snapshot.last30DaysTokens.map(UsageFormatter.tokenCountString) ?? "—"),
                emphasis: false))
        }
        var details = Self.tokenUsageHintLines(provider: provider)
        if details.isEmpty { details.append(L("Local token history · dollar costs unavailable")) }
        if let coverage = Self.tokenHistoryCoverageHint(snapshot) { details.append(coverage) }
        if comparisonPeriodsEnabled {
            details.append(contentsOf: snapshot.comparisonSummaries(calendar: calendar).map {
                Self.tokenWindowLine(label: Self.costHistoryWindowLabel(days: $0.days), tokens: $0.totalTokens)
            })
        }
        let points = Self.inlineCostHistoryPoints(
            days: Self.inlineCostHistoryDays(
                snapshot: snapshot,
                historyDays: historyDays,
                preservesCalendarDays: config.preservesCalendarDaysInCharts,
                calendar: calendar),
            displayCurrencyCode: "USD",
            convertedValue: { $0 },
            tokensOnly: true)
        let name = ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
        return InlineUsageDashboardModel(
            accessibilityLabel: L("%@: %@", name, L("Token history")),
            valueStyle: .tokens,
            kpis: kpis,
            points: points,
            detailLines: details)
    }

    private static func costHistoryTrailingKPIs(
        snapshot: CostUsageTokenSnapshot,
        latest: CostUsageDailyReport.Entry?)
        -> [InlineUsageDashboardModel.KPI]
    {
        if let requests = snapshot.last30DaysRequests {
            return [
                .init(
                    title: L("Requests"),
                    value: UsageFormatter.tokenCountString(requests),
                    emphasis: false),
            ]
        }
        return [
            .init(
                title: L("Latest tokens"),
                value: (latest?.totalTokens.map(UsageFormatter.tokenCountString) ?? "—")
                    + UsageFormatter.incompleteUsageSuffix(latest?.incompleteRequestCount ?? 0),
                emphasis: false),
        ]
    }

    private static func costString(_ value: Double, currencyCode: String) -> String {
        UsageFormatter.currencyString(value, currencyCode: currencyCode)
    }

    private static func costValueStyle(currencyCode: String) -> InlineUsageDashboardModel.ValueStyle {
        if currencyCode == "USD" {
            return .currencyUSD
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale(identifier: "en_US")
        let symbol = formatter.currencySymbol ?? currencyCode
        return .currency(symbol: symbol)
    }

    static func shortDayLabel(_ day: String) -> String {
        let pieces = day.split(separator: "-")
        guard pieces.count == 3, let rawDay = Int(pieces[2]) else { return day }
        return "\(rawDay)"
    }

    private static func inlineCostHistoryDays(
        snapshot: CostUsageTokenSnapshot,
        historyDays: Int,
        preservesCalendarDays: Bool,
        calendar sourceCalendar: Calendar)
        -> [(date: String, costUSD: Double?, totalTokens: Int?, incompleteRequestCount: Int)]
    {
        let existingDays = snapshot.daily.suffix(historyDays)
            .compactMap { entry -> (date: String, costUSD: Double?, totalTokens: Int?, incompleteRequestCount: Int)? in
                guard entry.costUSD != nil || entry.totalTokens != nil || entry.incompleteRequestCount > 0
                else { return nil }
                return (entry.date, entry.costUSD, entry.totalTokens, entry.incompleteRequestCount)
            }
        guard preservesCalendarDays else { return existingDays }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = sourceCalendar.timeZone
        let endDate = calendar.startOfDay(for: snapshot.updatedAt)
        guard let startDate = calendar.date(byAdding: .day, value: -(historyDays - 1), to: endDate) else {
            return existingDays
        }

        let entriesByDay = Dictionary(snapshot.daily.map { ($0.date, $0) }, uniquingKeysWith: { _, newer in newer })
        return (0..<historyDays).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else { return nil }
            let dayKey = Self.inlineCostHistoryDayKey(date, calendar: calendar)
            if let entry = entriesByDay[dayKey] {
                return (
                    date: dayKey,
                    costUSD: entry.costUSD,
                    totalTokens: entry.totalTokens,
                    incompleteRequestCount: entry.incompleteRequestCount)
            }
            // A missing date is zero only after the scan has covered the requested history.
            return (
                date: dayKey,
                costUSD: snapshot.historyIsFullyScanned ? 0 : nil,
                totalTokens: snapshot.historyIsFullyScanned ? 0 : nil,
                incompleteRequestCount: 0)
        }
    }

    private static func inlineCostHistoryPoints(
        days: [(date: String, costUSD: Double?, totalTokens: Int?, incompleteRequestCount: Int)],
        displayCurrencyCode: String,
        convertedValue: (Double) -> Double,
        tokensOnly: Bool = false) -> [InlineUsageDashboardModel.Point]
    {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        let formatter = DateFormatter()
        formatter.locale = codexBarLocalizedLocale()
        formatter.timeZone = parser.timeZone
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return days.map { day in
            let dateLabel = parser.date(from: day.date).map(formatter.string(from:)) ?? day.date
            let costUSD = tokensOnly ? nil : day.costUSD.flatMap { $0 >= 0 ? $0 : nil }
            let tokenCount = day.totalTokens.flatMap { $0 >= 0 ? $0 : nil }
            let convertedCost = costUSD.map(convertedValue)
            let hoverDetail: InlineUsageDashboardModel.HoverDetail? = if costUSD != nil || tokenCount != nil || day
                .incompleteRequestCount > 0
            {
                .init(
                    dateLabel: dateLabel,
                    cost: convertedCost,
                    tokenCount: tokenCount,
                    currencyCode: displayCurrencyCode,
                    incompleteRequestCount: day.incompleteRequestCount,
                    tokensOnly: tokensOnly)
            } else {
                nil
            }
            return InlineUsageDashboardModel.Point(
                id: day.date,
                label: Self.shortDayLabel(day.date),
                value: tokensOnly ? tokenCount.map(Double.init) : convertedCost,
                accessibilityValue: hoverDetail?.summary ?? "\(dateLabel): \(L("Unknown"))",
                hoverDetail: hoverDetail)
        }
    }

    private static func inlineCostHistoryDayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0)
    }

    /// Menu amounts: cents only below $100 ("$5.28", "$437", "$2,909").
    static func menuCurrencyString(_ value: Double, currencyCode: String) -> String {
        guard abs(value) >= 100 else { return UsageFormatter.currencyString(value, currencyCode: currencyCode) }
        return value.formatted(
            .currency(code: currencyCode)
                .precision(.fractionLength(0))
                .locale(Locale(identifier: "en_US")))
    }
}

struct InlineUsageDashboardContent: View {
    private let model: InlineUsageDashboardModel
    var showsChart = true
    @Environment(\.menuItemHighlighted) private var isHighlighted

    init(model: InlineUsageDashboardModel, showsChart: Bool = true) {
        self.model = model
        self.showsChart = showsChart
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            self.kpis
            if self.showsChart, !self.model.points.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if let caption = self.model.chartCaption {
                        Text(caption)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .lineLimit(1)
                    }
                    MiniUsageBars(model: self.model)
                        .frame(height: 46)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(self.model.accessibilityLabel)
                }
                .help(self.model.chartHelp ?? "")
            }
            if let tokenSpeed = self.model.tokenSpeed {
                InlineTokenSpeedRow(summary: tokenSpeed)
            }
            if !self.model.detailLines.isEmpty {
                self.detailLines
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpis: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 118), alignment: .leading),
                GridItem(.flexible(minimum: 100), alignment: .leading),
            ],
            alignment: .leading,
            spacing: 10)
        {
            ForEach(Array(self.model.kpis.enumerated()), id: \.offset) { _, kpi in
                KPIBlock(title: kpi.title, value: kpi.value, emphasis: kpi.emphasis, detail: kpi.detail)
            }
        }
    }

    private var detailLines: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(self.model.detailLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            }
        }
    }

    private struct KPIBlock: View {
        let title: String
        let value: String
        let emphasis: Bool
        var detail: String?
        @Environment(\.menuItemHighlighted) private var isHighlighted

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(self.title)
                    .font(.subheadline)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .fixedSize(horizontal: false, vertical: true)
                Text(self.value)
                    .font(.system(size: self.emphasis ? 15 : 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let detail = self.detail {
                    Text(detail)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct MiniUsageBars: View {
        let model: InlineUsageDashboardModel
        @Environment(\.menuItemHighlighted) private var isHighlighted
        @Environment(\.menuUsageBarSelection) private var injectedSelection
        @State private var selectedPointID: String?

        var body: some View {
            let scale = UsageChartScale(values: self.model.points.compactMap(\.value))
            let hoverDetail = self.model.points
                .first(where: { $0.id == (self.injectedSelection ?? self.$selectedPointID).wrappedValue })?
                .hoverDetail
            VStack(alignment: .trailing, spacing: 2) {
                if let currencyCode = self.model.currencyCode {
                    let scaleLabel = scale.maximum > 0
                        ? UsageFormatter.compactCurrencyString(scale.maximum, currencyCode: currencyCode)
                        : " "
                    Text(hoverDetail?.summary ?? scaleLabel)
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, alignment: hoverDetail == nil ? .trailing : .leading)
                        .opacity(hoverDetail != nil || scale.maximum > 0 ? 1 : 0)
                        .accessibilityHidden(hoverDetail != nil)
                }
                MenuUsageBarStrip(
                    points: self.model.points.map(\.menuUsageBarPoint),
                    baseColor: self.baseColor,
                    selection: self.injectedSelection ?? self.$selectedPointID)
            }
        }

        private var baseColor: Color {
            self.model.chartColor
        }
    }
}
