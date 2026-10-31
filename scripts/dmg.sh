#!/usr/bin/env bash
# Builds build/ScreenCap.app via bundle.sh, then packs dist/ScreenCap-<version>.dmg
# (app + Applications symlink, compressed UDZO). Version comes from ScreenCapKit.version.
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

mkdir -p dist
rm -f "$DMG"
hdiutil create -volname "ScreenCap $VERSION" -srcfolder "$STAGE" -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
echo "Built $ROOT/$DMG"
