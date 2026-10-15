import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct CLISnapshotTests {
    @Test
    func `renders text snapshot for codex`() {
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "user@example.com",
            accountOrganization: nil,
            loginMethod: "pro")
        let snap = UsageSnapshot(
            primary: .init(usedPercent: 12, windowMinutes: 300, resetsAt: nil, resetDescription: "today at 3:00 PM"),
            secondary: .init(usedPercent: 25, windowMinutes: 10080, resetsAt: nil, resetDescription: "Fri at 9:00 AM"),
            tertiary: nil,
            updatedAt: Date(timeIntervalSince1970: 0),
            identity: identity)

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snap,
            credits: CreditsSnapshot(remaining: 42, events: [], updatedAt: Date()),
            context: RenderContext(
                header: "Codex 1.2.3 (codex-cli)",
                status: ProviderStatusPayload(
                    indicator: .minor,
                    description: "Degraded performance",
                    updatedAt: Date(timeIntervalSince1970: 0),
                    url: "https://status.example.com"),
                useColor: false,
                resetStyle: .absolute))

        #expect(output.contains("Codex 1.2.3 (codex-cli)"))
        #expect(output.contains("Status: Partial outage – Degraded performance"))
        #expect(output.contains("Codex"))
        #expect(output.contains("Session: 88% left"))
        #expect(output.contains("Weekly: 75% left"))
        #expect(output.contains("Credits: 42"))
        #expect(output.contains("Account: user@example.com"))
        #expect(output.contains("Plan: Pro 20x"))
    }

    @Test
    func `renders Codex limit reset credits`() {
        let now = Date()
        let expiresAt = now.addingTimeInterval(7200)
        let resetCredits = CodexRateLimitResetCreditsSnapshot(
            credits: [
                CodexRateLimitResetCredit(
                    id: "credit-1",
                    resetType: "codex_rate_limits",
                    status: .available,
                    grantedAt: Date(timeIntervalSince1970: 0),
                    expiresAt: expiresAt,
                    redeemStartedAt: nil,
                    redeemedAt: nil,
                    title: nil,
                    description: nil),
                CodexRateLimitResetCredit(
                    id: "expired-credit",
                    resetType: "codex_rate_limits",
                    status: .available,
                    grantedAt: Date(timeIntervalSince1970: 0),
                    expiresAt: now,
                    redeemStartedAt: nil,
                    redeemedAt: nil,
                    title: nil,
                    description: nil),
            ],
            availableCount: 99,
            updatedAt: Date(timeIntervalSince1970: 0))
        let snapshot = UsageSnapshot(
            primary: .init(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            codexResetCredits: resetCredits,
            updatedAt: Date(timeIntervalSince1970: 0))

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snapshot,
            credits: nil,
            context: RenderContext(
                header: "Codex (oauth)",
                status: nil,
                useColor: false,
                resetStyle: .countdown))

        #expect(output.contains("Limit Reset Credits: 1 available"))
        #expect(output.contains("Next reset credit expires"))
    }

    @Test
    func `renders Codex prolite plan with multiplier display name`() {
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "user@example.com",
            accountOrganization: nil,
            loginMethod: "prolite")
        let snap = UsageSnapshot(
            primary: .init(usedPercent: 12, windowMinutes: 300, resetsAt: nil, resetDescription: "today at 3:00 PM"),
            secondary: nil,
            tertiary: nil,
            updatedAt: Date(timeIntervalSince1970: 0),
            identity: identity)

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snap,
            credits: nil,
            context: RenderContext(
                header: "Codex 1.2.3 (codex-cli)",
                status: nil,
                useColor: false,
                resetStyle: .absolute))

        #expect(output.contains("Plan: Pro 5x"))
        #expect(!output.contains("Plan: Pro Lite"))
        #expect(!output.contains("Plan: Prolite"))
    }

    @Test
    func `renders Codex plan only limits as unavailable`() {
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: "user@example.com",
            accountOrganization: nil,
            loginMethod: "pro")
        let snap = UsageSnapshot(
            primary: nil,
            secondary: nil,
            tertiary: nil,
            updatedAt: Date(timeIntervalSince1970: 0),
            identity: identity)

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snap,
            credits: nil,
            context: RenderContext(
                header: "Codex 1.2.3 (codex-cli)",
                status: nil,
                useColor: false,
                resetStyle: .absolute))

        #expect(output.contains("Limits: not available"))
        #expect(output.contains("Account: user@example.com"))
        #expect(output.contains("Plan: Pro 20x"))
        #expect(!output.contains("Session:"))
        #expect(!output.contains("Weekly:"))
    }

    @Test
    func `renders text snapshot for claude without weekly`() {
        let snap = UsageSnapshot(
            primary: .init(usedPercent: 2, windowMinutes: nil, resetsAt: nil, resetDescription: "3pm (Europe/Vienna)"),
            secondary: nil,
            tertiary: nil,
            updatedAt: Date(timeIntervalSince1970: 0))

        let output = CLIRenderer.renderText(
            provider: .claude,
            snapshot: snap,
            credits: nil,
            context: RenderContext(
                header: "Claude Code 2.0.69 (claude)",
                status: nil,
                useColor: false,
                resetStyle: .absolute))

        #expect(output.contains("Session: 98% left"))
        #expect(!output.contains("Weekly:"))
    }

    @Test
    func `renders Claude Max multiplier without uppercasing x`() {
        let identity = ProviderIdentitySnapshot(
            providerID: .claude,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: "Claude Max 5x")
        let snapshot = UsageSnapshot(
            primary: .init(usedPercent: 2, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: Date(timeIntervalSince1970: 0),
            identity: identity)

        let output = CLIRenderer.renderText(
            provider: .claude,
            snapshot: snapshot,
            credits: nil,
            context: RenderContext(
                header: "Claude (oauth)",
                status: nil,
                useColor: false,
                resetStyle: .absolute))

        #expect(output.contains("Plan: Claude Max 5x"))
        #expect(!output.contains("Plan: Claude Max 5X"))
    }

    @Test
    func `renders pace line when weekly has reset`() {
        let now = Date()
        let snap = UsageSnapshot(
            primary: nil,
            secondary: .init(
                usedPercent: 50,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(3 * 24 * 60 * 60),
                resetDescription: nil),
            tertiary: nil,
            updatedAt: now)

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snap,
            credits: nil,
            context: RenderContext(
                header: "Codex 0.0.0 (codex-cli)",
                status: nil,
                useColor: false,
                resetStyle: .countdown))

        #expect(output.contains("Pace:"))
    }

    @Test
    func `configured work days affect weekly text and JSON pace`() throws {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let resetsAt = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 14)))
        let now = resetsAt.addingTimeInterval(-72 * 60 * 60)
        let snap = UsageSnapshot(
            primary: nil,
            secondary: .init(
                usedPercent: 60,
                windowMinutes: 10080,
                resetsAt: resetsAt,
                resetDescription: nil),
            tertiary: nil,
            updatedAt: now)

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snap,
            credits: nil,
            context: RenderContext(
                header: "Codex 0.0.0 (codex-cli)",
                status: nil,
                useColor: false,
                resetStyle: .countdown,
                weeklyWorkDays: 5),
            now: now)
        #expect(output.contains("Pace: On pace | Expected 60% used | Lasts until reset"))

        let pace = try #require(CLIRenderer.providerPacePayload(
            provider: .codex,
            snapshot: snap,
            weeklyWorkDays: 5,
            now: now)?.secondary)
        #expect(pace.expectedUsedPercent == 60)
        #expect(pace.summary == "On pace | Expected 60% used | Lasts until reset")
    }

    @Test
    func `renders session pace line when session window has reset`() {
        let now = Date()
        let snap = UsageSnapshot(
            primary: .init(
                usedPercent: 20,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(2 * 60 * 60),
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now)

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snap,
            credits: nil,
            context: RenderContext(
                header: "Codex 0.0.0 (codex-cli)",
                status: nil,
                useColor: false,
                resetStyle: .countdown),
            now: now)

        #expect(output.contains("Session: 80% left"))
        // 2h remaining of a 5h window => 3h elapsed => 60% expected; even rate easily lasts to reset.
        #expect(output.contains("Pace: 40% in reserve | Expected 60% used | Lasts until reset | 1.5× headroom"))
    }

    @Test
    func `renders Claude session pace using five hour default window`() {
        let now = Date()
        let snap = UsageSnapshot(
            primary: .init(
                usedPercent: 20,
                windowMinutes: nil,
                resetsAt: now.addingTimeInterval(2 * 60 * 60),
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now)

        let output = CLIRenderer.renderText(
            provider: .claude,
            snapshot: snap,
            credits: nil,
            context: RenderContext(
                header: "Claude Code 2.0.69 (claude)",
                status: nil,
                useColor: false,
                resetStyle: .countdown),
            now: now)

        // windowMinutes is nil, so the 5-hour (300 minute) session default must drive the pace.
        #expect(output.contains("Pace: 40% in reserve | Expected 60% used | Lasts until reset"))
        #expect(!output.contains("1.5× headroom"))
    }

    @Test
    func `renders session pace deficit with run out estimate`() {
        let now = Date()
        let snap = UsageSnapshot(
            primary: .init(
                usedPercent: 50,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(4 * 60 * 60),
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now)

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snap,
            credits: nil,
            context: RenderContext(
                header: "Codex 0.0.0 (codex-cli)",
                status: nil,
                useColor: false,
                resetStyle: .countdown),
            now: now)

        // 1h elapsed of a 5h window => 20% expected vs 50% used => burning ahead of pace.
        // Session mirrors the GUI's "Projected empty" wording (weekly uses "Runs out").
        #expect(output.contains("Pace: 30% in deficit | Expected 20% used | Projected empty in"))
        #expect(!output.contains("Runs out"))
    }

    @Test
    func `renders session pace on track and lasts until reset`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Exactly halfway through a 5h window with 50% used => On pace (delta 0); the even rate
        // means the quota lasts precisely to the reset.
        let snap = UsageSnapshot(
            primary: .init(
                usedPercent: 50,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(2.5 * 60 * 60),
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now)

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snap,
            credits: nil,
            context: RenderContext(
                header: "Codex 0.0.0 (codex-cli)",
                status: nil,
                useColor: false,
                resetStyle: .countdown),
            now: now)

        #expect(output.contains("Pace: On pace | Expected 50% used | Lasts until reset"))
    }

    @Test
    func `hides session pace for non-session primary window`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Claude with no 5-hour data falls a 7-day window back into `primary`; it must not be
        // paced as a "Session" (that would print "Projected empty …" over a weekly window).
        let snap = UsageSnapshot(
            primary: .init(
                usedPercent: 50,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(3 * 24 * 60 * 60),
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now)

        let output = CLIRenderer.renderText(
            provider: .claude,
            snapshot: snap,
            credits: nil,
            context: RenderContext(
                header: "Claude Code 2.0.69 (claude)",
                status: nil,
                useColor: false,
                resetStyle: .countdown),
            now: now)

        #expect(!output.contains("Pace:"))
        #expect(CLIRenderer.providerPacePayload(provider: .claude, snapshot: snap, now: now) == nil)
    }

    @Test
    func `renders JSON payload`() throws {
        let snap = UsageSnapshot(
            primary: .init(usedPercent: 50, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: .init(usedPercent: 10, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let payload = ProviderPayload(
            provider: .codex,
            account: nil,
            version: "1.2.3",
            source: "codex-cli",
            status: ProviderStatusPayload(
                indicator: .none,
                description: nil,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_010),
                url: "https://status.example.com"),
            usage: snap,
            credits: nil,
            openaiDashboard: nil,
            error: nil,
            diagnostic: "Grok team usage is unavailable from the current billing surface.")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            Issue.record("Failed to decode JSON payload")
            return
        }

        #expect(json.contains("\"provider\":\"codex\""))
        #expect(json.contains("\"version\":\"1.2.3\""))
        #expect(json.contains("\"status\""))
        #expect(json.contains("status.example.com"))
        #expect(json.contains("Grok team usage is unavailable from the current billing surface."))
        #expect(json.contains("\"primary\""))
        #expect(json.contains("\"windowMinutes\":300"))
        #expect(json.contains("1700000000"))
    }

    @Test
    func `json pace rounds derived numbers to match usage precision`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // 13000s elapsed of an 18000s (300m) window => 72.22% expected; used 79 => +6.78 deficit;
        // projected empty in ~3455.7s. Derived fields must be emitted as whole numbers (no float noise).
        let snap = UsageSnapshot(
            primary: .init(
                usedPercent: 79,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(5000),
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now)

        let payload = ProviderPayload(
            provider: .codex,
            account: nil,
            version: nil,
            source: "codex-cli",
            status: nil,
            usage: snap,
            credits: nil,
            openaiDashboard: nil,
            error: nil,
            pace: CLIRenderer.providerPacePayload(provider: .codex, snapshot: snap, now: now))

        let data = try JSONEncoder().encode(payload)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let primary = try #require((root["pace"] as? [String: Any])?["primary"] as? [String: Any])

        #expect(primary["expectedUsedPercent"] as? Double == 72)
        #expect(primary["deltaPercent"] as? Double == 7)
        #expect(primary["etaSeconds"] as? Double == 3456)
        // actualUsedPercent is not emitted; consumers read usage.primary.usedPercent.
        #expect(primary["actualUsedPercent"] == nil)
    }

    @Test
    func `json payload includes session and weekly pace with distinct wording`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = UsageSnapshot(
            // 1h elapsed of a 5h window => 20% expected vs 50% used => deficit, runs out in 1h.
            primary: .init(
                usedPercent: 50,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(4 * 60 * 60),
                resetDescription: nil),
            // 5d elapsed of a 7d window => ~71% expected vs 90% used => deficit, runs out before reset.
            secondary: .init(
                usedPercent: 90,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(2 * 24 * 60 * 60),
                resetDescription: nil),
            tertiary: nil,
            updatedAt: now)

        let payload = ProviderPayload(
            provider: .codex,
            account: nil,
            version: "1.2.3",
            source: "codex-cli",
            status: nil,
            usage: snap,
            credits: nil,
            openaiDashboard: nil,
            error: nil,
            pace: CLIRenderer.providerPacePayload(provider: .codex, snapshot: snap, now: now))

        let data = try JSONEncoder().encode(payload)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pace = try #require(root["pace"] as? [String: Any])

        let primary = try #require(pace["primary"] as? [String: Any])
        #expect(primary["stage"] as? String == "farAhead")
        #expect(primary["expectedUsedPercent"] as? Double == 20)
        #expect(primary["deltaPercent"] as? Double == 30)
        #expect(primary["willLastToReset"] as? Bool == false)
        #expect(primary["etaSeconds"] as? Double == 3600)
        #expect((primary["summary"] as? String)?
            .contains("30% in deficit | Expected 20% used | Projected empty in") == true)
        // actualUsedPercent is redundant with usage.usedPercent and is not emitted;
        // runOutProbability is never set by the CLI, so both keys are omitted.
        #expect(primary["actualUsedPercent"] == nil)
        #expect(primary["runOutProbability"] == nil)

        let secondary = try #require(pace["secondary"] as? [String: Any])
        #expect(secondary["stage"] as? String == "farAhead")
        #expect((secondary["summary"] as? String)?.contains("Runs out in") == true)
        #expect((secondary["summary"] as? String)?.contains("Projected empty") == false)
    }

    @Test
    func `json includes only session pace when weekly window missing`() throws {
        let now = Date()
        let snap = UsageSnapshot(
            primary: .init(
                usedPercent: 50,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(4 * 60 * 60),
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: now)

        let payload = ProviderPayload(
            provider: .codex,
            account: nil,
            version: nil,
            source: "codex-cli",
            status: nil,
            usage: snap,
            credits: nil,
            openaiDashboard: nil,
            error: nil,
            pace: CLIRenderer.providerPacePayload(provider: .codex, snapshot: snap, now: now))

        let data = try JSONEncoder().encode(payload)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pace = try #require(root["pace"] as? [String: Any])
        #expect(pace["primary"] is [String: Any])
        #expect(pace["secondary"] == nil)
    }

    @Test
    func `encodes JSON with secondary null when missing`() throws {
        let snap = UsageSnapshot(
            primary: .init(usedPercent: 0, windowMinutes: nil, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snap)
        guard let json = String(data: data, encoding: .utf8) else {
            Issue.record("Failed to decode JSON payload")
            return
        }

        #expect(json.contains("\"secondary\":null"))
    }

    @Test
    func `parses output format`() {
        #expect(OutputFormat(argument: "json") == .json)
        #expect(OutputFormat(argument: "TEXT") == .text)
        #expect(OutputFormat(argument: "invalid") == nil)
    }

    @Test
    func `defaults to usage when no command provided`() {
        #expect(CodexBarCLI.effectiveArgv([]) == ["usage"])
        #expect(CodexBarCLI.effectiveArgv(["--format", "json"]).first == "usage")
        #expect(CodexBarCLI.effectiveArgv(["usage", "--format", "json"]).first == "usage")
    }

    @Test
    func `status line is last and colored when TTY`() {
        let identity = ProviderIdentitySnapshot(
            providerID: .claude,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: "pro")
        let snap = UsageSnapshot(
            primary: .init(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: .init(usedPercent: 0, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            updatedAt: Date(),
            identity: identity)

        let output = CLIRenderer.renderText(
            provider: .claude,
            snapshot: snap,
            credits: nil,
            context: RenderContext(
                header: "Claude Code 2.0.58 (claude)",
                status: ProviderStatusPayload(
                    indicator: .critical,
                    description: "Major outage",
                    updatedAt: nil,
                    url: "https://status.claude.com"),
                useColor: true,
                resetStyle: .absolute))

        let lines = output.split(separator: "\n")
        #expect(lines.last?.contains("Status: Critical issue – Major outage") == true)
        #expect(output.contains("\u{001B}[31mStatus")) // red for critical
    }

    @Test
    func `output has ansi when TTY even without status`() {
        let snap = UsageSnapshot(
            primary: .init(usedPercent: 1, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: Date(timeIntervalSince1970: 0))

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snap,
            credits: nil,
            context: RenderContext(
                header: "Codex 0.0.0 (codex-cli)",
                status: nil,
                useColor: true,
                resetStyle: .absolute))

        #expect(output.contains("\u{001B}["))
    }

    @Test
    func `tty output colors header and usage`() {
        let snap = UsageSnapshot(
            primary: .init(usedPercent: 95, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: .init(usedPercent: 80, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            updatedAt: Date(timeIntervalSince1970: 0))

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snap,
            credits: nil,
            context: RenderContext(
                header: "Codex 0.0.0 (codex-cli)",
                status: nil,
                useColor: true,
                resetStyle: .absolute))

        #expect(output.contains("\u{001B}[1;95m== Codex 0.0.0 (codex-cli) ==\u{001B}[0m"))
        #expect(output.contains("Session: \u{001B}[31m5% left\u{001B}[0m")) // red <10% left
        #expect(output.contains("Weekly: \u{001B}[33m20% left\u{001B}[0m")) // yellow <25% left
    }

    @Test
    func `status line is plain when no TTY`() {
        let identity = ProviderIdentitySnapshot(
            providerID: .codex,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: "pro")
        let snap = UsageSnapshot(
            primary: .init(usedPercent: 0, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: .init(usedPercent: 0, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            tertiary: nil,
            updatedAt: Date(),
            identity: identity)

        let output = CLIRenderer.renderText(
            provider: .codex,
            snapshot: snap,
            credits: nil,
            context: RenderContext(
                header: "Codex 0.6.0 (codex-cli)",
                status: ProviderStatusPayload(
                    indicator: .none,
                    description: "Operational",
                    updatedAt: nil,
                    url: "https://status.openai.com/"),
                useColor: false,
                resetStyle: .absolute))

        #expect(!output.contains("\u{001B}["))
        #expect(output.contains("Status: Operational – Operational"))
    }
}
