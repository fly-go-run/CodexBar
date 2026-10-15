import AppKit
import Foundation
import QuartzCore
import XCTest
@testable import CodexBar
@testable import CodexBarCore

/// Opt-in native menu proof with disposable settings and no provider transports.
@MainActor
final class StatusMenuProviderNativeProofTests: XCTestCase {
    private static func nativeReceipt(
        menu: NSMenu,
        host: NSWindow,
        fixture: CodexWorkspacesNavigationFixture,
        controller: StatusItemController) -> [String: String]
    {
        let overviewRow = menu.items.first {
            ($0.representedObject as? String) == "overviewRow-codex"
        }?.view as? MenuRowContainerView
        let contentHost = overviewRow?.subviews.last
        let statusItem = menu.items.first { $0.title == L("Status Page") }
        let submenu = statusItem?.submenu
        return [
            "outerVibrancy": String(overviewRow?.allowsVibrancy ?? false),
            "innerVibrancy": String(contentHost?.allowsVibrancy ?? false),
            "swiftUIHighlighted": String(overviewRow?.highlightState.isHighlighted ?? false),
            "pid": String(ProcessInfo.processInfo.processIdentifier),
            "window": String(host.windowNumber),
            "menuWindow": String(menu.items.compactMap { $0.view?.window?.windowNumber }.first ?? 0),
            "overviewLayout": fixture.settings.mergedOverviewLayout.rawValue,
            "selected": fixture.settings.selectedMenuProvider?.rawValue ?? "none",
            "overview": String(fixture.settings.mergedMenuLastSelectedWasOverview),
            "highlighted": menu.highlightedItem?.representedObject as? String ?? "none",
            "overviewSubmenus": String(menu.items.count(where: {
                ($0.representedObject as? String)?.hasPrefix("overviewRow-") == true && $0.submenu != nil
            })),
            "statusProvider": submenu?.items.first?.toolTip
                ?? submenu?.items.last?.identifier?.rawValue ?? "website-only",
            "cachedSelections": String(controller.mergedSwitcherContentCaches[ObjectIdentifier(menu)]?
                .count ?? 0),
        ]
    }

    private static func measureHighlights(in menu: NSMenu, host: NSWindow, directory: URL) throws {
        let item = try XCTUnwrap(menu.items.first { ($0.representedObject as? String) == "overviewRow-codex" })
        let row = try XCTUnwrap(item.view as? MenuRowContainerView)
        let width = max(300, row.frame.width)
        let size = NSSize(width: width, height: row.measuredHeight(width: width))
        host.setContentSize(size)
        host.contentView = row
        row.frame = NSRect(origin: .zero, size: size)
        row.layoutSubtreeIfNeeded()
        row.displayIfNeeded()
        CATransaction.flush()
        func toggle(_ selected: Bool) -> Double {
            let start = DispatchTime.now().uptimeNanoseconds
            row.setHighlighted(selected)
            row.layoutSubtreeIfNeeded()
            row.displayIfNeeded()
            CATransaction.flush()
            _ = RunLoop.main.run(mode: .default, before: Date())
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        }
        let first = toggle(true)
        var samples: [Double] = []
        var swiftUIChanges = 0
        for index in 0..<200 {
            samples.append(autoreleasepool { toggle(index % 2 != 0) })
            if row.highlightState.isHighlighted { swiftUIChanges += 1 }
        }
        let sorted = samples.sorted()
        let receipt: [String: Any] = [
            "firstMilliseconds": first,
            "averageMilliseconds": samples.reduce(0, +) / Double(samples.count),
            "p95Milliseconds": sorted[189],
            "maxMilliseconds": sorted[199],
            "toggles": samples.count,
            "samplesMilliseconds": samples,
            "swiftUIHighlightChanges": swiftUIChanges,
            "outerVibrancy": row.allowsVibrancy,
            "innerVibrancy": row.subviews.last?.allowsVibrancy ?? false,
        ]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("benchmark.json"), options: .atomic)
    }

    private static func seedCompactAccounts(in fixture: CodexWorkspacesNavigationFixture) {
        fixture.settings.multiAccountMenuLayout = .stacked
        for index in 0..<5 {
            fixture.settings.addTokenAccount(
                provider: .claude, label: "Synthetic Account \(index + 1)", token: "fixture-oauth-\(index)")
        }
        fixture.settings.setActiveTokenAccountIndex(0, for: .claude)
        let accounts = fixture.settings.tokenAccounts(for: .claude)
        let now = Date()
        fixture.store.accountSnapshots[.claude] = accounts.enumerated().map { index, account in
            TokenAccountUsageSnapshot(
                account: account,
                snapshot: UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: index == 0 ? 20 : Double(99 - index),
                        windowMinutes: 300,
                        resetsAt: now.addingTimeInterval(Double(index + 1) * 3600),
                        resetDescription: nil),
                    secondary: RateWindow(
                        usedPercent: Double(85 - index * 5),
                        windowMinutes: 10080,
                        resetsAt: now.addingTimeInterval(Double(index + 1) * 86400),
                        resetDescription: nil),
                    updatedAt: now),
                error: nil,
                sourceLabel: "synthetic",
                cacheKey: fixture.store.tokenAccountSnapshotCacheKey(provider: .claude, account: account))
        }
    }

    private static func seedOverviewHistory(in fixture: CodexWorkspacesNavigationFixture) {
        fixture.settings.costUsageEnabled = true
        fixture.settings.costSummaryDisplayStyle = .both
        let now = Date()
        let day = CostUsageScanner.CostUsageDayRange.dayKey(from: now)
        for provider in [UsageProvider.claude, .codex] {
            fixture.store._setTokenSnapshotForTesting(
                CostUsageTokenSnapshot(
                    sessionTokens: 100,
                    sessionCostUSD: 1.5,
                    last30DaysTokens: 100,
                    last30DaysCostUSD: 1.5,
                    daily: [.init(
                        date: day,
                        inputTokens: 70,
                        outputTokens: 30,
                        totalTokens: 100,
                        costUSD: 1.5,
                        modelsUsed: nil,
                        modelBreakdowns: nil)],
                    updatedAt: now),
                provider: provider)
        }
    }
}

@MainActor
private final class StatusProviderProofButton: NSButton {
    var proofMenu: NSMenu?

    @objc func openMenu() {
        self.proofMenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: self.bounds.maxY), in: self)
    }
}
