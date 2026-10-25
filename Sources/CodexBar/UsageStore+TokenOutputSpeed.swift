import CodexBarCore
import Foundation

typealias TokenOutputSpeedScanOverride = @Sendable (UsageProvider, String?) async throws -> TokenOutputSpeedSnapshot?

extension UsageStore {
    /// Speed scans only parse what was appended to the session logs, but still walk the log tree.
    static let tokenOutputSpeedMinInterval: TimeInterval = 30

    /// What a speed scan reads from: results are only valid for the scope that was active when they ran.
    struct TokenOutputSpeedScope: Equatable, Sendable {
        let codexHomePath: String?
        let signature: String
    }

    /// Per-provider scan bookkeeping.
    struct TokenOutputSpeedScheduleState {
        /// A request arrived that no scan has started for yet.
        var pending = false
        var lastFinishedAt: Date?
        /// The scope the published speeds were measured for.
        var publishedScope: TokenOutputSpeedScope?
    }

    /// Speeds measured for another scope (for example before a Codex home switch) are never shown, even
    /// before the next scan has replaced them.
    func tokenOutputSpeed(for provider: UsageProvider) -> TokenOutputSpeedSnapshot? {
        let id = provider.instanceID
        guard let snapshot = self.tokenOutputSpeeds[id],
              self.tokenOutputSpeedSchedule[id]?.publishedScope == self.tokenOutputSpeedScope(for: provider)
        else { return nil }
        return snapshot
    }

    /// Runs beside the cost refresh rather than inside it: cost snapshots are TTL-cached for a
    /// long time, while speed is only interesting while requests are happening.
    ///
    /// At most one scan loop per provider exists. A request that arrives while a scan runs (or while
    /// the loop waits out the minimum interval) is remembered and answered by one trailing scan with the
    /// latest scope, so it is never lost even in manual refresh mode where no timer will ask again.
    func scheduleTokenOutputSpeedRefresh(for provider: UsageProvider, now: Date = Date()) {
        guard provider == .claude || provider == .codex else { return }
        let id = provider.instanceID
        self.tokenOutputSpeedSchedule[id, default: .init()].pending = true
        guard self.tokenOutputSpeedScanTasks[id] == nil else { return }
        self.tokenOutputSpeedScanTasks[id] = Task { [weak self] in
            await self?.runTokenOutputSpeedScans(for: provider, firstRequestAt: now)
        }
    }

    private func tokenOutputSpeedScope(for provider: UsageProvider) -> TokenOutputSpeedScope {
        let scope = self.tokenCostScope(for: provider)
        let codexHomePath = self._test_tokenOutputSpeedCodexHomePath?(provider) ?? scope.codexHomePath
        return TokenOutputSpeedScope(codexHomePath: codexHomePath, signature: scope.signature)
    }

    private func runTokenOutputSpeedScans(for provider: UsageProvider, firstRequestAt: Date) async {
        let id = provider.instanceID
        var requestedAt: Date? = firstRequestAt
        while !Task.isCancelled {
            // The floor runs from the end of the previous scan, so a slow scan is never followed by another
            // at once; a request inside the floor waits for its deadline instead of being dropped.
            if let finished = self.tokenOutputSpeedSchedule[id]?.lastFinishedAt {
                let elapsed = (requestedAt ?? Date()).timeIntervalSince(finished)
                if elapsed >= 0, elapsed < self.tokenOutputSpeedMinInterval {
                    do {
                        try await Task.sleep(for: .seconds(self.tokenOutputSpeedMinInterval - elapsed))
                    } catch {
                        break
                    }
                }
            }
            requestedAt = nil
            // The scope is read when the scan starts and compared again when it ends: a switch in between
            // (which may not have scheduled anything itself) makes the result stale.
            let scope = self.tokenOutputSpeedScope(for: provider)
            self.tokenOutputSpeedSchedule[id, default: .init()].pending = false
            let result = await self.scanTokenOutputSpeed(provider: provider, scope: scope)
            self.tokenOutputSpeedSchedule[id, default: .init()].lastFinishedAt = Date()
            if scope != self.tokenOutputSpeedScope(for: provider) {
                self.tokenOutputSpeeds[id] = nil
                self.tokenOutputSpeedSchedule[id, default: .init()].publishedScope = nil
                self.tokenOutputSpeedSchedule[id, default: .init()].pending = true
            } else if case let .success(snapshot) = result {
                let summary = snapshot?.models.map { "\($0.model ?? "?")=\(Int($0.tokensPerSecond))" }
                    .joined(separator: ",") ?? "none"
                self.tokenCostLogger.debug("output speed provider=\(provider.rawValue) \(summary)")
                self.tokenOutputSpeedSchedule[id, default: .init()].publishedScope = scope
                if self.tokenOutputSpeeds[id] != snapshot {
                    self.tokenOutputSpeeds[id] = snapshot
                }
            }
            // Checked without suspending, so a request cannot slip in between.
            if self.tokenOutputSpeedSchedule[id]?.pending != true { break }
        }
        self.tokenOutputSpeedScanTasks[id] = nil
    }

