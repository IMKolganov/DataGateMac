#!/bin/bash
# Copy the built DataGateMac.app to /Applications so the system VPN daemon can find
# the packet tunnel extension (avoids NE error code 14 when running from Xcode/DerivedData).
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED="${HOME}/Library/Developer/Xcode/DerivedData"
APP_NAME="DataGateMac.app"
# Find latest build (any DataGateMac-* folder)
BUILD_DIR=$(find "$DERIVED" -maxdepth 1 -type d -name "DataGateMac-*" 2>/dev/null | head -1)
if [ -z "$BUILD_DIR" ]; then
  echo "No DerivedData build found. Build the app in Xcode first (Product > Build)."
  exit 1
fi
SRC="$BUILD_DIR/Build/Products/Debug/$APP_NAME"
if [ ! -d "$SRC" ]; then
  echo "App not found at $SRC. Build the DataGateMac scheme in Xcode first."
  exit 1
fi
echo "Copying $SRC to /Applications/"
sudo rm -rf "/Applications/$APP_NAME"
sudo cp -R "$SRC" "/Applications/"
sudo chown -R "$(whoami):staff" "/Applications/$APP_NAME"
echo "Done. Run: open /Applications/$APP_NAME"
echo "Then tap Connect in the app."
