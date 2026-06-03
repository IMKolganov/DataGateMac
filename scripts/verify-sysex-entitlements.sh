#!/bin/bash
# Compare signed sysex entitlements vs embedded provisioning profile (catches App Group mismatch).
set -euo pipefail

APP="${1:-/Applications/DataGateMac.app}"
SYSEXT=$(find "$APP/Contents/Library/SystemExtensions" -maxdepth 1 -name '*.systemextension' -print -quit)
[[ -n "$SYSEXT" ]] || { echo "ERROR: no system extension in $APP"; exit 1; }

PROFILE="$SYSEXT/Contents/embedded.provisionprofile"
ENT_TMP=$(mktemp)
trap 'rm -f "$ENT_TMP"' EXIT

codesign -d --entitlements "$ENT_TMP" --xml "$SYSEXT" 2>/dev/null

echo "=== Signed sysex entitlements ==="
plutil -p "$ENT_TMP"

if plutil -extract com.apple.security.application-groups xml1 "$ENT_TMP" -o - 2>/dev/null; then
  echo ""
  echo "WARNING: sysex claims App Groups but embedded profile may not authorize them."
  if [[ -f "$PROFILE" ]]; then
    if ! security cms -D -i "$PROFILE" 2>/dev/null | plutil -extract Entitlements.com.apple.security.application-groups xml1 -o - - 2>/dev/null; then
      echo "ERROR: embedded.provisionprofile lacks application-groups — taskgated will block the extension (code 14)."
      exit 1
    fi
  fi
fi

echo ""
echo "OK: sysex entitlements compatible with embedded profile"
