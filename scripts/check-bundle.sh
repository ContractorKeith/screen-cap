#!/usr/bin/env bash
# Checks a built app's Info.plist (#77): CFBundleVersion is a real build number (not the
# source plist's "1"), and CFBundleShortVersionString matches ScreenCapKit.version.
# Also (#92): Sparkle.framework is embedded, and every SwiftPM resource bundle the app needs is in
# Contents/Resources. Expected bundles are each `*.bundle` in BIN_DIR (the swift build output) plus
# KeyboardShortcuts_KeyboardShortcuts.bundle, which the Shortcuts pane traps without.
# Usage: scripts/check-bundle.sh [build/ScreenCap.app] [BIN_DIR]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/ScreenCap.app}"
BIN_DIR="${2:-}"
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
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "$SPARKLE" ]]; then
  echo "Sparkle.framework not embedded" >&2; fail=1
elif ! codesign --verify "$SPARKLE" 2>/dev/null; then
  echo "Sparkle.framework is not validly signed" >&2; fail=1
fi
expected=("KeyboardShortcuts_KeyboardShortcuts.bundle")
if [[ -n "$BIN_DIR" ]]; then
  for res in "$BIN_DIR"/*.bundle; do [[ -e "$res" ]] && expected+=("$(basename "$res")"); done
fi
for name in $(printf '%s\n' "${expected[@]}" | sort -u); do
  [[ -f "$APP/Contents/Resources/$name/Info.plist" ]] || {
    echo "Resource bundle $name missing from Contents/Resources" >&2; fail=1; }
done
# #142: a read-only file makes `xattr -d com.apple.quarantine` fail on it.
readonly_files="$(find "$APP" ! -type l ! -perm -u+w)"
if [[ -n "$readonly_files" ]]; then
  echo "Files not user-writable (bundle.sh must chmod -R u+w):" >&2; echo "$readonly_files" >&2; fail=1
fi
# #141: an ad-hoc cdhash requirement changes every build and loses the Screen Recording grant.
if codesign -dr - "$APP" 2>&1 | grep -q 'designated => cdhash'; then
  echo "Designated requirement is a cdhash; bundle.sh must pin it to the bundle identifier" >&2; fail=1
fi
(( fail == 0 )) || exit 1
echo "Bundle OK: $SHORT ($BUILD)"
