import Testing
@testable import CodexBarCore

struct ProviderLoggingTests {
    @Test
    func `surfaced refresh failure logs a warning with the strategy trail`() {
        let recorder = LogRecorder()
        let logger = CodexBarLogger(minimumLevel: .info) { level, message, metadata in
            recorder.entries.append((level, message, metadata ?? [:]))
        }

        ProviderLogging.logSurfacedRefreshFailure(
            logger: logger,
            provider: UsageProvider.claude.instanceID,
            status: "timeout",
            message: "The request timed out.",
            attempts: [
                ProviderFetchAttempt(
                    strategyID: "claude.oauth",
                    kind: .oauth,
                    wasAvailable: false,
                    errorDescription: nil),
                ProviderFetchAttempt(
                    strategyID: "claude.web",
                    kind: .web,
                    wasAvailable: true,
                    errorDescription: "No Safari session cookie"),
                ProviderFetchAttempt(
                    strategyID: "claude.cli",
                    kind: .cli,
                    wasAvailable: true,
                    errorDescription: "The request timed out."),
            ],
            keptPriorData: true)

        #expect(recorder.entries.count == 1)
        let entry = recorder.entries[0]
        #expect(entry.level == .warning)
        #expect(entry.message == "Provider refresh failed")
        #expect(entry.metadata["provider"] == "claude")
        #expect(entry.metadata["status"] == "timeout")
        #expect(entry.metadata["error"] == "The request timed out.")
        #expect(entry.metadata["keptPriorData"] == "1")
        #expect(entry.metadata["attempts"] == "claude.oauth=skipped,claude.web=failed,claude.cli=failed")
        #expect(entry.metadata["attemptErrors"] == "claude.web: No Safari session cookie")
    }

    @Test
    func `surfaced refresh failure clips long errors and omits empty attempt fields`() {
        let recorder = LogRecorder()
        let logger = CodexBarLogger(minimumLevel: .info) { level, message, metadata in
            recorder.entries.append((level, message, metadata ?? [:]))
        }
        let longMessage = String(repeating: "x", count: ProviderLogging.maxLoggedErrorLength + 50)

        ProviderLogging.logSurfacedRefreshFailure(
            logger: logger,
            provider: UsageProvider.codex.instanceID,
            status: "network_error",
            message: longMessage,
            attempts: [],
            keptPriorData: false)

        let metadata = recorder.entries.first?.metadata ?? [:]
        #expect(metadata["error"]?.count == ProviderLogging.maxLoggedErrorLength + 1)
        #expect(metadata["error"]?.hasSuffix("…") == true)
        #expect(metadata["keptPriorData"] == "0")
        #expect(metadata["attempts"] == nil)
        #expect(metadata["attemptErrors"] == nil)
    }
}

private final class LogRecorder: @unchecked Sendable {
    var entries: [(level: CodexBarLog.Level, message: String, metadata: [String: String])] = []
}
