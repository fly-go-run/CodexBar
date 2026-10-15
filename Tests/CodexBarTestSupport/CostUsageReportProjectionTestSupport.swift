// SwiftBuild also compiles this test-support target for `swift build -c release`,
// where CodexBarCore is not built for testing.
#if DEBUG
import Foundation
@testable import CodexBarCore

extension CostUsageScanner {
    static func buildCodexSessionBreakdownsFromCache(
        cache: CostUsageCache,
        range: CostUsageDayRange,
        modelsDevCatalog: ModelsDevCatalog? = nil,
        modelsDevCacheRoot: URL? = nil,
        sessionRoots: [URL]? = nil,
        priorityTurns: [String: CodexPriorityTurnMetadata]? = nil,
        modelsDevCatalogLoader: (URL?) -> ModelsDevCatalog? = {
            CostUsagePricing.modelsDevCatalog(cacheRoot: $0)
        }) -> [CostUsageSessionBreakdown]
    {
        buildCodexReportProjectionsFromCache(
            cache: cache,
            range: range,
            modelsDevCatalog: modelsDevCatalog,
            modelsDevCacheRoot: modelsDevCacheRoot,
            sessionRoots: sessionRoots,
            includeProjects: false,
            priorityTurns: priorityTurns,
            modelsDevCatalogLoader: modelsDevCatalogLoader).sessions
    }

    static func buildCodexProjectBreakdownsFromCache(
        cache: CostUsageCache,
        range: CostUsageDayRange,
        modelsDevCatalog: ModelsDevCatalog? = nil,
        modelsDevCacheRoot: URL? = nil,
        priorityTurns: [String: CodexPriorityTurnMetadata]? = nil,
        modelsDevCatalogLoader: (URL?) -> ModelsDevCatalog? = {
            CostUsagePricing.modelsDevCatalog(cacheRoot: $0)
        }) -> [CostUsageProjectBreakdown]
    {
        buildCodexReportProjectionsFromCache(
            cache: cache,
            range: range,
            modelsDevCatalog: modelsDevCatalog,
            modelsDevCacheRoot: modelsDevCacheRoot,
            priorityTurns: priorityTurns,
            modelsDevCatalogLoader: modelsDevCatalogLoader).projects
    }
}

extension CostUsageStoreReadView {
    func projects(range: CostUsageScanner.CostUsageDayRange, cacheRoot: URL?) -> [CostUsageProjectBreakdown] {
        self.reports(range: range, cacheRoot: cacheRoot, roots: []).projects
    }

    func sessions(
        range: CostUsageScanner.CostUsageDayRange,
        cacheRoot: URL?,
        roots: [URL]) -> [CostUsageSessionBreakdown]
    {
        self.reports(range: range, cacheRoot: cacheRoot, roots: roots, includeProjects: false).sessions
    }
}
#endif
