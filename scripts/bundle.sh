#!/usr/bin/env bash
# Builds a release binary and assembles an ad-hoc signed build/ScreenCap.app.
# Set SIGN_IDENTITY to a Developer ID to sign for notarization (release.yml shows where).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="build/ScreenCap.app"
CONTENTS="$APP/Contents"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"
cp "$BIN_DIR/ScreenCap" "$CONTENTS/MacOS/ScreenCap"
# Sparkle ships as a dynamic framework; embed it (ditto keeps its symlinks) and point the rpath at it.
ditto "$BIN_DIR/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/ScreenCap"
cp App/Resources/Info.plist "$CONTENTS/Info.plist"
# CFBundleVersion is the build number Sparkle compares (sparkle:version), so it must increase every
# release: the git commit count. CFBundleShortVersionString comes from ScreenCapKit.version.
VERSION="$(sed -nE 's/.*static let version = "([^"]+)".*/\1/p' \
  Packages/ScreenCapKit/Sources/ScreenCapKit/ScreenCapKit.swift)"
[[ -n "$VERSION" ]] || { echo "Could not read ScreenCapKit.version" >&2; exit 1; }
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || true)}"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ && "$BUILD_NUMBER" -gt 1 ]] || {
  echo "Bad build number '$BUILD_NUMBER' (needs full git history; set BUILD_NUMBER to override)" >&2; exit 1; }
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Placeholder icon, drawn programmatically (original artwork).
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

plutil -lint "$CONTENTS/Info.plist" >/dev/null
# Ad-hoc by default. --deep also signs Sparkle's nested helpers (Autoupdate, Updater.app, XPC services).
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --verbose=1 "$APP"
scripts/check-bundle.sh "$APP"
echo "Built $ROOT/$APP"
