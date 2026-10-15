import Foundation

/// Closed first-party bootstrap list, in `UsageProvider` order. Runtime registrations remain owned by
/// `ProviderDescriptorRegistry.register(_:)`.
public enum ProviderManifest {
    public static let allDescriptors: [ProviderDescriptor] = [
        CodexProviderDescriptor.descriptor,
        ClaudeProviderDescriptor.descriptor,
    ]
}
