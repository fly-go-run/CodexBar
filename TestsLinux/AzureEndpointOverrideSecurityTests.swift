import CodexBarCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

@Suite
struct AzureEndpointOverrideSecurityTests {


}

private enum CapturingTransportError: Error {
    case unexpectedRequest
}

private struct CapturingTransport: ProviderHTTPTransport {
    let handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await self.handler(request)
    }
}
