---
summary: "Agent Sessions discovery, protocol versions, presentation, and privacy boundaries."
read_when:
  - Changing local or SSH agent-session discovery
  - Reviewing Agent Sessions architecture
---

# Agent Sessions design

CodexBar discovers Codex and Claude Code agent sessions locally and over SSH. Local discovery correlates processes with bounded metadata and can show recent Codex file-only fallback rows. Those fallback rows do not prove process lifetime and never activate Stay Awake.

## Data model

`AgentSession.Provider` contains `codex` and `claude`. A resolved upstream session ID is preferred, while an unmatched process uses `pid:<pid>`.

The v1 JSON protocol remains a top-level array restricted to `codex` and `claude`. The v2 protocol retains the same array shape and carries the current providers and optional fields. Remote fetching negotiates v2 first and falls back to v1 for mixed-version compatibility.

## Local scanner

`LocalAgentSessionScanner` combines bounded process and metadata signals. macOS process and cwd discovery stays in-process through libproc; Linux uses the existing guarded `ps` and `/proc` paths.

On macOS, Codex and Claude bundle checks, provider identity, and CLI/desktop source labels use the preserved executable argument, so prompt paths do not change session classification. Existing executable allowlists, wrapper handling, and command-only fallbacks still apply.

The deadline also gates file-type inspection, Codex modification-time reads, and queued Claude Desktop root probes. In-flight filesystem calls can finish after the deadline; this is a best-effort work budget, not an interruptible timeout.

## Presentation and focus

The menu uses `⌘` for Codex and `✦` for Claude Code. Project labels remain the default because descriptive titles can contain sensitive text.

Local focus walks from the session PID to the owning terminal/editor application and raises the best matching window when Accessibility permission is available. Remote focus invokes the same command over SSH.

## Privacy and safety

CodexBar never invokes `ps eww`, reads `/proc/<pid>/environ`, or otherwise captures full target-process environments for session discovery. It reads only bounded session metadata under resolved roots, never loads prompt/tool transcript bodies for this feature, never changes upstream session state, and never persists extracted titles separately.

## Stay Awake

Settings → Menu → Agent Sessions → **Stay Awake** is off by default and local to this Mac. It scans locally every 30 seconds without enabling the sessions menu or remote discovery. One `PreventUserIdleSystemSleep` assertion stays active while at least one session has a positive PID, including idle processes waiting for a prompt. Remote sessions and file-only rollouts do not count. The menu shows “Stay Awake: local agent session is live” while active.

The assertion releases at the next scan with no process-backed sessions, immediately on disablement or quit, and through macOS on a crash. Stale scans cannot reacquire it after disablement or shutdown; failed acquisitions retry on the next scan. Stay Awake can use battery power. It cannot wake a Mac or prevent display, explicit, or lid-close sleep, and has no timer, grace period, or always-on mode.

Final store teardown cancels its tasks and releases an owned assertion on the thread that drops the last reference, without a main-actor cleanup hop. Live state changes remain on the main actor; teardown uses Sendable task handles and the thread-safe assertion-release closure.

## Non-goals

Historical browsing/analytics, cloud chat/task sessions, permission-waiting state, exact tmux pane focus, a persistent remote daemon, and treating either upstream on-disk dialect as a public compatibility guarantee are out of scope.
