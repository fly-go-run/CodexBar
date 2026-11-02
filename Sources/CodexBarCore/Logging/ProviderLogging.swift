public enum ProviderLogging {
    public static func logStartupState(
        logger: CodexBarLogger,
        providers: [UsageProvider],
        isEnabled: (UsageProvider) -> Bool,
        modeSnapshot: [String: String])
    {
        let ordered = providers.sorted { $0.rawValue < $1.rawValue }
        let states = ordered
            .map { provider -> String in
                let enabled = isEnabled(provider)
                return "\(provider.rawValue)=\(enabled ? "1" : "0")"
            }
            .joined(separator: ",")
        let enabledProviders = ordered
            .filter { isEnabled($0) }
            .map(\.rawValue)
            .joined(separator: ",")
        logger.info(
            "Provider enablement at startup",
            metadata: [
                "states": states,
                "enabled": enabledProviders.isEmpty ? "none" : enabledProviders,
            ])
        logger.info("Provider mode snapshot", metadata: modeSnapshot)
    }

    /// Records a refresh failure that reached the menu. Warning level so the unified log persists it
    /// even when file logging is off and info-level fetch details have already been dropped.
    public static func logSurfacedRefreshFailure( // swiftlint:disable:this function_parameter_count
        logger: CodexBarLogger,
        provider: ProviderInstanceID,
        status: String,
        message: String,
        attempts: [ProviderFetchAttempt],
        keptPriorData: Bool)
    {
        var metadata = [
            "provider": provider.rawValue,
            "status": status,
            "error": self.clippedForLog(message),
            "keptPriorData": keptPriorData ? "1" : "0",
        ]
        if !attempts.isEmpty {
            metadata["attempts"] = attempts
                .map { "\($0.strategyID)=\($0.outcome.rawValue)" }
                .joined(separator: ",")
        }
        // Fallback pipelines surface only the last failure; earlier strategies often explain it.
        let earlierFailures = attempts
            .compactMap { attempt -> String? in
                guard let description = attempt.errorDescription, description != message else { return nil }
                return "\(attempt.strategyID): \(self.clippedForLog(description))"
            }
        if !earlierFailures.isEmpty {
            metadata["attemptErrors"] = earlierFailures.joined(separator: " | ")
        }
        logger.warning("Provider refresh failed", metadata: metadata)
    }

    static let maxLoggedErrorLength = 240

    static func clippedForLog(_ text: String) -> String {
        guard text.count > self.maxLoggedErrorLength else { return text }
        return String(text.prefix(self.maxLoggedErrorLength)) + "…"
    }
}
