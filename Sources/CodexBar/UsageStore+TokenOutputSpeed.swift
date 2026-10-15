import CodexBarCore
import Foundation

extension UsageStore {
    /// Speed scans only parse what was appended to the session logs, but still walk the log tree.
    static let tokenOutputSpeedMinInterval: TimeInterval = 30

    /// What a speed scan reads from: results are only valid for the scope that was active when they ran.
    struct TokenOutputSpeedScope: Equatable, Sendable {
        let codexHomePath: String?
        let signature: String
    }

    func tokenOutputSpeed(for provider: UsageProvider) -> TokenOutputSpeedSnapshot? {
        self.tokenOutputSpeeds[provider.instanceID]
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
        let scope = self.tokenOutputSpeedScope(for: provider)
        if let previous = self.tokenOutputSpeedScopes[id], previous != scope {
            // The published numbers belong to the old scope.
            self.tokenOutputSpeeds[id] = nil
        }
        self.tokenOutputSpeedScopes[id] = scope
        self.tokenOutputSpeedScanPending.insert(id)
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
            if let finished = self.tokenOutputSpeedLastScanFinishedAt[id] {
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
            guard let scope = self.tokenOutputSpeedScopes[id] else { break }
            self.tokenOutputSpeedScanPending.remove(id)
            let result = await self.scanTokenOutputSpeed(provider: provider, scope: scope)
            self.tokenOutputSpeedLastScanFinishedAt[id] = Date()
            if case let .success(snapshot) = result, self.tokenOutputSpeedScopes[id] == scope {
                let summary = snapshot?.models.map { "\($0.model ?? "?")=\(Int($0.tokensPerSecond))" }
                    .joined(separator: ",") ?? "none"
                self.tokenCostLogger.debug("output speed provider=\(provider.rawValue) \(summary)")
                if self.tokenOutputSpeeds[id] != snapshot {
                    self.tokenOutputSpeeds[id] = snapshot
                }
            }
            // Checked and cleared without suspending, so a request cannot slip in between.
            if !self.tokenOutputSpeedScanPending.contains(id) { break }
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
