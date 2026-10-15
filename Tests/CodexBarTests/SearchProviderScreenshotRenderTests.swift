import AppKit
import SwiftUI
import XCTest
@testable import CodexBar
@testable import CodexBarCore

@MainActor
final class SearchProviderScreenshotRenderTests: XCTestCase {
    private static func balanceSnapshot(
        provider: UsageProvider,
        title: String,
        label: String,
        value: String,
        loginMethod: String) throws -> UsageSnapshot
    {
        try UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [ProviderDetailSection(title: title, rows: [.init(label: label, value: value)])],
            updatedAt: Date(timeIntervalSince1970: 1_789_700_000),
            identity: ProviderIdentitySnapshot(
                providerID: provider.instanceID, accountEmail: nil, accountOrganization: nil, loginMethod: loginMethod),
            dataConfidence: .exact)
    }
}
