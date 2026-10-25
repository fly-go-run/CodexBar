import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

/// Renders a synthetic Claude card for visual review; only runs when an output directory is given.
@MainActor
struct MenuCardRedesignProofTests {
    @Test
    func `renders the synthetic Claude usage card`() throws {
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_MENU_CARD_PROOF"] else { return }
        for language in ["zh-Hans", "en"] {
            try CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                let model = try Self.model()
                for scheme in [ColorScheme.light, .dark] {
                    try Self.render(
                        model,
                        scheme: scheme,
                        name: "claude-card-\(language)-\(scheme == .dark ? "dark" : "light")",
                        directory: directory)
                }
            }
        }
    }

    private static func model() throws -> UsageMenuCardView.Model {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let day = 24.0 * 3600
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let costs: [Double] = [
            120, 160, 30, 90, 150, 70, 40, 10, 0, 50, 473, 300, 310, 120, 150, 155, 70, 60, 180, 30, 210,
            320, 220, 300, 200, 130, 170, 160, 12, 15,
        ]
        let daily = costs.enumerated().map { index, cost in
            CostUsageDailyReport.Entry(
                date: formatter.string(from: now.addingTimeInterval(-Double(costs.count - 1 - index) * day)),
                inputTokens: Int(cost * 3_000_000),
                outputTokens: Int(cost * 50000),
                totalTokens: Int(cost * 3_800_000),
                costUSD: cost,
                modelsUsed: ["claude-opus-4-1"],
                modelBreakdowns: [.init(
                    modelName: "claude-opus-4-1",
                    costUSD: cost,
                    totalTokens: Int(cost * 3_800_000))])
        }
        let tokenSnapshot = CostUsageTokenSnapshot(
            sessionTokens: 40_000_000,
            sessionCostUSD: 15.28,
            last30DaysTokens: 17_000_000_000,
            last30DaysCostUSD: 4476,
            historyDays: 30,
            daily: daily,
            updatedAt: now)

        func sample(_ model: String, rate: Double, hoursAgo: Double, tokens: Int = 1200) -> TokenOutputSpeedSample {
            let end = now.addingTimeInterval(-hoursAgo * 3600)
            return TokenOutputSpeedSample(
                model: model,
                outputTokens: tokens,
                startedAt: end.addingTimeInterval(-Double(tokens) / rate),
                completedAt: end)
        }
        let opusRates: [Double] = [122, 128, 118, 125, 131, 120, 117, 112, 126, 119, 115, 108, 104, 96, 92]
        var samples = opusRates.enumerated().flatMap { index, rate in
            (0..<3).map { sample(
                "claude-opus-4-1",
                rate: rate + Double($0 * 4),
                hoursAgo: Double(14 - index) + 0.2 * Double($0)) }
        }
        samples += (0..<12)
            .map { sample("claude-opus-4-1", rate: 92 + Double($0 % 4) * 5, hoursAgo: 0.05 * Double($0)) }
        samples += [97.0, 94, 101, 99, 96, 98, 103, 95].enumerated().map { index, rate in
            sample("claude-sonnet-4-5", rate: rate, hoursAgo: Double(index) * 1.7 + 0.1, tokens: 500)
        }
        let speed = TokenOutputSpeedSnapshot(samples: samples, now: now)

        return try UsageMenuCardView.Model.make(.init(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            snapshot: UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 14,
                    windowMinutes: 5 * 60,
                    resetsAt: now.addingTimeInterval(3 * 3600 + 50 * 60),
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 88,
                    windowMinutes: 7 * 24 * 60,
                    resetsAt: now.addingTimeInterval(2 * 3600 + 10 * 60),
                    resetDescription: nil),
                tertiary: RateWindow(
                    usedPercent: 0,
                    windowMinutes: 7 * 24 * 60,
                    resetsAt: now.addingTimeInterval(2 * 3600 + 10 * 60),
                    resetDescription: nil),
                updatedAt: now.addingTimeInterval(-60)),
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: tokenSnapshot,
            tokenError: nil,
            tokenOutputSpeed: speed,
            account: AccountInfo(email: "user@example.com", plan: "Max 5x"),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: true,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            costUsageBucketCalendar: calendar,
            now: now))
    }

    @Test
    func `renders the synthetic Claude cost submenu with every model's speed`() throws {
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_MENU_CARD_PROOF"] else { return }
        let now = Date()
        func samples(
            _ model: String,
            tokens: Int,
            seconds: TimeInterval,
            minutesAgo: [Double]) -> [TokenOutputSpeedSample]
        {
            minutesAgo.map { minutes in
                let end = now.addingTimeInterval(-minutes * 60)
                return TokenOutputSpeedSample(
                    model: model, outputTokens: tokens, startedAt: end.addingTimeInterval(-seconds), completedAt: end)
            }
        }
        let speed = TokenOutputSpeedSnapshot(
            samples: samples("claude-opus-4-1", tokens: 640, seconds: 10, minutesAgo: [3, 8, 14, 22, 35, 48])
                + samples("claude-opus-4-1", tokens: 900, seconds: 10, minutesAgo: [90, 150, 210, 300])
                + samples("claude-sonnet-4-5", tokens: 900, seconds: 10, minutesAgo: [120, 180, 240, 400])
                + samples("claude-haiku-4-5", tokens: 300, seconds: 2, minutesAgo: [70, 260]),
            now: now)
        let calendar = Calendar.current
        let daily = (0..<30).map { offset -> CostUsageDailyReport.Entry in
            let day = calendar.date(byAdding: .day, value: -29 + offset, to: now)!
            let key = day.formatted(.iso8601.year().month().day())
            let cost = Double(40 + (offset * 37) % 160)
            return CostUsageDailyReport.Entry(
                date: key,
                inputTokens: nil,
                outputTokens: nil,
                totalTokens: Int(cost * 3_000_000),
                costUSD: cost,
                modelsUsed: ["claude-opus-4-1", "claude-sonnet-4-5"],
                modelBreakdowns: [
                    .init(modelName: "claude-opus-4-1", costUSD: cost * 0.8, totalTokens: Int(cost * 2_400_000)),
                    .init(modelName: "claude-sonnet-4-5", costUSD: cost * 0.2, totalTokens: Int(cost * 600_000)),
                ])
        }
        for language in ["zh-Hans", "en"] {
            try CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                for scheme in [ColorScheme.light, .dark] {
                    let view = CostHistoryChartMenuView(
                        provider: .claude,
                        daily: daily,
                        totalCostUSD: daily.compactMap(\.costUSD).reduce(0, +),
                        tokenSpeed: UsageMenuCardView.Model.tokenSpeedAllModelsSummary(speed),
                        hidePersonalInfo: false,
                        width: 310)
                        .codexBarLocalized()
                        .environment(\.colorScheme, scheme)
                        .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.97))
                    try Self.write(
                        view,
                        name: "claude-cost-\(language)-\(scheme == .dark ? "dark" : "light")",
                        directory: directory)
                }
            }
        }
    }

    private static func write(_ view: some View, name: String, directory: String) throws {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: view.frame(width: 310))
        renderer.scale = 2
        let bitmap = try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
    }

    private static func render(
        _ model: UsageMenuCardView.Model,
        scheme: ColorScheme,
        name: String,
        directory: String) throws
    {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let view = UsageMenuCardHeaderAndUsageSectionView(
            model: model,
            layoutModel: model,
            bottomPadding: 6,
            width: 310)
            .environment(\.colorScheme, scheme)
            .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.97))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let bitmap = try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
    }
}
