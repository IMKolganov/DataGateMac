#!/bin/bash
# Build, verify, and package DataGateMac for Apple Silicon (arm64) website distribution.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_DIR/dist"
APP_PATH="$DIST_DIR/export/DataGateMac.app"
DMG_PATH="$DIST_DIR/DataGateMac.dmg"
MANIFEST="$DIST_DIR/release-manifest.txt"
SHA256_FILE="$DIST_DIR/DataGateMac.dmg.sha256"
NOTARY_PROFILE="${NOTARY_PROFILE:-DataGateMacNotary}"

echo "=== DataGateMac Apple Silicon release pipeline ==="

bash "$SCRIPT_DIR/build-release-dmg.sh"

DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
APP_SHA256="$(shasum -a 256 "$APP_PATH/Contents/MacOS/DataGateMac" | awk '{print $1}')"
SYSEX="$(find "$APP_PATH/Contents/Library/SystemExtensions" -maxdepth 1 -name '*.systemextension' -print -quit)"
SYSEX_SHA256="$(shasum -a 256 "$SYSEX/Contents/MacOS/"* | awk '{print $1}')"
MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
SIGNING="$(codesign -dv "$APP_PATH" 2>&1 | sed -n 's/^Authority=Developer ID Application: /Developer ID Application: /p' | head -1)"
NOTARIZED="no"

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "Notary profile found; submitting for notarization..."
  bash "$SCRIPT_DIR/notarize-dmg.sh" "$NOTARY_PROFILE" "$DMG_PATH" "$APP_PATH"
  NOTARIZED="yes"
else
  echo "Notary profile '$NOTARY_PROFILE' not configured — skipping notarization."
  echo "Gatekeeper on other Macs will show 'unnotarized' until you run:"
  echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple-id> --team-id <team-id>"
  echo "  (notarytool prompts for app-specific password interactively; do not commit it)"
  echo "  NOTARY_PROFILE=$NOTARY_PROFILE $0"
fi

printf '%s  DataGateMac.dmg\n' "$DMG_SHA256" > "$SHA256_FILE"

{
  echo "DataGateMac release manifest"
  echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "Platform: macOS Apple Silicon (arm64) only"
  echo "Minimum macOS: 26.2 (see MACOSX_DEPLOYMENT_TARGET in project)"
  echo "Marketing version: $MARKETING_VERSION"
  echo "Build version: $BUILD_VERSION"
  echo "Bundle ID: imkolganov.DataGateMac"
  echo "Sysex ID: imkolganov.DataGateMac.PacketTunnel"
  echo "Signing: Developer ID Application: $SIGNING"
  echo "Notarized: $NOTARIZED"
  echo
  echo "Website download file:"
  echo "  Path: $DMG_PATH"
  echo "  Size: $(stat -f%z "$DMG_PATH") bytes"
  echo "  SHA-256: $DMG_SHA256"
  echo
  echo "Checksum file for website:"
  echo "  $SHA256_FILE"
  echo
  echo "Install: open DMG, drag DataGateMac.app to Applications, launch and approve system extension in System Settings."
} > "$MANIFEST"

echo
echo "=== Release ready (Apple Silicon) ==="
echo "DMG:       $DMG_PATH"
echo "SHA-256:   $DMG_SHA256"
echo "Manifest:  $MANIFEST"
echo "Notarized: $NOTARIZED"

if [[ "$NOTARIZED" == "yes" ]]; then
  spctl --assess --type execute -vv "$APP_PATH" 2>&1 | head -3 || true
fi
