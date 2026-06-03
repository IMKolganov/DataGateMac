#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_DIR/dist"
DMG_PATH="${2:-$DIST_DIR/DataGateMac.dmg}"
APP_PATH="${3:-$DIST_DIR/export/DataGateMac.app}"
PROFILE="${1:-${NOTARY_PROFILE:-}}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

require_command xcrun
require_command codesign

if [[ -z "$PROFILE" ]]; then
  echo "Usage: $0 <notarytool-keychain-profile> [dmg-path] [app-path]"
  echo "Example:"
  echo "  xcrun notarytool store-credentials DataGateMacNotary --apple-id <apple-id> --team-id <team-id>"
  echo "  (notarytool prompts for app-specific password interactively; do not commit it)"
  echo "  $0 DataGateMacNotary"
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH"
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  exit 1
fi

echo "Submitting DMG for notarization..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$PROFILE" --wait

echo "Stapling app..."
xcrun stapler staple "$APP_PATH"

echo "Stapling DMG..."
xcrun stapler staple "$DMG_PATH"

echo "Validating signatures..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
xcrun stapler validate "$APP_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type execute -vv "$APP_PATH"

echo
echo "Notarized app: $APP_PATH"
echo "Notarized DMG: $DMG_PATH"
