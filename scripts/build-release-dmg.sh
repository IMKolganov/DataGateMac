#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$REPO_DIR/DataGateMac/DataGateMac.xcodeproj"
SCHEME="DataGateMac"
DIST_DIR="$REPO_DIR/dist"
ARCHIVE_PATH="$DIST_DIR/DataGateMac.xcarchive"
EXPORT_DIR="$DIST_DIR/export"
APP_NAME="DataGateMac.app"
ARCHIVE_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
APP_PATH="$EXPORT_DIR/$APP_NAME"
DMG_PATH="$DIST_DIR/DataGateMac.dmg"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

require_command xcodebuild
require_command codesign
require_command security

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "Developer ID Application certificate not found in keychain."
  echo "Install a Developer ID Application certificate before building a public release."
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$DMG_PATH"

echo "Archiving Release build (dev entitlements in archive; Developer ID applied during re-sign)..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  archive \
  -archivePath "$ARCHIVE_PATH"

if [[ ! -d "$ARCHIVE_APP" ]]; then
  echo "Archived app not found: $ARCHIVE_APP"
  exit 1
fi

mkdir -p "$EXPORT_DIR"
echo "Copying app from archive..."
ditto "$ARCHIVE_APP" "$APP_PATH"

CONFIG_PLIST="$REPO_DIR/DataGateMac/DataGateMac/Config.plist"
if [[ ! -f "$CONFIG_PLIST" ]]; then
  echo "Config.plist not found at $CONFIG_PLIST"
  echo "The GitHub DMG needs APIBaseURL and GIDClientID; copy Config.example.plist to Config.plist first."
  exit 1
fi
echo "Embedding Config.plist into app Resources..."
mkdir -p "$APP_PATH/Contents/Resources"
cp "$CONFIG_PLIST" "$APP_PATH/Contents/Resources/Config.plist"

echo "Re-signing for Developer ID distribution..."
bash "$SCRIPT_DIR/resign-developer-id-app.sh" "$APP_PATH"

echo "Running release verification..."
bash "$SCRIPT_DIR/verify-release-app.sh" "$APP_PATH"

echo "Building DMG..."
bash "$SCRIPT_DIR/build-dmg.sh" "$APP_PATH"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG was not created: $DMG_PATH"
  exit 1
fi

bash "$SCRIPT_DIR/unregister-duplicate-apps.sh" "/Applications/DataGateMac.app"

echo
echo "Release app: $APP_PATH"
echo "Release DMG: $DMG_PATH"
echo
echo "Next step (requires Apple ID app-specific password):"
echo "  xcrun notarytool store-credentials DataGateMacNotary --apple-id <apple-id> --team-id <team-id>"
echo "  (notarytool prompts for app-specific password interactively; do not commit it)"
echo "  $SCRIPT_DIR/notarize-dmg.sh DataGateMacNotary"
