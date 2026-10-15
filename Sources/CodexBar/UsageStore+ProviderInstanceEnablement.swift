import CodexBarCore
import Foundation

@MainActor
extension UsageStore {
    func isEnabledProviderInstance(_ instanceID: ProviderInstanceID, now: Date) -> Bool {
        guard let provider = instanceID.firstPartyProvider else { return false }
        return self.isProviderAvailable(provider, now: now)
    }
}
