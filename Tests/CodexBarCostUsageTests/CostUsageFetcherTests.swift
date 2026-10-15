import Foundation
import SQLite3
import Testing
@testable import CodexBarCore
@testable import CodexBarTestSupport

@Suite(.serialized)
struct CostUsageFetcherTests {
    @Test
    func `all time includes retained logs older than a year`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let old = try env.makeLocalNoon(year: 2024, month: 1, day: 31)
        let now = try env.makeLocalNoon(year: 2026, month: 2, day: 1)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: old,
            filename: "old.jsonl",
            tokens: 123)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: now,
            filename: "new.jsonl",
            tokens: 7)
        let options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"))
        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: now.addingTimeInterval(10),
            forceRefresh: true,
            historyDays: CostReportingPeriod.allTime.days(now: now),
            allowPricingRefresh: false,
            scannerOptions: options)
        #expect(snapshot.daily.map(\.date) == ["2024-01-31", "2026-02-01"])
        #expect(snapshot.last30DaysTokens == 130)
    }
}

extension CostUsageFetcherTests {
    @Test
    func `completed empty codex scan publishes known zero totals`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"))
        options.refreshMinIntervalSeconds = 0

        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            historyDays: 1,
            allowPricingRefresh: false,
            scannerOptions: options)

        #expect(snapshot.historyCoverageIsEstablished)
        #expect(snapshot.sessionTokens == 0)
        #expect(snapshot.sessionCostUSD == 0)
        #expect(snapshot.last30DaysTokens == 0)
        #expect(snapshot.last30DaysCostUSD == 0)
    }

    @Test
    func `codex history coverage follows pending catch up`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: day,
            filename: "bounded.jsonl",
            tokens: 42)

        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"),
            maxCodexSessionFileBytes: 1,
            maxCodexScanBytesPerRefresh: 1)
        options.refreshMinIntervalSeconds = 0

        let pending = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            historyDays: 1,
            allowPricingRefresh: false,
            scannerOptions: options)
        #expect(!pending.historyCoverageIsEstablished)

        options.maxCodexSessionFileBytes = 0
        options.maxCodexScanBytesPerRefresh = 0
        let covered = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day.addingTimeInterval(1),
            historyDays: 1,
            allowPricingRefresh: false,
            scannerOptions: options)
        #expect(covered.historyCoverageIsEstablished)
    }

    @Test
    func `fetcher refreshes codex cache when history window expands`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let oldDay = try env.makeLocalNoon(year: 2026, month: 4, day: 2)
        let newDay = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: oldDay,
            filename: "old.jsonl",
            tokens: 15)
        try Self.writeCodexSessionFile(
            homeRoot: env.codexHomeRoot,
            env: env,
            day: newDay,
            filename: "new.jsonl",
            tokens: 30)

        var options = CostUsageScanner.Options(
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root
                .appendingPathComponent("missing-traces.sqlite"))
        options.refreshMinIntervalSeconds = 3600

        let narrow = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: newDay,
            codexHomePath: env.codexHomeRoot.path,
            historyDays: 1,
            allowPricingRefresh: false,
            scannerOptions: options)
        #expect(narrow.daily.map(\.date) == ["2026-04-08"])
        #expect(narrow.last30DaysTokens == 30)

        var legacyCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        legacyCache.scanSinceKey = nil
        legacyCache.scanUntilKey = nil
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: legacyCache)

        let expanded = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: newDay.addingTimeInterval(1),
            codexHomePath: env.codexHomeRoot.path,
            historyDays: 7,
            allowPricingRefresh: false,
            scannerOptions: options)
        #expect(expanded.daily.map(\.date) == ["2026-04-02", "2026-04-08"])
        #expect(expanded.last30DaysTokens == 45)
    }

    @Test
    func `fetcher resolves fork parent outside requested codex window`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let parentDay = try env.makeLocalNoon(year: 2026, month: 4, day: 2)
        let childDay = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let model = "openai/gpt-5.4"
        let parentID = "parent-session"
        let parentTimestamp = env.isoString(for: parentDay.addingTimeInterval(1))
        let childTimestamp = env.isoString(for: childDay.addingTimeInterval(1))
        _ = try env.writeCodexSessionFile(
            day: parentDay,
            filename: "parent.jsonl",
            contents: env.jsonl([
                [
                    "type": "session_meta",
                    "timestamp": env.isoString(for: parentDay),
                    "payload": ["session_id": parentID],
                ],
                Self.codexTokenCount(
                    timestamp: parentTimestamp,
                    model: model,
                    usageKey: "total_token_usage",
                    usage: .init(input: 100, cached: 0, output: 0)),
            ]))
        _ = try env.writeCodexSessionFile(
            day: childDay,
            filename: "child.jsonl",
            contents: env.jsonl([
                [
                    "type": "session_meta",
                    "timestamp": env.isoString(for: childDay),
                    "payload": [
                        "session_id": "child-session",
                        "forked_from_id": parentID,
                        "timestamp": parentTimestamp,
                    ],
                ],
                Self.codexTokenCount(
                    timestamp: childTimestamp,
                    model: model,
                    usageKey: "total_token_usage",
                    usage: .init(input: 125, cached: 0, output: 5)),
            ]))

        let options = CostUsageScanner.Options(
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root
                .appendingPathComponent("missing-traces.sqlite"))
        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: childDay,
            codexHomePath: env.codexHomeRoot.path,
            historyDays: 1,
            allowPricingRefresh: false,
            scannerOptions: options)

        #expect(snapshot.daily.map(\.date) == ["2026-04-08"])
        #expect(snapshot.last30DaysTokens == 30)
    }

    @Test
    func `force refresh only scans requested codex date window`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let oldDay = try env.makeLocalNoon(year: 2026, month: 3, day: 1)
        let newDay = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let oldURL = try env.writeCodexSessionFile(
            day: oldDay,
            filename: "old.jsonl",
            contents: env.jsonl([
                Self.codexTokenCount(
                    timestamp: env.isoString(for: oldDay),
                    model: "openai/gpt-5.4",
                    usageKey: "last_token_usage",
                    usage: .init(input: 10, cached: 0, output: 0)),
            ]))
        try FileManager.default.setAttributes([.modificationDate: oldDay], ofItemAtPath: oldURL.path)
        _ = try env.writeCodexSessionFile(
            day: newDay,
            filename: "new.jsonl",
            contents: env.jsonl([
                Self.codexTokenCount(
                    timestamp: env.isoString(for: newDay),
                    model: "openai/gpt-5.4",
                    usageKey: "last_token_usage",
                    usage: .init(input: 30, cached: 0, output: 0)),
            ]))

        let options = CostUsageScanner.Options(
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"))
        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: newDay,
            forceRefresh: true,
            codexHomePath: env.codexHomeRoot.path,
            historyDays: 1,
            allowPricingRefresh: false,
            scannerOptions: options)
        let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let cacheFileExists = FileManager.default.fileExists(
            atPath: CostUsageStore(cacheRoot: env.cacheRoot).databaseURL.path)

        #expect(snapshot.daily.map(\.date) == ["2026-04-08"])
        #expect(snapshot.last30DaysTokens == 30)
        #expect(cacheFileExists)
        #expect(cache.files.keys.sorted().map(URL.init(fileURLWithPath:)).map(\.lastPathComponent) == ["new.jsonl"])
    }

    @Test
    func `narrow codex refresh preserves wider cache window`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let oldDay = try env.makeLocalNoon(year: 2026, month: 4, day: 2)
        let newDay = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        _ = try env.writeCodexSessionFile(
            day: oldDay,
            filename: "old.jsonl",
            contents: env.jsonl([
                Self.codexTokenCount(
                    timestamp: env.isoString(for: oldDay),
                    model: "openai/gpt-5.4",
                    usageKey: "last_token_usage",
                    usage: .init(input: 15, cached: 0, output: 0)),
            ]))
        _ = try env.writeCodexSessionFile(
            day: newDay,
            filename: "new.jsonl",
            contents: env.jsonl([
                Self.codexTokenCount(
                    timestamp: env.isoString(for: newDay),
                    model: "openai/gpt-5.4",
                    usageKey: "last_token_usage",
                    usage: .init(input: 30, cached: 0, output: 0)),
            ]))

        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"))
        options.refreshMinIntervalSeconds = 0
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: newDay,
            until: newDay,
            now: newDay,
            options: options)
        let wide = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: newDay.addingTimeInterval(1),
            codexHomePath: env.codexHomeRoot.path,
            historyDays: 7,
            allowPricingRefresh: false,
            refreshPricingInBackground: false,
            scannerOptions: options)
        let narrow = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: newDay.addingTimeInterval(2),
            codexHomePath: env.codexHomeRoot.path,
            historyDays: 1,
            allowPricingRefresh: false,
            refreshPricingInBackground: false,
            scannerOptions: options)
        let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)

        #expect(wide.last30DaysTokens == 45)
        #expect(narrow.last30DaysTokens == 30)
        #expect(cache.files.keys.map(URL.init(fileURLWithPath:)).map(\.lastPathComponent).sorted() == [
            "new.jsonl",
            "old.jsonl",
        ])
        #expect(cache.scanSinceKey == "2026-04-01")
        #expect(cache.scanUntilKey == "2026-04-09")
    }

    @Test
    func `force codex rescan narrows cache window to refreshed range`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let oldDay = try env.makeLocalNoon(year: 2026, month: 4, day: 2)
        let newDay = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        _ = try env.writeCodexSessionFile(
            day: oldDay,
            filename: "old.jsonl",
            contents: env.jsonl([
                Self.codexTokenCount(
                    timestamp: env.isoString(for: oldDay),
                    model: "openai/gpt-5.4",
                    usageKey: "last_token_usage",
                    usage: .init(input: 15, cached: 0, output: 0)),
            ]))
        _ = try env.writeCodexSessionFile(
            day: newDay,
            filename: "new.jsonl",
            contents: env.jsonl([
                Self.codexTokenCount(
                    timestamp: env.isoString(for: newDay),
                    model: "openai/gpt-5.4",
                    usageKey: "last_token_usage",
                    usage: .init(input: 30, cached: 0, output: 0)),
            ]))

        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"))
        options.refreshMinIntervalSeconds = 0
        _ = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: newDay,
            codexHomePath: env.codexHomeRoot.path,
            historyDays: 7,
            allowPricingRefresh: false,
            refreshPricingInBackground: false,
            scannerOptions: options)

        var rescanOptions = options
        rescanOptions.forceRescan = true
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: newDay,
            until: newDay,
            now: newDay.addingTimeInterval(1),
            options: rescanOptions)
        let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)

        #expect(cache.files.keys.map(URL.init(fileURLWithPath:)).map(\.lastPathComponent).sorted() == ["new.jsonl"])
        #expect(cache.scanSinceKey == "2026-04-07")
        #expect(cache.scanUntilKey == "2026-04-09")
    }

    @Test
    func `codex refresh drops stale cache entry when session moves to archive`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let contents = try env.jsonl([
            [
                "type": "session_meta",
                "timestamp": env.isoString(for: day),
                "payload": ["session_id": "moved-session"],
            ],
            Self.codexTokenCount(
                timestamp: env.isoString(for: day.addingTimeInterval(1)),
                model: "openai/gpt-5.4",
                usageKey: "last_token_usage",
                usage: .init(input: 30, cached: 0, output: 0)),
        ])
        let originalURL = try env.writeCodexSessionFile(day: day, filename: "moved.jsonl", contents: contents)

        var options = CostUsageScanner.Options(
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root
                .appendingPathComponent("missing-traces.sqlite"))
        options.refreshMinIntervalSeconds = 0
        let first = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day,
            codexHomePath: env.codexHomeRoot.path,
            historyDays: 1,
            allowPricingRefresh: false,
            scannerOptions: options)

        let archivedURL = env.codexArchivedSessionsRoot.appendingPathComponent("moved.jsonl", isDirectory: false)
        try FileManager.default.moveItem(at: originalURL, to: archivedURL)

        let second = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            now: day.addingTimeInterval(1),
            codexHomePath: env.codexHomeRoot.path,
            historyDays: 1,
            allowPricingRefresh: false,
            scannerOptions: options)
        let cache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)

        #expect(first.last30DaysTokens == 30)
        #expect(second.last30DaysTokens == 30)
        #expect(cache.files.count == 1)
        #expect(cache.files.keys.first.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } ==
            archivedURL.resolvingSymlinksInPath().path)
    }

    @Test
    func `app codex refresh bounds its initial scan before background catch up`() {
        #expect(CostUsageFetcher.resolvedCodexScanDurationPerRefresh(
            provider: .codex,
            bypassScannerDebounce: true,
            configuredDuration: nil) == 2)
        #expect(CostUsageFetcher.resolvedCodexScanDurationPerRefresh(
            provider: .codex,
            bypassScannerDebounce: false,
            configuredDuration: nil) == nil)
        #expect(CostUsageFetcher.resolvedCodexScanDurationPerRefresh(
            provider: .claude,
            bypassScannerDebounce: true,
            configuredDuration: nil) == nil)
        #expect(CostUsageFetcher.resolvedCodexScanDurationPerRefresh(
            provider: .codex,
            bypassScannerDebounce: true,
            configuredDuration: 7) == 7)
    }

    private static func scannerOptions(env: CostUsageTestEnvironment) -> CostUsageScanner.Options {
        CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: [env.claudeProjectsRoot],
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite"))
    }

    private static func codexTokenCount(
        timestamp: String,
        model: String,
        usageKey: String,
        usage: CostUsageCodexTotals) -> [String: Any]
    {
        [
            "type": "event_msg",
            "timestamp": timestamp,
            "payload": [
                "type": "token_count",
                "info": [
                    "model": model,
                    usageKey: [
                        "input_tokens": usage.input,
                        "cached_input_tokens": usage.cached,
                        "output_tokens": usage.output,
                    ],
                ],
            ],
        ]
    }

    private static func writeCodexSessionFile(
        homeRoot: URL,
        env: CostUsageTestEnvironment,
        day: Date,
        filename: String,
        tokens: Int) throws
    {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        let dir = homeRoot
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(String(format: "%04d", comps.year ?? 1970), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", comps.month ?? 1), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", comps.day ?? 1), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let model = "openai/gpt-5.4"
        let url = dir.appendingPathComponent(filename, isDirectory: false)
        try env.jsonl([
            [
                "type": "turn_context",
                "timestamp": env.isoString(for: day),
                "payload": ["model": model],
            ],
            Self.codexTokenCount(
                timestamp: env.isoString(for: day.addingTimeInterval(1)),
                model: model,
                usageKey: "last_token_usage",
                usage: .init(input: tokens, cached: 0, output: 0)),
        ]).write(to: url, atomically: true, encoding: .utf8)
    }
}

