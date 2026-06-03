#!/bin/bash
# Verify Info.plist keys required for network extension system extension activation.
set -euo pipefail

APP="${1:-/Applications/DataGateMac.app}"
HOST_PLIST="$APP/Contents/Info.plist"
SYSEXT_DIR="$APP/Contents/Library/SystemExtensions"
USAGE_KEY="NSSystemExtensionUsageDescription"

fail() {
  echo "ERROR: $1"
  exit 1
}

[[ -d "$APP" ]] || fail "App not found: $APP"

echo "=== Host app ==="
echo "$HOST_PLIST"
/usr/libexec/PlistBuddy -c "Print :$USAGE_KEY" "$HOST_PLIST" >/dev/null 2>&1 \
  || fail "Host app missing $USAGE_KEY"
echo "OK: host has $USAGE_KEY"

echo ""
echo "=== System extension ==="
[[ -d "$SYSEXT_DIR" ]] || fail "Missing Contents/Library/SystemExtensions"
found=0
while IFS= read -r bundle; do
  found=1
  plist="$bundle/Contents/Info.plist"
  echo "$bundle"
  [[ -f "$plist" ]] || fail "Missing Info.plist in $bundle"
  /usr/libexec/PlistBuddy -c "Print :$USAGE_KEY" "$plist" >/dev/null 2>&1 \
    || fail "System extension missing $USAGE_KEY: $bundle"
  /usr/libexec/PlistBuddy -c 'Print :NetworkExtension:NEProviderClasses:com.apple.networkextension.packet-tunnel' "$plist" >/dev/null 2>&1 \
    || fail "System extension missing packet-tunnel NEProviderClasses: $bundle"
  echo "OK: sysex has $USAGE_KEY and packet-tunnel provider class"
done < <(find "$SYSEXT_DIR" -maxdepth 1 -name '*.systemextension' -print)
[[ "$found" -eq 1 ]] || fail "No .systemextension bundles under $SYSEXT_DIR"

echo ""
echo "All checks passed for $APP"