    private func scanTokenOutputSpeed(
        provider: UsageProvider,
        scope: TokenOutputSpeedScope) async -> Result<TokenOutputSpeedSnapshot?, Error>
    {
        if let override = self._test_tokenOutputSpeedScan {
            do {
                return try await .success(override(provider, scope.codexHomePath))
            } catch {
                return .failure(error)
            }
        }
        let codexHomePath = scope.codexHomePath
        let scan = Task.detached(priority: .utility) {
            try TokenOutputSpeedScanner.shared.snapshot(provider: provider, codexHomePath: codexHomePath)
        }
        return await withTaskCancellationHandler {
            await scan.result
        } onCancel: {
            scan.cancel()
        }
    }
}

/// Presentation of the output-speed block: one row per model doing a real share of the work, each with its
/// own rate, so a number is never a blend of models.
struct TokenSpeedSummary: Equatable {
    struct Row: Equatable {
        let model: String
        let value: String
        /// Set when this model had too few requests in the last hour and shows its 24h rate instead.
        let windowNote: String?
        /// How much slower the last hour ran than this model's 24h average, when that is worth flagging.
        let slowdownPercent: Int?
        /// The headline rate behind `value`, for the card's large number.
        var rate: Double = 0
        /// One sentence under the rate comparing it with the model's 24h average; nil when the rate already
        /// is the 24h average.
        var detail: String?
        /// Orange when the rate runs clearly below the average (the same cut as `slowdownPercent`).
        var detailIsWarning = false
        /// The figures behind the row (median request, request counts), kept out of the card itself.
        var help: String?
        /// Rates of the most recent active periods, oldest first.
        var trend: [Double] = []
        /// The model's 24h average, drawn as the trend's reference line.
        var baseline: Double?

        var slowdownText: String? {
            self.slowdownPercent.map { "↓\($0)%" }
        }

        var slowdownHelp: String? {
            self.slowdownPercent.map { L("token_speed_slowdown_help", "\($0)") }
        }

        var rateText: String {
            String(format: "%.0f", self.rate)
        }

        var compactText: String {
            [self.model, self.windowNote.map { "(\($0))" }, self.value, self.slowdownText]
                .compactMap(\.self)
                .joined(separator: " ")
        }
    }

    let title: String
    /// Largest output first; never empty.
    let rows: [Row]
    /// Card heading without the window, which the card shows on the right with the request count.
    var heading: String = L("token_speed_heading")
    var windowLabel: String = ""
    /// Measurable requests behind the block in its window.
    var requestCount = 0

    /// "近 1 小时 · 42 次请求"
    var windowSummary: String {
        let requests = self.requestCount > 0
            ? L("token_speed_requests", codexBarLocalizedInteger(self.requestCount))
            : nil
        return [self.windowLabel, requests]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    /// Text-only surfaces (cost section, provider details, tooltips) show one line per model, the title only
    /// on the first.
    var lines: [String] {
        self.rows.enumerated().map { index, row in
            index == 0 ? "\(self.title) · \(row.compactText)" : row.compactText
        }
    }
}

extension UsageMenuCardView.Model {
    /// The last hour is the "how fast is it right now" number; below this many requests it is too
    /// noisy and the 24h rate takes over.
    static let tokenSpeedLastHourMinimumRequests = 3
    /// Flag the last hour only when it is clearly slower than the 24h average.
    static let tokenSpeedSlowdownThreshold = 0.2
    /// Within this the last hour reads as "same as usual" rather than a percentage.
    static let tokenSpeedSteadyThreshold = 0.05
    /// Models below this share of the window's output (background title or summary calls, a one-off
    /// switch) are left out so they do not crowd the block.
    static let tokenSpeedMinimumOutputShare = 0.1
    static let tokenSpeedMaximumRows = 3

