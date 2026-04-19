#!/bin/bash
# Offline checks for packet tunnel embedding and signing. Does not fix code 14 by itself.
# Usage:
#   ./scripts/diagnose-vpn-extension.sh
#   ./scripts/diagnose-vpn-extension.sh /Applications/DataGateMac.app
#   ./scripts/diagnose-vpn-extension.sh "$HOME/Library/Developer/Xcode/DerivedData/.../Debug/DataGateMac.app"
set -euo pipefail

EXPECTED_BUNDLE_ID="imkolganov.DataGateMac.PacketTunnel"
EXPECTED_POINT="com.apple.networkextension.packet-tunnel"
APP="${1:-/Applications/DataGateMac.app}"

echo "=== Target app ==="
echo "$APP"
if [[ ! -d "$APP" ]]; then
  echo "ERROR: App not found. Build first, then pass path to DataGateMac.app"
  exit 1
fi

echo ""
echo "=== PlugIns listing ==="
PLUGINS="$APP/Contents/PlugIns"
if [[ ! -d "$PLUGINS" ]]; then
  echo "ERROR: Missing Contents/PlugIns — extension not embedded."
  exit 1
fi
ls -la "$PLUGINS"

APPEX="$PLUGINS/DataGateMacPacketTunnel.appex"
echo ""
echo "=== Packet tunnel appex ==="
if [[ ! -d "$APPEX" ]]; then
  echo "ERROR: DataGateMacPacketTunnel.appex not found."
  exit 1
fi

INFO="$APPEX/Contents/Info.plist"
echo "Info.plist: $INFO"
if [[ -f "$INFO" ]]; then
  echo -n "CFBundleIdentifier: "
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO" 2>/dev/null || echo "(read failed)"
  BID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO" 2>/dev/null || true)
  if [[ "$BID" == "$EXPECTED_BUNDLE_ID" ]]; then
    echo "Bundle ID: OK (matches providerBundleIdentifier)"
  else
    echo "Bundle ID: MISMATCH — expected $EXPECTED_BUNDLE_ID got ${BID:-empty}"
  fi
  echo -n "NSExtensionPointIdentifier: "
  /usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$INFO" 2>/dev/null || echo "(missing)"
  POINT=$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$INFO" 2>/dev/null || true)
  if [[ "$POINT" != "$EXPECTED_POINT" ]]; then
    echo "WARNING: expected $EXPECTED_POINT"
  fi
else
  echo "ERROR: Info.plist missing"
fi

EXE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO" 2>/dev/null || true)
if [[ -n "$EXE_NAME" ]]; then
  EXE_PATH="$APPEX/Contents/MacOS/$EXE_NAME"
  echo "Executable path: $EXE_PATH"
  if [[ -f "$EXE_PATH" ]]; then
    echo "Executable on disk: OK"
  else
    echo "ERROR: Executable file missing"
  fi
fi

echo ""
echo "=== codesign (app) ==="
codesign -dv --verbose=4 "$APP" 2>&1 || true

echo ""
echo "=== codesign (appex) ==="
codesign -dv --verbose=4 "$APPEX" 2>&1 || true

echo ""
echo "=== pluginkit (filter: DataGate) ==="
if command -v pluginkit >/dev/null 2>&1; then
  pluginkit -m -v -p 2>/dev/null | grep -i datagate || echo "(no DataGate lines — normal if app not registered for this user)"
else
  echo "pluginkit not found"
fi

echo ""
echo "=== Optional: refresh Launch Services registration ==="
echo "sudo lsregister -f \"$APP\""
echo "(run manually if you suspect stale DB)"
