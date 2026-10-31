#!/usr/bin/env bash
# Stamps an Info.plist with the release version and build number (#77), called by bundle.sh.
# CFBundleVersion is the build number Sparkle compares (sparkle:version), so it must increase every
# release: the git commit count (override with BUILD_NUMBER). CFBundleShortVersionString comes from
# ScreenCapKit.version. Usage: scripts/stamp-version.sh <Info.plist>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="${1:?usage: stamp-version.sh <Info.plist>}"

VERSION="$(sed -nE 's/.*static let version = "([^"]+)".*/\1/p' \
  "$ROOT/Packages/ScreenCapKit/Sources/ScreenCapKit/ScreenCapKit.swift")"
[[ -n "$VERSION" ]] || { echo "Could not read ScreenCapKit.version" >&2; exit 1; }
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || true)}"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ && "$BUILD_NUMBER" -gt 1 ]] || {
  echo "Bad build number '$BUILD_NUMBER' (needs full git history; set BUILD_NUMBER to override)" >&2; exit 1; }
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
