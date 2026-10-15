#!/usr/bin/env bash
# Build a release bundle signed with a local Apple Development identity and install it into
# /Applications. A stable signing identity keeps macOS privacy grants (Full Disk Access for
# Safari cookie import) valid across rebuilds; ad-hoc builds lose them every time.
#
# The identity and Team ID are detected from the login keychain's code-signing certificates;
# override with LOCAL_SIGNING_IDENTITY / LOCAL_TEAM_ID. Never auto-updates to upstream.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TARGET="/Applications/CodexBar.app"

IDENTITY="${LOCAL_SIGNING_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -p codesigning -v | sed -nE 's/.*"(Apple Development: [^"]+)".*/\1/p' | head -1)
fi
if [[ -z "$IDENTITY" ]]; then
  echo "ERROR: No Apple Development signing identity found; set LOCAL_SIGNING_IDENTITY." >&2
  exit 1
fi

TEAM_ID="${LOCAL_TEAM_ID:-}"
if [[ -z "$TEAM_ID" ]]; then
  # Development certificate names end in a personal ID; the Team ID is the certificate's OU.
  TEAM_ID=$(security find-certificate -c "$IDENTITY" -p | openssl x509 -noout -subject -nameopt multiline |
    sed -nE 's/^ *organizationalUnitName *= *([A-Z0-9]{10})$/\1/p' | head -1)
fi
if [[ -z "$TEAM_ID" ]]; then
  echo "ERROR: Could not read the Team ID from '$IDENTITY'; set LOCAL_TEAM_ID." >&2
  exit 1
fi

cd "$ROOT"
CODEXBAR_SIGNING=identity APP_IDENTITY="$IDENTITY" APP_TEAM_ID="$TEAM_ID" ./Scripts/package_app.sh release

osascript -e 'quit app "CodexBar"' >/dev/null 2>&1 || true
for _ in {1..20}; do
  pgrep -x CodexBar >/dev/null || break
  sleep 0.5
done
pkill -x CodexBar 2>/dev/null || true

rm -rf "$TARGET"
ditto "$ROOT/CodexBar.app" "$TARGET"
codesign --verify --deep --strict "$TARGET"
open -g "$TARGET"
echo "Installed $(defaults read "$TARGET/Contents/Info.plist" CFBundleShortVersionString) to $TARGET"