    /// Lists the models of the last hour while at least one of them has enough requests there for a stable
    /// number; a listed model with too few of its own falls back to its 24h rate, marked as such. Otherwise
    /// the block lists the models of the last 24h.
    static func tokenSpeedSummary(_ snapshot: TokenOutputSpeedSnapshot?) -> TokenSpeedSummary? {
        guard let snapshot, !snapshot.models.isEmpty else { return nil }
        let dayBuckets = Dictionary(
            snapshot.models.map { ($0.model ?? "", $0) },
            uniquingKeysWith: { first, _ in first })
        let hourModels = Self.tokenSpeedListedBuckets(snapshot.lastHourModels)
        guard hourModels.contains(where: { $0.requestCount >= Self.tokenSpeedLastHourMinimumRequests }) else {
            let rows = Self.tokenSpeedListedBuckets(snapshot.models).map { bucket in
                Self.tokenSpeedRow(
                    bucket: bucket,
                    dayBucket: nil,
                    trend: snapshot.recentRates[bucket.model ?? ""] ?? [],
                    windowNote: nil,
                    slowdown: nil)
            }
            return TokenSpeedSummary(
                title: L("token_speed_title_24h"),
                rows: rows,
                windowLabel: L("token_speed_window_24h"),
                requestCount: snapshot.models.reduce(0) { $0 + $1.requestCount })
        }
        let rows = hourModels.map { bucket -> TokenSpeedSummary.Row in
            let key = bucket.model ?? ""
            let dayBucket = dayBuckets[key]
            let trend = snapshot.recentRates[key] ?? []
            guard bucket.requestCount >= Self.tokenSpeedLastHourMinimumRequests, let dayBucket else {
                return Self.tokenSpeedRow(
                    bucket: dayBucket ?? bucket,
                    dayBucket: nil,
                    trend: trend,
                    windowNote: L("token_speed_window_24h"),
                    slowdown: nil)
            }
            return Self.tokenSpeedRow(
                bucket: bucket,
                dayBucket: dayBucket,
                trend: trend,
                windowNote: nil,
                slowdown: Self.tokenSpeedSlowdown(rate: bucket.tokensPerSecond, average: dayBucket.tokensPerSecond))
        }
        return TokenSpeedSummary(
            title: L("token_speed_title_last_hour"),
            rows: rows,
            windowLabel: L("token_speed_window_last_hour"),
            requestCount: snapshot.lastHour?.requestCount ?? 0)
    }

    static let tokenSpeedAllModelsMaximumRows = 8

    /// Every model of the last 24h for the cost submenu, where there is room for the ones the card leaves out.
    /// A model with enough requests in the last hour shows that rate against its 24h average; the rest show
    /// their 24h rate. Each row's detail says which window it is and how many requests are behind it.
    static func tokenSpeedAllModelsSummary(_ snapshot: TokenOutputSpeedSnapshot?) -> TokenSpeedSummary? {
        guard let snapshot, !snapshot.models.isEmpty else { return nil }
        let hourBuckets = Dictionary(
            snapshot.lastHourModels.map { ($0.model ?? "", $0) },
            uniquingKeysWith: { first, _ in first })
        let rows = snapshot.models.prefix(Self.tokenSpeedAllModelsMaximumRows).map { dayBucket in
            let key = dayBucket.model ?? ""
            let trend = snapshot.recentRates[key] ?? []
            guard let hourBucket = hourBuckets[key],
                  hourBucket.requestCount >= Self.tokenSpeedLastHourMinimumRequests
            else {
                var row = Self.tokenSpeedRow(
                    bucket: dayBucket,
                    dayBucket: nil,
                    trend: trend,
                    windowNote: nil,
                    slowdown: nil)
                row.detail = [
                    L("token_speed_window_24h"),
                    L("token_speed_requests", codexBarLocalizedInteger(dayBucket.requestCount)),
                ].joined(separator: " · ")
                return row
            }
            var row = Self.tokenSpeedRow(
                bucket: hourBucket,
                dayBucket: dayBucket,
                trend: trend,
                windowNote: nil,
                slowdown: Self.tokenSpeedSlowdown(
                    rate: hourBucket.tokensPerSecond,
                    average: dayBucket.tokensPerSecond))
            row.detail = [
                L("token_speed_window_last_hour"),
                Self.tokenSpeedComparison(rate: hourBucket.tokensPerSecond, average: dayBucket.tokensPerSecond),
                L("token_speed_requests", codexBarLocalizedInteger(hourBucket.requestCount)),
            ].joined(separator: " · ")
            return row
        }
        return TokenSpeedSummary(
            title: L("token_speed_title_24h"),
            rows: Array(rows),
            windowLabel: L("token_speed_window_24h"),
            requestCount: snapshot.models.reduce(0) { $0 + $1.requestCount })
    }

