import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct ClaudeSwapSwitchErrorTimingTests {
    @MainActor
    private final class ProgressRecorder {
        var phases: [ClaudeSwapSwitchPhase?] = []
    }

    enum ConfigurationChange: CaseIterable, Equatable, Sendable {
        case unchanged
        case differentPath
        case disabledThenRestored
    }

    @MainActor
    private final class RefreshGate {
        var entered = false
        private var released = false
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            self.entered = true
            guard !self.released else { return }
            await withCheckedContinuation { self.continuation = $0 }
        }

        func release() {
            self.released = true
            self.continuation?.resume()
            self.continuation = nil
        }
    }
}
