import CodexBarCore
import Foundation

@MainActor
enum ClaudeUIErrorMapper {
    static func userFacingMessage(
        _ raw: String?,
        staleSnapshotUpdatedAt: Date?,
        keychainAccessDisabled: Bool = KeychainAccessGate.isExplicitlyDisabled,
        safariNeedsFullDiskAccess: () -> Bool = { false },
        localize: (String) -> String = L) -> String?
    {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let missingCredentials = [
            ClaudeOAuthCredentialsError.missingAccessToken,
            .missingOAuth,
            .notFound,
        ].contains { $0.localizedDescription == trimmed }
        // With Keychain disabled, Safari web is the preferred source; when it is unreadable, the actionable fix is
        // Full Disk Access rather than the Keychain setting itself.
        let message = if keychainAccessDisabled, missingCredentials, safariNeedsFullDiskAccess() {
            localize("claude_safari_full_disk_access_required")
        } else if keychainAccessDisabled, missingCredentials {
            localize("claude_oauth_keychain_access_disabled")
        } else if trimmed == ClaudeOAuthCredentialsError.keychainAccessRevoked.localizedDescription {
            localize("claude_oauth_keychain_access_revoked")
        } else {
            trimmed
        }
        guard let staleSnapshotUpdatedAt else { return message }
        return message + " " + LastKnownUsagePresentation.message(
            capturedAt: staleSnapshotUpdatedAt,
            localize: localize)
    }
}
