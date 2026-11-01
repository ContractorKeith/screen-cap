#!/usr/bin/env bash
# Builds build/ScreenCap.app via bundle.sh, then packs dist/ScreenCap-<version>.dmg
# (app, Applications symlink and a first-launch note, compressed UDZO). Version comes from ScreenCapKit.version.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(sed -nE 's/.*static let version = "([^"]+)".*/\1/p' \
  Packages/ScreenCapKit/Sources/ScreenCapKit/ScreenCapKit.swift)"
[[ -n "$VERSION" ]] || { echo "Could not read ScreenCapKit.version" >&2; exit 1; }

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Resources/Info.plist)"
if [[ "$PLIST_VERSION" != "$VERSION" ]]; then
  echo "Version mismatch: ScreenCapKit $VERSION, Info.plist $PLIST_VERSION" >&2
  exit 1
fi

scripts/bundle.sh

DMG="dist/ScreenCap-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ditto build/ScreenCap.app "$STAGE/ScreenCap.app"
ln -s /Applications "$STAGE/Applications"
# Not notarized yet (#128): say how to get past Gatekeeper, since macOS 15 dropped right-click → Open.
cat > "$STAGE/If ScreenCap won't open.txt" <<'TXT'
ScreenCap is not notarized yet, so macOS blocks it the first time.

macOS 15 and later:
  1. Drag ScreenCap to Applications and open it once. Click Done on the "Not Opened" dialog.
  2. System Settings > Privacy & Security, scroll to "ScreenCap was blocked", click Open Anyway.
  3. Authenticate, then open ScreenCap again.
  Or in Terminal: xattr -d com.apple.quarantine /Applications/ScreenCap.app

macOS 14: right-click ScreenCap.app > Open > Open.

After that it opens normally. Each new version you download needs this once.

Updating? If ScreenCap asks for Screen Recording although its toggle is already on, run
  tccutil reset ScreenCapture com.contractorkeith.screencap
in Terminal, then turn ScreenCap on again in System Settings.
TXT

mkdir -p dist
rm -f "$DMG"
hdiutil create -volname "ScreenCap $VERSION" -srcfolder "$STAGE" -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
echo "Built $ROOT/$DMG"