extension CostUsageFetcherTests {}

extension CostUsageFetcherTests {
    @Test
    func `relative sqlite home uses each rollout directory before project canonicalization`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let project = env.root.appendingPathComponent("project", isDirectory: true)
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["init", "-q", project.path]
        try git.run()
        git.waitUntilExit()
        #expect(git.terminationStatus == 0)

        for sessionID in ["first", "second"] {
            let cwd = project.appendingPathComponent(sessionID, isDirectory: true)
            let sqliteHome = cwd.appendingPathComponent("local-state", isDirectory: true)
            try FileManager.default.createDirectory(at: sqliteHome, withIntermediateDirectories: true)
            var database: OpaquePointer?
            let opened = sqlite3_open(sqliteHome.appendingPathComponent("state_5.sqlite").path, &database)
            defer { sqlite3_close(database) }
            #expect(opened == SQLITE_OK)
            let sql = """
            CREATE TABLE threads (id TEXT PRIMARY KEY, title TEXT);
            INSERT INTO threads VALUES ('\(sessionID)', 'Title for \(sessionID)');
            CREATE TABLE projects (id TEXT PRIMARY KEY, name TEXT);
            CREATE TABLE project_roots (project_id TEXT, path TEXT);
            INSERT INTO projects VALUES ('project', 'Saved Worktree Project');
            INSERT INTO project_roots VALUES ('project', '\(cwd.path)');
            """
            #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
            _ = try env.writeCodexSessionFile(
                day: day,
                filename: "\(sessionID).jsonl",
                contents: env.jsonl([
                    [
                        "type": "session_meta",
                        "timestamp": env.isoString(for: day),
                        "payload": ["session_id": sessionID, "cwd": cwd.path],
                    ],
                    [
                        "type": "event_msg",
                        "timestamp": env.isoString(for: day.addingTimeInterval(1)),
                        "payload": ["type": "token_count", "info": [
                            "model": "openai/gpt-5.4",
                            "last_token_usage": ["input_tokens": 100, "output_tokens": 10],
                        ]],
                    ],
                ]))
        }
        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            environment: ["CODEX_SQLITE_HOME": "local-state"],
            now: day,
            historyDays: 1,
            allowPricingRefresh: false,
            scannerOptions: .init(
                codexSessionsRoot: env.codexSessionsRoot,
                cacheRoot: env.cacheRoot,
                codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite")))

        #expect(snapshot.sessions.count == 2)
        for session in snapshot.sessions {
            #expect(session.title == "Title for \(session.sessionID)")
            #expect(session.projectName == "Saved Worktree Project")
            #expect(session.projectPath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
                == project.resolvingSymlinksInPath().path)
            #expect(session.totalTokens == 110)
        }
        #expect(snapshot.projects.map(\.name) == ["Saved Worktree Project"])
        let cachedResult = await CostUsageFetcher.loadCachedCodexTokenSnapshotResult(
            now: day,
            historyDays: 1,
            scannerOptions: .init(
                codexSessionsRoot: env.codexSessionsRoot,
                cacheRoot: env.cacheRoot,
                codexTraceDatabaseURL: env.root.appendingPathComponent("missing-traces.sqlite")),
            environment: ["CODEX_SQLITE_HOME": "local-state"])
        let cached = try #require(cachedResult?.snapshot)
        #expect(cached.projects.map(\.name) == ["Saved Worktree Project"])
        #expect(cached.sessions.allSatisfy { $0.projectName == "Saved Worktree Project" })
    }

    @Test
    func `thread title lookup skips roots outside a codex home`() {
        let session = CostUsageSessionBreakdown(
            sessionID: "session",
            lastActivity: Date(timeIntervalSince1970: 0),
            inputTokens: 1,
            cachedInputTokens: nil,
            outputTokens: 1,
            totalTokens: 2,
            requestCount: 1,
            costUSD: 1,
            modelBreakdowns: [])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-codex-home", isDirectory: true)

        #expect(CostUsageFetcher.codexBreakdownsWithMetadata([session], sessionsRoot: root).sessions == [session])
        #expect(CostUsageFetcher.codexBreakdownsWithMetadata([session], sessionsRoot: nil).sessions == [session])
    }
}
