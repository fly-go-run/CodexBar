import CodexBarCore
import Foundation

extension UsageStore {
    func shouldSurfaceProviderRefreshFailure(
        provider: UsageProvider,
        state: (hadPriorData: Bool, preservesPriorData: Bool, restoredClaudeHistory: Bool)) -> Bool
    {
        if state.restoredClaudeHistory { return true }
        return self.failureGates[provider.instanceID]?
            .shouldSurfaceError(onFailureWithPriorData: state.hadPriorData) ?? true
    }
}
