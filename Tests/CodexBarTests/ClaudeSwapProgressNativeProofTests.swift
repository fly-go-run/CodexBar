import AppKit
import CodexBarCore
import Foundation
import XCTest
@testable import CodexBar

/// Opt-in, synthetic-only proof of account progress in a genuinely tracking, attached menu.
@MainActor
final class ClaudeSwapProgressNativeProofTests: XCTestCase {}

struct ClaudeSwapProgressNativeProofConfiguration {
    let output: URL
    let expectedActivating: String
    let expectedReconciling: String
    let expectedCompleted: String?
    let expectedHeading: String?

    init(path: String, environment: [String: String]) {
        self.output = URL(fileURLWithPath: path, isDirectory: true)
        let isBaseline = environment["CODEXBAR_CLAUDE_SWAP_PROGRESS_BASELINE"] == "1"
        self.expectedActivating = environment["CODEXBAR_CLAUDE_SWAP_PROGRESS_EXPECT_ACTIVATING"] ??
            (isBaseline ? "Loading…" : "Switching account…")
        self.expectedReconciling = environment["CODEXBAR_CLAUDE_SWAP_PROGRESS_EXPECT_RECONCILING"] ??
            (isBaseline ? "Loading…" : "Refreshing account status…")
        // Skipping candidate acceptance checks requires an explicit baseline run.
        self.expectedCompleted = isBaseline ? nil :
            (environment["CODEXBAR_CLAUDE_SWAP_PROGRESS_EXPECT_COMPLETED"] ?? "Active")
        self.expectedHeading = isBaseline ? nil :
            (environment["CODEXBAR_CLAUDE_SWAP_PROGRESS_EXPECT_HEADING"] ?? "Switch Claude Code account")
    }
}
