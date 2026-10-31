#!/usr/bin/env bash
# Checks a built app's Info.plist (#77): CFBundleVersion is a real build number (not the
# source plist's "1"), and CFBundleShortVersionString matches ScreenCapKit.version.
# Usage: scripts/check-bundle.sh [build/ScreenCap.app]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/ScreenCap.app}"
PLIST="$APP/Contents/Info.plist"
[[ -f "$PLIST" ]] || { echo "No Info.plist at $PLIST (run make bundle)" >&2; exit 1; }

VERSION="$(sed -nE 's/.*static let version = "([^"]+)".*/\1/p' \
  "$ROOT/Packages/ScreenCapKit/Sources/ScreenCapKit/ScreenCapKit.swift")"
SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"

fail=0
if [[ "$SHORT" != "$VERSION" ]]; then
  echo "CFBundleShortVersionString is $SHORT, ScreenCapKit.version is $VERSION" >&2; fail=1
fi
if ! [[ "$BUILD" =~ ^[0-9]+$ ]] || (( BUILD <= 1 )); then
  echo "CFBundleVersion is '$BUILD'; bundle.sh must set it to the git commit count" >&2; fail=1
fi
[[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]] || { echo "Sparkle.framework not embedded" >&2; fail=1; }
(( fail == 0 )) || exit 1
echo "Bundle OK: $SHORT ($BUILD)"
