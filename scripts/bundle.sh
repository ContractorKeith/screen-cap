#!/usr/bin/env bash
# Builds a release binary and assembles an ad-hoc signed build/ScreenCap.app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="build/ScreenCap.app"
CONTENTS="$APP/Contents"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/ScreenCap" "$CONTENTS/MacOS/ScreenCap"
cp App/Resources/Info.plist "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Placeholder icon, drawn programmatically (original artwork).
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

plutil -lint "$CONTENTS/Info.plist" >/dev/null
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=1 "$APP"
echo "Built $ROOT/$APP"
