#!/usr/bin/env bash
# Writes dist/appcast.xml from the DMGs in dist/ with Sparkle's generate_appcast.
#
# One-time setup (maintainer machine):
#   1. swift package resolve   # downloads Sparkle's tools into .build/artifacts
#   2. .build/artifacts/sparkle/Sparkle/bin/generate_keys
#      Stores the private EdDSA key in your login Keychain and prints the public key.
#   3. Paste the public key into App/Resources/Info.plist as SUPublicEDKey (replacing
#      the REPLACE_WITH_... placeholder) and commit it. Until then the app's updater stays off.
#   Back up the private key (generate_keys -x <file>); losing it means users can't update.
#
# Per release: make dmg && scripts/appcast.sh, then attach dist/appcast.xml to the GitHub
# Release next to the DMG (the feed URL is releases/latest/download/appcast.xml).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TOOL=".build/artifacts/sparkle/Sparkle/bin/generate_appcast"
[[ -x "$TOOL" ]] || swift package resolve
[[ -x "$TOOL" ]] || { echo "generate_appcast not found at $TOOL" >&2; exit 1; }

KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' App/Resources/Info.plist)"
if [[ "$KEY" == REPLACE_WITH_* ]]; then
  echo "SUPublicEDKey is still the placeholder; run generate_keys first (see the top of this script)." >&2
  exit 1
fi

ls dist/*.dmg >/dev/null 2>&1 || { echo "No DMGs in dist/; run make dmg first." >&2; exit 1; }

# Downloads resolve to the release asset for each version's tag.
"$TOOL" --download-url-prefix "https://github.com/ContractorKeith/screen-cap/releases/download/v$(
  sed -nE 's/.*static let version = "([^"]+)".*/\1/p' Packages/ScreenCapKit/Sources/ScreenCapKit/ScreenCapKit.swift
)/" "$@" dist/
echo "Wrote $ROOT/dist/appcast.xml"
