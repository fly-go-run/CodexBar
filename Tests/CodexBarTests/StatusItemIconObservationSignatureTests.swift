import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct StatusItemIconObservationSignatureTests {
    private static func makeSnapshot(
        provider: UsageProvider,
        email: String,
        primaryUsedPercent: Double = 10,
        secondaryUsedPercent: Double = 20,
        updatedAt: Date = Date(timeIntervalSince1970: 100))
        -> UsageSnapshot
    {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: primaryUsedPercent,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: secondaryUsedPercent,
                windowMinutes: 10080,
                resetsAt: nil,
                resetDescription: nil),
            updatedAt: updatedAt,
            identity: ProviderIdentitySnapshot(
                providerID: provider.instanceID,
                accountEmail: email,
                accountOrganization: nil,
                loginMethod: "plus"))
    }

    private static func makeTokenSnapshot(
        todayCost: Double,
        last30DaysCost: Double,
        sessionTokens: Int? = nil,
        now: Date = .init())
        -> CostUsageTokenSnapshot
    {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return CostUsageTokenSnapshot(
            sessionTokens: sessionTokens,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: last30DaysCost,
            daily: [
                CostUsageDailyReport.Entry(
                    date: formatter.string(from: now),
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: nil,
                    costUSD: todayCost,
                    modelsUsed: nil,
                    modelBreakdowns: nil),
            ],
            updatedAt: now)
    }
}
