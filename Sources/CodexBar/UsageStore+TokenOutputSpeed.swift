import CodexBarCore
import Foundation

extension UsageStore {
    /// Speed scans only re-read session files that changed, but still walk the log tree.
    static let tokenOutputSpeedMinInterval: TimeInterval = 30

    func tokenOutputSpeed(for provider: UsageProvider) -> TokenOutputSpeedSnapshot? {
        self.tokenOutputSpeeds[provider.instanceID]
    }

    /// Runs beside the cost refresh rather than inside it: cost snapshots are TTL-cached for a
    /// long time, while speed is only interesting while requests are happening.
    func scheduleTokenOutputSpeedRefresh(for provider: UsageProvider, now: Date = Date()) {
        guard provider == .claude || provider == .codex else { return }
        let id = provider.instanceID
        if let last = self.tokenOutputSpeedScanStartedAt[id],
           now.timeIntervalSince(last) >= 0,
           now.timeIntervalSince(last) < Self.tokenOutputSpeedMinInterval
        {
            return
        }
        self.tokenOutputSpeedScanStartedAt[id] = now
        let codexHomePath = self.tokenCostScope(for: provider).codexHomePath
        Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                TokenOutputSpeedScanner.shared.snapshot(provider: provider, codexHomePath: codexHomePath)
            }.value
            guard let self else { return }
            let summary = snapshot?.models.map { "\($0.model ?? "?")=\(Int($0.tokensPerSecond))" }
                .joined(separator: ",") ?? "none"
            self.tokenCostLogger.debug("output speed provider=\(provider.rawValue) \(summary)")
            if self.tokenOutputSpeeds[id] != snapshot {
                self.tokenOutputSpeeds[id] = snapshot
            }
        }
    }
}

extension UsageMenuCardView.Model {
    static func tokenOutputSpeedLines(_ snapshot: TokenOutputSpeedSnapshot?) -> [String] {
        guard let snapshot, !snapshot.models.isEmpty else { return [] }
        let models = snapshot.models.prefix(2).map { bucket in
            "\(Self.tokenOutputSpeedModelName(bucket.model ?? "")) \(Self.tokensPerSecondText(bucket.tokensPerSecond))"
        }
        var lines = [String(format: L("token_speed_window_line"), models.joined(separator: " · ") + " tok/s")]
        if let lastHour = snapshot.lastHour {
            lines.append(String(
                format: L("token_speed_last_hour_line"),
                Self.tokensPerSecondText(lastHour.tokensPerSecond),
                "\(lastHour.requestCount)"))
        }
        return lines
    }

    static func tokenOutputSpeedModelName(_ raw: String) -> String {
        let name = UsageFormatter.modelDisplayName(raw)
        return name.hasPrefix("claude-") ? String(name.dropFirst("claude-".count)) : name
    }

    private static func tokensPerSecondText(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}
