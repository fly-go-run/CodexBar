// SwiftBuild also compiles this test-support target for `swift build -c release`,
// where CodexBarCore is not built for testing.
#if DEBUG
import Foundation
@testable import CodexBarCore

actor ProviderHTTPTransportStub: ProviderHTTPTransport {
    private let handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private var recordedRequests: [URLRequest] = []

    init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.handler = handler
    }

    func requests() -> [URLRequest] {
        self.recordedRequests
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.recordedRequests.append(request)
        return try await self.handler(request)
    }
}
#endif