    /// The leader always stays; the rest need their share of the window's output.
    private static func tokenSpeedListedBuckets(
        _ buckets: [TokenOutputSpeedSnapshot.Bucket]) -> [TokenOutputSpeedSnapshot.Bucket]
    {
        let total = buckets.reduce(0) { $0 + $1.outputTokens }
        return Array(buckets.enumerated()
            .filter { index, bucket in
                index == 0 || Double(bucket.outputTokens) >= Double(total) * Self.tokenSpeedMinimumOutputShare
            }
            .map(\.element)
            .prefix(Self.tokenSpeedMaximumRows))
    }

    /// `bucket` is the window the headline rate comes from; `dayBucket` is the 24h average it is compared
    /// with, nil when the headline already is the 24h rate.
    private static func tokenSpeedRow(
        bucket: TokenOutputSpeedSnapshot.Bucket,
        dayBucket: TokenOutputSpeedSnapshot.Bucket?,
        trend: [Double],
        windowNote: String?,
        slowdown: Int?) -> TokenSpeedSummary.Row
    {
        let rate = bucket.tokensPerSecond
        let windowFigures = L(
            "token_speed_help_window",
            dayBucket != nil ? L("token_speed_window_last_hour") : L("token_speed_window_24h"),
            String(format: "%.0f", bucket.medianTokensPerSecond),
            codexBarLocalizedInteger(bucket.requestCount))
        let help = [
            windowFigures,
            dayBucket.map { L("token_speed_help_day", String(format: "%.0f", $0.tokensPerSecond)) },
            L("token_speed_help_end_to_end"),
        ].compactMap(\.self).joined(separator: "\n")
        return TokenSpeedSummary.Row(
            model: self.tokenSpeedModelName(bucket.model ?? ""),
            value: String(format: "%.0f tok/s", rate),
            windowNote: windowNote,
            slowdownPercent: slowdown,
            rate: rate,
            detail: dayBucket.map { Self.tokenSpeedComparison(rate: rate, average: $0.tokensPerSecond) },
            detailIsWarning: slowdown != nil,
            help: help,
            trend: trend,
            baseline: (dayBucket ?? bucket).tokensPerSecond)
    }

    /// Percent the last hour ran below the 24h average, only once it is clearly slower.
    private static func tokenSpeedSlowdown(rate: Double, average: Double) -> Int? {
        guard average > 0, rate < average * (1 - self.tokenSpeedSlowdownThreshold) else { return nil }
        return Int(((1 - rate / average) * 100).rounded())
    }

    /// "比 24h 均值快 6%" / "与 24h 均值持平" / "比 24h 均值慢 18%".
    static func tokenSpeedComparison(rate: Double, average: Double) -> String {
        guard average > 0 else { return L("token_speed_vs_day_same") }
        let change = rate / average - 1
        guard abs(change) >= Self.tokenSpeedSteadyThreshold else { return L("token_speed_vs_day_same") }
        let percent = String(Int((abs(change) * 100).rounded()))
        return change > 0 ? L("token_speed_vs_day_faster", percent) : L("token_speed_vs_day_slower", percent)
    }

    static func tokenOutputSpeedLines(_ snapshot: TokenOutputSpeedSnapshot?) -> [String] {
        self.tokenSpeedSummary(snapshot)?.lines ?? []
    }

    /// `claude-opus-4-1` → `Opus 4.1`, `gpt-5-codex` → `GPT-5 Codex`; unknown shapes pass through.
    static func tokenSpeedModelName(_ raw: String) -> String {
        let name = UsageFormatter.modelDisplayName(raw)
        guard name == name.lowercased(), !name.contains(" ") else { return name }
        var parts = name.split(separator: "-").map(String.init)
        if parts.first == "gpt", parts.count >= 2 {
            let words = parts.dropFirst(2).map(\.capitalized)
            return (["GPT-\(parts[1])"] + words).joined(separator: " ")
        }
        if parts.first == "claude" { parts.removeFirst() }
        let version = parts.filter { $0.allSatisfy(\.isNumber) }
        let words = parts.filter { !$0.allSatisfy(\.isNumber) }.map(\.capitalized)
        guard !words.isEmpty else { return name }
        return (words + (version.isEmpty ? [] : [version.joined(separator: ".")])).joined(separator: " ")
    }
}
