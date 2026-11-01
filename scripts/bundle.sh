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
# SwiftPM resource bundles (KeyboardShortcuts' localizations, #92). codesign forbids the app root, where
# the generated Bundle.module looks, so they go in Resources; App/ResourceBundles.swift redirects there.
shopt -s nullglob
for res in "$BIN_DIR"/*.bundle; do
  ditto "$res" "$CONTENTS/Resources/$(basename "$res")"
done
shopt -u nullglob
cp App/Resources/Info.plist "$CONTENTS/Info.plist"
scripts/stamp-version.sh "$CONTENTS/Info.plist" # build number and version (#77)
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Placeholder icon, drawn programmatically (original artwork).
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

plutil -lint "$CONTENTS/Info.plist" >/dev/null
# SwiftPM copies some resources read-only (0444); make everything user-writable so
# `xattr -d com.apple.quarantine` and later updates can touch every file (#142).
chmod -R u+w "$APP"

# Sparkle's nested helpers (Autoupdate, Updater.app, XPC services) are signed first, on their own,
# so the app's identifier and requirement below don't leak into them.
ID="com.contractorkeith.screencap"
ENTITLEMENTS="App/Resources/ScreenCap.entitlements"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$CONTENTS/Frameworks/Sparkle.framework"
  # Ad hoc: the default designated requirement is the cdhash, which changes every build, so macOS
  # treats each build as a new app for Screen Recording. Pin it to the bundle identifier (#141).
  codesign --force --sign - --identifier "$ID" --entitlements "$ENTITLEMENTS" \
    --requirements "=designated => identifier \"$ID\"" "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$CONTENTS/Frameworks/Sparkle.framework"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" --identifier "$ID" \
    --entitlements "$ENTITLEMENTS" "$APP"
fi
codesign --verify --verbose=1 "$APP"
scripts/check-bundle.sh "$APP" "$BIN_DIR"
echo "Built $ROOT/$APP"
