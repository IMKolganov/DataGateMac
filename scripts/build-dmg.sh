#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_DIR/dist"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/datagate-dmg-stage.XXXXXX")"
VOL_NAME="DataGateMac"
APP_NAME="DataGateMac.app"
DMG_PATH="$DIST_DIR/${VOL_NAME}.dmg"
TEMP_RW_DMG="$DIST_DIR/${VOL_NAME}-temp.dmg"
WINDOW_BOUNDS="{120, 120, 760, 480}"
APP_ICON_POS="{180, 220}"
APPLICATIONS_ICON_POS="{500, 220}"
ICON_SIZE=128
TEXT_SIZE=14

cleanup() {
  rm -rf "$STAGE_DIR"
  rm -f "$TEMP_RW_DMG"
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
  -srcfolder "$STAGE_DIR" \
  -volname "$VOL_NAME" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$TEMP_RW_DMG" >/dev/null

MOUNT_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_RW_DMG")"
DEVICE="$(printf '%s\n' "$MOUNT_OUTPUT" | awk '/Apple_HFS/ {print $1; exit}')"
if [[ -z "$DEVICE" ]]; then
  echo "Failed to mount temporary DMG."
  exit 1
fi

VOLUME_PATH="/Volumes/$VOL_NAME"

osascript <<EOF
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to $WINDOW_BOUNDS
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to $ICON_SIZE
        set text size of theViewOptions to $TEXT_SIZE
        set position of item "$APP_NAME" of container window to $APP_ICON_POS
        set position of item "Applications" of container window to $APPLICATIONS_ICON_POS
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
EOF

sync
hdiutil detach "$DEVICE" >/dev/null

hdiutil convert "$TEMP_RW_DMG" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" >/dev/null

echo "DMG created: $DMG_PATH"
