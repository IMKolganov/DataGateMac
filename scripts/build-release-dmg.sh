#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$REPO_DIR/DataGateMac/DataGateMac.xcodeproj"
SCHEME="DataGateMac"
DIST_DIR="$REPO_DIR/dist"
ARCHIVE_PATH="$DIST_DIR/DataGateMac.xcarchive"
EXPORT_DIR="$DIST_DIR/export"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$SCRIPT_DIR/export-options-developer-id.plist}"
APP_NAME="DataGateMac.app"
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

if [[ ! -f "$EXPORT_OPTIONS_PLIST" ]]; then
  echo "Export options plist not found: $EXPORT_OPTIONS_PLIST"
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "Developer ID Application certificate not found in keychain."
  echo "Install a Developer ID Application certificate before building a public notarized release."
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR" "$DMG_PATH"

echo "Archiving Release build..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "platform=macOS" \
  archive \
  -archivePath "$ARCHIVE_PATH"

echo "Exporting Developer ID app..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Exported app not found: $APP_PATH"
  exit 1
fi

echo "Verifying app signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Building DMG..."
bash "$SCRIPT_DIR/build-dmg.sh" "$APP_PATH"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG was not created: $DMG_PATH"
  exit 1
fi

echo
echo "Release app: $APP_PATH"
echo "Release DMG: $DMG_PATH"
echo "Next step: notarize the DMG with scripts/notarize-dmg.sh"
