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

# Sparkle's nested helpers (Autoupdate, Updater.app, XPC services) are signed first, on their own.
#
# Ad hoc (default): codesign's default designated requirement is the cdhash. It changes every build,
# so macOS asks for Screen Recording again after each rebuild or update; the welcome window walks
# the user through that. Never pin it to the identifier alone: with no certificate to anchor to,
# any ad-hoc app claiming our identifier would inherit the grant (#146).
#
# Developer ID: set SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" (release.yml shows
# where). The default requirement is then anchored to Apple and the team ID, so grants persist
# across updates and can't be forged. Not used yet: there is no Apple Developer account.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$CONTENTS/Frameworks/Sparkle.framework"
  codesign --force --sign - "$APP"
else
  # --- Developer ID path (only when SIGN_IDENTITY is set) ---
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$CONTENTS/Frameworks/Sparkle.framework"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --verbose=1 "$APP"
scripts/check-bundle.sh "$APP" "$BIN_DIR"
echo "Built $ROOT/$APP"
