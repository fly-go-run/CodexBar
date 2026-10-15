import CodexBarCore
import Foundation

extension UsageStore {
    /// Speed scans only parse what was appended to the session logs, but still walk the log tree.
    static let tokenOutputSpeedMinInterval: TimeInterval = 30

    func tokenOutputSpeed(for provider: UsageProvider) -> TokenOutputSpeedSnapshot? {
        self.tokenOutputSpeeds[provider.instanceID]
    }

    /// Runs beside the cost refresh rather than inside it: cost snapshots are TTL-cached for a
    /// long time, while speed is only interesting while requests are happening.
    ///
    /// At most one scan per provider is in flight; requests that arrive meanwhile are dropped (the next
    /// refresh tick asks again), and the minimum interval counts from the end of the previous scan.
    func scheduleTokenOutputSpeedRefresh(for provider: UsageProvider, now: Date = Date()) {
        guard provider == .claude || provider == .codex else { return }
        let id = provider.instanceID
        guard self.tokenOutputSpeedScanTasks[id] == nil else { return }
        if let last = self.tokenOutputSpeedScanStartedAt[id],
           now.timeIntervalSince(last) >= 0,
           now.timeIntervalSince(last) < Self.tokenOutputSpeedMinInterval
        {
            return
        }
        self.tokenOutputSpeedScanStartedAt[id] = now
        let codexHomePath = self.tokenCostScope(for: provider).codexHomePath
        self.tokenOutputSpeedScanTasks[id] = Task { [weak self] in
            let scan = Task.detached(priority: .utility) {
                try TokenOutputSpeedScanner.shared.snapshot(provider: provider, codexHomePath: codexHomePath)
            }
            let result: Result<TokenOutputSpeedSnapshot?, Error> = await withTaskCancellationHandler {
                await scan.result
            } onCancel: {
                scan.cancel()
            }
            guard let self else { return }
            self.tokenOutputSpeedScanTasks[id] = nil
            // The floor runs from when the scan finished, so a slow scan is never followed by another at once.
            self.tokenOutputSpeedScanStartedAt[id] = Date()
            guard case let .success(snapshot) = result else { return }
            let summary = snapshot?.models.map { "\($0.model ?? "?")=\(Int($0.tokensPerSecond))" }
                .joined(separator: ",") ?? "none"
            self.tokenCostLogger.debug("output speed provider=\(provider.rawValue) \(summary)")
            if self.tokenOutputSpeeds[id] != snapshot {
                self.tokenOutputSpeeds[id] = snapshot
            }
        }
    }
}

/// Presentation of the output-speed block: one headline rate plus a quiet per-model line.
struct TokenSpeedSummary: Equatable {
    struct Row: Equatable {
        let name: String
        let value: String
    }

    let title: String
    let value: String
    /// Per-model 24h rates, numbers only ("96"); the unit lives on the headline.
    let rows: [Row]
    /// How much slower the last hour ran than the 24h average, when that is worth flagging.
    let slowdownPercent: Int?

    var rowsLine: String? {
        guard !self.rows.isEmpty else { return nil }
        return (["24h"] + self.rows.map { "\($0.name) \($0.value)" }).joined(separator: " · ")
    }

    var slowdownText: String? {
        self.slowdownPercent.map { "↓\($0)%" }
    }

    var slowdownHelp: String? {
        self.slowdownPercent.map { L("token_speed_slowdown_help", "\($0)") }
    }

    /// Single-line form for text-only surfaces (cost section, provider details, tooltips).
    var compactLine: String {
        let headline = [self.title, self.value, self.slowdownText].compactMap(\.self).joined(separator: " ")
        return ([headline] + [self.rowsLine].compactMap(\.self)).joined(separator: " · ")
    }
}

extension UsageMenuCardView.Model {
    /// The last hour is the "how fast is it right now" number; below this many requests it is too
    /// noisy and the 24h rate takes over.
    static let tokenSpeedLastHourMinimumRequests = 3
    static let tokenSpeedMaximumRows = 3
    /// Flag the last hour only when it is clearly slower than the 24h average.
    static let tokenSpeedSlowdownThreshold = 0.2

    static func tokenSpeedSummary(_ snapshot: TokenOutputSpeedSnapshot?) -> TokenSpeedSummary? {
        guard let snapshot, !snapshot.models.isEmpty else { return nil }
        let dayRate = Self.combinedTokensPerSecond(snapshot.models)
        let lastHourRate = (snapshot.lastHour?.requestCount ?? 0) >= Self.tokenSpeedLastHourMinimumRequests
            ? snapshot.lastHour?.tokensPerSecond : nil
        let slowdown: Int? = if let lastHourRate, dayRate > 0,
                                lastHourRate < dayRate * (1 - Self.tokenSpeedSlowdownThreshold)
        {
            Int(((1 - lastHourRate / dayRate) * 100).rounded())
        } else {
            nil
        }
        // With one model and no last-hour headline, its row would just repeat the headline.
        let rows = lastHourRate != nil || snapshot.models.count > 1
            ? snapshot.models.prefix(Self.tokenSpeedMaximumRows).map {
                TokenSpeedSummary.Row(
                    name: Self.tokenSpeedModelName($0.model ?? ""),
                    value: String(format: "%.0f", $0.tokensPerSecond))
            }
            : []
        return TokenSpeedSummary(
            title: L(lastHourRate != nil ? "token_speed_title_last_hour" : "token_speed_title_24h"),
            value: String(format: "%.0f tok/s", lastHourRate ?? dayRate),
            rows: rows,
            slowdownPercent: slowdown)
    }

    static func tokenOutputSpeedLines(_ snapshot: TokenOutputSpeedSnapshot?) -> [String] {
        self.tokenSpeedSummary(snapshot).map { [$0.compactLine] } ?? []
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

    private static func combinedTokensPerSecond(_ buckets: [TokenOutputSpeedSnapshot.Bucket]) -> Double {
        let seconds = buckets.reduce(0) { $0 + $1.seconds }
        return seconds > 0 ? Double(buckets.reduce(0) { $0 + $1.outputTokens }) / seconds : 0
    }
}
