#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_DIR/dist"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/datagate-dmg-stage.XXXXXX")"
VOL_NAME="DataGateMac"
APP_NAME="DataGateMac.app"
DMG_PATH="$DIST_DIR/${VOL_NAME}.dmg"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

mkdir -p "$DIST_DIR"

APP_SOURCE="${1:-}"
if [[ -z "$APP_SOURCE" ]]; then
  if [[ -d "$HOME/Applications/$APP_NAME" ]]; then
    APP_SOURCE="$HOME/Applications/$APP_NAME"
  elif [[ -d "/Applications/$APP_NAME" ]]; then
    APP_SOURCE="/Applications/$APP_NAME"
  else
    echo "App source not found. Pass path to DataGateMac.app as the first argument."
    echo "Example: $0 \"$HOME/Applications/$APP_NAME\""
    exit 1
  fi
fi

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "App source does not exist: $APP_SOURCE"
  exit 1
fi

echo "Using app: $APP_SOURCE"
cp -R "$APP_SOURCE" "$STAGE_DIR/$APP_NAME"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "DMG created: $DMG_PATH"
