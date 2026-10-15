import CodexBarCore
import Foundation

extension UsageStore {
    /// #2899: the startup version probe runs in a detached background task, where the Claude
    /// opaque-child gate denies `claude --version` on a cold profile. A manual refresh is user-initiated,
    /// so the gate allows the probe; run only the Claude version probe once per manual refresh while the
    /// version is still missing, whatever usage source the refresh ends up using (OAuth, CLI or web).
    func refreshMissingClaudeVersionForUserInitiatedRefresh(provider: UsageProvider) {
        // Provider-specific by design: only Claude's version probe is background-gated.
        guard provider == .claude,
              ProviderInteractionContext.current == .userInitiated,
              self.versions[provider.instanceID] == nil,
              self.claudeVersionRefreshTask == nil,
              let implementation = ProviderCatalog.all.first(where: { $0.id == .claude })
        else { return }
        let context = ProviderVersionContext(provider: .claude, browserDetection: self.browserDetection)
        // Unstructured (not detached) so the user-initiated interaction task-local is inherited.
        self.claudeVersionRefreshTask = Task { @MainActor [weak self] in
            let version = await implementation.detectVersion(context: context)
            guard let self else { return }
            self.claudeVersionRefreshTask = nil
            guard let version, !version.isEmpty else { return }
            self.versions[UsageProvider.claude.instanceID] = version
            self.claudeBinaryResolvedWithoutVersion = false
        }
    }
}
