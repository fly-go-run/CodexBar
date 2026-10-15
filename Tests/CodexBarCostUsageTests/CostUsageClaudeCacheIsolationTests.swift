import Foundation
import Testing
@testable import CodexBarCore
@testable import CodexBarTestSupport

struct CostUsageClaudeCacheFixtures: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool {
        true
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void) async throws
    {
        try await CostUsageClaudeCacheIO.withIsolatedCachesForTesting(operation: function)
    }
}

@Suite(CostUsageClaudeCacheFixtures())
struct CostUsageClaudeCacheIsolationTests {
    private typealias Fixture = CostUsageClaudeWriteAmplificationTests.Fixture
}
