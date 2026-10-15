# CodexBar 🎚️ — May your tokens never run out.

> Every AI coding limit, in your menu bar.

[![Latest release](https://img.shields.io/github/v/release/steipete/CodexBar?style=flat-square&color=0a0a0c)](https://github.com/steipete/CodexBar/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-0a0a0c?style=flat-square)](https://github.com/steipete/CodexBar/releases/latest)
[![Linux desktop](https://img.shields.io/badge/Linux-Qt_6-1793d1?style=flat-square)](Integrations/Linux/README.md)
[![Homebrew](https://img.shields.io/badge/brew-steipete%2Ftap%2Fcodexbar-orange?style=flat-square)](https://github.com/steipete/homebrew-tap)
[![AUR](https://img.shields.io/aur/version/codexbar-cli?style=flat-square&color=1793d1)](https://aur.archlinux.org/packages/codexbar-cli)
[![License: MIT](https://img.shields.io/badge/license-MIT-6e5aff?style=flat-square)](LICENSE)
[![Site](https://img.shields.io/badge/site-codexbar.app-16d3b4?style=flat-square)](https://codexbar.app)

<a href="https://codexbar.app"><img src="docs/social.png?v=3127a233986e3638" alt="CodexBar — every AI coding limit in your menu bar." width="100%" /></a>

Tiny macOS 14+ menu bar app that keeps **Codex and Claude limits visible** and shows when each window resets. See the [supported providers](#providers) below. One status item per provider, or Merge Icons mode with a provider switcher. No Dock icon, minimal UI, dynamic bar icons.

Also available as a [Linux desktop app](Integrations/Linux/README.md) with usage and spending windows, separate settings, desktop notifications, and an optional tray icon. On Omarchy, a native bar widget shares the desktop app’s data and follows your theme.

<img src="docs/codexbar.png" alt="CodexBar menu popover with provider tiles, usage bars, and reset countdowns" width="520" />

## Why

- **Plan around resets.** Per-provider session, weekly, and monthly windows with countdowns to the next reset — stop guessing whether to start that long task.
- **Credits, spend, and cost scans.** Credit balances, Claude Admin API spend dashboards, and local cost scans for Codex and Claude.
- **Live status.** Provider status polling surfaces incident badges in the menu and an indicator overlay on the bar icon.
- **Privacy-first.** Reuses existing Codex and Claude sessions — OAuth, browser cookies, local files — so no passwords are stored.

## Install

### macOS app

Requires macOS 14+ (Sonoma). Download from [GitHub Releases](https://github.com/steipete/CodexBar/releases), or install with Homebrew:

```bash
brew install --cask codexbar
```

### Linux desktop and Omarchy

The Qt 6 desktop app supports Wayland and X11, with an optional Omarchy widget.
Published desktop archives target x86_64 and ARM64 and require glibc 2.39+,
Qt 6.4+, and a separately installed CodexBar CLI. Python 3 runs the per-user installer.

Follow the [Linux installation guide](Integrations/Linux/README.md#install-release-archives)
for Arch/Omarchy, Fedora, and Debian/Ubuntu runtime packages, verified release
downloads, and upgrades. It keeps the CLI's resource bundle beside its executable
and installs a launcher and optional login startup. Open Settings to choose
providers, then authenticate through the provider's CLI or configure its API key.
GNOME may need a tray extension; the app's windows work without a tray.

See the [macOS feature comparison](Integrations/Linux/MAC_COMPARISON.md) for
supported features and remaining gaps.

### CLI Tarballs (macOS/Linux)
Homebrew formula (Linux today):
```bash
brew install steipete/tap/codexbar
```
Arch Linux AUR package:
```bash
yay -S codexbar-cli
```
Or download release tarballs from GitHub Releases:
- macOS: `CodexBarCLI-v<tag>-macos-arm64.tar.gz`, `CodexBarCLI-v<tag>-macos-x86_64.tar.gz`
- Linux (glibc): `CodexBarCLI-v<tag>-linux-aarch64.tar.gz`, `CodexBarCLI-v<tag>-linux-x86_64.tar.gz`
- Linux (static musl): `CodexBarCLI-v<tag>-linux-musl-aarch64.tar.gz`, `CodexBarCLI-v<tag>-linux-musl-x86_64.tar.gz`

### macOS first run
- Open Settings → Providers and enable what you use.
- Install/sign in to the Codex and Claude sources you rely on: the CLIs, browser sessions, or OAuth credentials.
- Optional: Settings → Providers → Codex → OpenAI cookies (Automatic or Manual) to add dashboard extras.

### Configure providers from the CLI
Provider toggles live in the resolved CodexBar config file. New installs use
`~/.config/codexbar/config.json`; existing `~/.codexbar/config.json` installs still load from the legacy path. You can
script the same provider list that Settings → Providers uses:

```bash
codexbar config providers
codexbar config enable --provider claude
codexbar config disable --provider codex
```

See [CLI configuration](docs/cli-configuration.md) for the full flow.

## Providers

This build supports only Codex and Claude.

- [Codex](docs/codex.md) — OAuth API or local Codex CLI, plus optional OpenAI web dashboard extras.
- [Claude](docs/claude.md) — OAuth API, browser cookies, or CLI PTY fallback; session and weekly usage where available.

## Icon & Screenshot
The menu bar icon is a tiny usage meter. Bar meaning is provider-specific, and errors/stale data can dim the icon or
show an incident indicator.

## Features
- Codex and Claude menu bar with per-provider toggles (Settings → Providers).
- Provider-specific usage meters with reset countdowns.
- Optional Codex web dashboard enrichments (code review remaining, usage breakdown, credits history).
- Inline spend and usage charts for the Claude Admin API.
- Codex and Claude Plan Usage menus show a quota burndown from recorded snapshots, with the capture time and an even-use guide. The existing utilization history remains below it, and the line fills in as the app collects samples.
- Configurable cost-usage scans for Codex + Claude. Codex history uses a WAL-enabled SQLite store capped at 25,000 retained session entries and 256 MiB.
- A persistent Settings → Usage & Spend view for local estimates, grouped by native currency and provider. Each provider shows its accounts or history sources alongside its model breakdown; project/session views and daily/hourly trends share compact selectors. Incomplete history stays labeled, and source, privacy, export, and sharing controls remain available.
- Provider status polling with incident badges in the menu and icon overlay.
- Merge Icons mode to combine providers into one status item + switcher. With **Icon + Percent** and both providers enabled, choose **Stacked** to show their first layout lines together. Automatic rows follow provider order and reserve explicit choices; disabling a selected provider uses a fallback and restores the saved choice when re-enabled. The dropdown menu stays available, and each provider keeps its own layout settings.
- Display controls for provider icons, labels, bars, reset-time style, and highest-usage auto-selection.
- Fresh installs default to Adaptive refresh. Existing users keep every valid stored choice, while legacy unset or
  invalid preferences resolve to 5 minutes. Manual and fixed 1m, 2m, 5m, 15m, and 30m alternatives remain available.
- Bundled CLI (`codexbar`) for scripts and CI (including `codexbar cost --provider codex`, `claude`, or `both` for local cost usage); macOS and Linux CLI builds available.
- WidgetKit widgets for Codex and Claude.
- Localized app and website with a shared 23-language catalog, automatic website detection, persistent pickers, and RTL support.
- Optional session quota notifications and weekly-reset confetti.
- Privacy-first: on-device parsing by default; browser cookies are opt-in and reused (no passwords stored).

## Privacy note
Wondering if CodexBar scans your disk? It doesn’t crawl your filesystem; it reads a small set of known locations (browser cookies/local storage, provider config files, local JSONL logs) when the related features are enabled. Plain Adaptive refresh never inspects local agent activity. The separate Adaptive (agent-aware) option asks before inspecting the running-process list (including command lines) to identify Codex/Claude and reading bounded known-session metadata. Declining returns to plain Adaptive. When allowed with Agent Sessions hidden, CodexBar retains only the latest activity time and discards session paths and identities. Provider tokens and token-account settings live in the CodexBar config file with restrictive file permissions. See the discussion and audit notes in [issue #12](https://github.com/steipete/CodexBar/issues/12).

## macOS permissions (why they’re needed)
- **Full Disk Access (optional)**: only required to read Safari cookies/local storage for web-based sources. If you don’t grant it, use another supported browser, manual cookies, OAuth, or CLI/local sources.
- **Keychain access (prompted by macOS)**:
  Chromium cookie import needs the browser’s Safe Storage item, and an explicitly enabled Claude OAuth repair may
  read Claude Code’s own Keychain item. Background CodexBar paths fail or skip instead of requesting authorization;
  a user-initiated import or repair can still show the macOS prompt. **Settings → Advanced → Disable Keychain
  access** blocks CodexBar-owned Keychain operations and browser decryption, but cannot constrain provider-owned CLIs
  that CodexBar launches. Manual cookie headers, API keys, and file-backed sources remain alternatives where
  supported. See [Keychain prompts](docs/keychain-prompts.md) for Allow Once vs. Always Allow, recurring grants, and
  safe troubleshooting.
- **Files & Folders prompts (folder/volume access)**: CodexBar launches the Codex and Claude CLIs and local probes. If those helpers read a project directory or external drive, macOS may ask CodexBar for that folder/volume (e.g., Desktop or an external volume). This is driven by the helper’s working directory, not background disk scanning.
- **What we do not request in the background**: no Screen Recording or Accessibility permissions; user-triggered helper actions may ask macOS for Automation permission to open Terminal. No passwords are stored (browser cookies are reused when you opt in).

## Docs
- Providers overview: [docs/providers.md](docs/providers.md)
- Issue labeling guide: [docs/ISSUE_LABELING.md](docs/ISSUE_LABELING.md)
- UI & icon notes: [docs/ui.md](docs/ui.md)
- CLI reference: [docs/cli.md](docs/cli.md)
- Configuration: [docs/configuration.md](docs/configuration.md)
- Keychain prompts: [docs/keychain-prompts.md](docs/keychain-prompts.md)
- CLI configuration: [docs/cli-configuration.md](docs/cli-configuration.md)
- Widgets: [docs/widgets.md](docs/widgets.md)
- Architecture: [docs/architecture.md](docs/architecture.md)
- Refresh loop: [docs/refresh-loop.md](docs/refresh-loop.md)
- Status polling: [docs/status.md](docs/status.md)
- Sparkle updates: [docs/sparkle.md](docs/sparkle.md)
- Packaging: [docs/packaging.md](docs/packaging.md)
- Development: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- Release checklist: [docs/RELEASING.md](docs/RELEASING.md)
- Changelog: [CHANGELOG.md](CHANGELOG.md)

## Getting started (dev)
- Clone the repo and open it in Xcode or run the scripts directly.
- Launch once, then toggle providers in Settings → Providers.
- Install/sign in to the Codex and Claude sources you rely on (CLIs, browser cookies, or OAuth).
- Optional: set OpenAI cookies (Automatic or Manual) for Codex dashboard extras.

## Build from source
Requires macOS 14+ and Swift 6.2+.

```bash
./Scripts/package_app.sh        # builds CodexBar.app in-place with ad-hoc signing
open CodexBar.app
```

Dev loop:
```bash
./Scripts/compile_and_run.sh
./Scripts/compile_and_run.sh --test  # also run the sharded test suite before packaging/relaunching
make check                           # SwiftFormat + SwiftLint
make docs-list                       # list docs with frontmatter summaries
```

CLI install:
```bash
# after installing CodexBar.app in /Applications
./bin/install-codexbar-cli.sh
```

## Related
- ✂️ [Trimmy](https://github.com/steipete/Trimmy) — “Paste once, run once.” Flatten multi-line shell snippets so they paste and run.
- 🧳 [MCPorter](https://mcporter.dev) — TypeScript toolkit + CLI for Model Context Protocol servers.
- 🧿 [oracle](https://askoracle.dev) — Ask the oracle when you're stuck. Invoke GPT-5 Pro with a custom context and files.

## Looking for a Windows version?
- [Win-CodexBar](https://github.com/Finesssee/Win-CodexBar)
- [CodexBar for Windows](https://github.com/hinneslung/CodexBar-for-Windows) — Native Windows tray app powered by the original CodexBar CLI through WSL2; x64 and ARM64 installers.

## Linux desktop integration?
- [Linux desktop app](Integrations/Linux/README.md) — x86_64/ARM64 release archives with an installer; Qt 6 usage and spending windows, separate settings, optional system tray, and desktop notifications using the Linux CLI.
- [Omarchy native widget](Integrations/Omarchy/README.md) — Compact Quickshell usage popup sharing the Linux desktop app’s backend.
- [codexbar-waybar](https://github.com/Marouan-chak/codexbar-waybar) — Waybar custom module + GTK4 popover for Hyprland / Sway / other Wayland compositors, built on top of the bundled Linux CLI.
- [codexbar-cosmic-applet](https://github.com/andrew-verde/codexbar-cosmic-applet) — Native COSMIC (System76) desktop panel applet with a tab per provider, pace projections, and cost/token stats, built on top of the bundled Linux CLI.
- [Codexbar GNOME](https://extensions.gnome.org/extension/9841/codexbar/) — GNOME Shell extension that brings CodexBar usage into the desktop panel.
- [codexbar-cinnamon-applet](https://github.com/jacobcalvert/codexbar-cinnamon-applet) — Linux Mint Cinnamon panel applet powered by CodexBar's JSON output.
- [noctalia-codex-usage](https://github.com/rayoplateado/noctalia-codex-usage) — Noctalia/Quickshell plugin that shows Codex 5-hour and weekly usage limits, built on top of the bundled Linux CLI.
- [KodexBar](https://github.com/tylxr59/KodexBar) — KDE Plasma widget that shows CodexBar usage in the Plasma panel, built on top of the bundled Linux CLI.
- [codexbar-plasmoid](https://github.com/psimaker/codexbar-plasmoid) — KDE Plasma 6 widget for CodexBar's meter icon, provider switcher, quota windows, pace, credits, local cost, and status, powered by the bundled Linux CLI.
- [CodexBar Plasma](https://github.com/Lucenx9/codexbar-plasma) — KDE Plasma 6 widget with multi-provider views, account selection, cost history, notifications, configurable providers, and installable `.plasmoid` releases, powered by the bundled Linux CLI.
- [CodexBar AgentView](https://github.com/materemias/codexbar-agentview) — KDE Plasma 6 widget with usage meters, agent-session search, terminal focus, and kitty session restoration, powered by the bundled Linux CLI.
- [CodexBar Meter](https://github.com/noctalia-dev/community-plugins/tree/main/codexbar-meter) — Noctalia v5 bar widget and panel showing every enabled provider's quota windows, credits, and pace, installable from Noctalia's plugin store, built on the bundled Linux CLI.

## Desk display
- [AI Monitor](https://github.com/tobymarks/esp32-ai-monitor) — ESP32 desk display (Cheap Yellow Display) plus a macOS companion app that shows Claude, ChatGPT, Gemini, Copilot, Cursor and Antigravity limits as rings or bars, fed over USB by the bundled CLI. No Wi-Fi on the device, 3D-printable case.
- [TokenTV](https://github.com/click6067-ship-it/token-tv) — Python host that shows Claude and Codex 5-hour and weekly limits on compatible 240×240 Wi-Fi desk clocks (GeekMagic SmallTV style), using the bundled CLI or `codexbar serve`. It uploads rendered screens to the clock's stock photo album without changing its firmware.

## Status bar & terminal integration
- [showy-quota](https://github.com/enieuwy/showy-quota) — always-on AI plan quota strips for SketchyBar, tmux, and Zellij (standalone WASM plugin), built on `codexbar serve` / the bundled CLI.
- [AI Usage Limits](https://github.com/lenadweb/stream-deck-ai-limits) — Elgato Stream Deck integration for macOS: shows a selected CodexBar provider, account, and configurable quota or payload metrics on keys and Stream Deck+ dials, using local `codexbar serve`.

## Phone & web

- [Starbridge](https://github.com/T0mSIlver/starbridge) — Community-maintained Android and web app that displays quota windows from the CodexBar CLI on macOS and Linux, with optional quota alerts.
- [Notify! CodexBar](https://github.com/simplytoast1/notify-codexbar) — Community-maintained macOS companion that reads CodexBar CLI or local `codexbar serve` output and sends selected usage through [Notify!](https://getnotifyapp.com/) for iPhone/iPad widgets, Live Activities, and quota notifications.

## Credits
Inspired by [ccusage](https://github.com/ryoppippi/ccusage) (MIT), specifically the cost usage tracking.

## License
MIT • Peter Steinberger ([steipete](https://twitter.com/steipete))
