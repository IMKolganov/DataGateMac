#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-$SCRIPT_DIR/../dist/export/DataGateMac.app}"

if [[ ! -d "$APP" ]]; then
  echo "App not found: $APP"
  exit 1
fi

fail() {
  echo "VERIFY FAILED: $*"
  exit 1
}

echo "=== codesign verify ==="
codesign --verify --deep --strict --verbose=2 "$APP"

echo
echo "=== signing authority ==="
codesign -dv "$APP" 2>&1 | grep -E "Authority|Identifier|TeamIdentifier|Runtime" || true

SYSEX="$(find "$APP/Contents/Library/SystemExtensions" -maxdepth 1 -name '*.systemextension' -print -quit)"
[[ -n "$SYSEX" ]] || fail "missing embedded system extension"

echo
echo "=== sysex plist ==="
bash "$SCRIPT_DIR/verify-sysex-plist.sh" "$APP"

echo
echo "=== sysex entitlements vs profile ==="
bash "$SCRIPT_DIR/verify-sysex-entitlements.sh" "$APP"

HOST_ENT_TMP="$(mktemp)"
SYSEX_ENT_TMP="$(mktemp)"
trap 'rm -f "$HOST_ENT_TMP" "$SYSEX_ENT_TMP"' EXIT

codesign -d --entitlements "$HOST_ENT_TMP" --xml "$APP" 2>/dev/null
codesign -d --entitlements "$SYSEX_ENT_TMP" --xml "$SYSEX" 2>/dev/null

echo
echo "=== host NE entitlement ==="
/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.networking.networkextension' "$HOST_ENT_TMP" >/dev/null 2>&1 || fail "host missing NE entitlement"
grep -q "packet-tunnel-provider-systemextension" "$HOST_ENT_TMP" || fail "host must use packet-tunnel-provider-systemextension"

echo
echo "=== sysex NE entitlement ==="
/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.networking.networkextension' "$SYSEX_ENT_TMP" >/dev/null 2>&1 || fail "sysex missing NE entitlement"
grep -q "packet-tunnel-provider-systemextension" "$SYSEX_ENT_TMP" || fail "sysex must use packet-tunnel-provider-systemextension"

if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' "$SYSEX_ENT_TMP" >/dev/null 2>&1; then
  fail "sysex must not claim App Groups in release signing"
fi

echo
echo "=== host sysex-install vs Developer ID profile ==="
HOST_PROFILE_TMP="$(mktemp)"
security cms -D -i "$APP/Contents/embedded.provisionprofile" > "$HOST_PROFILE_TMP"
HOST_HAS_SYSEX_INSTALL_ENT="$(
  /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.system-extension.install' "$HOST_ENT_TMP" >/dev/null 2>&1 && echo yes || echo no
)"
HOST_PROFILE_HAS_SYSEX_INSTALL="$(
  /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.system-extension.install' "$HOST_PROFILE_TMP" >/dev/null 2>&1 && echo yes || echo no
)"
if [[ "$HOST_HAS_SYSEX_INSTALL_ENT" == yes && "$HOST_PROFILE_HAS_SYSEX_INSTALL" == no ]]; then
  fail "host claims com.apple.developer.system-extension.install but embedded Developer ID profile does not authorize it (macOS launch error 163). Regenerate the host Developer ID profile on developer.apple.com with System Extension enabled, or omit sysex-install from release entitlements."
fi
if [[ "$HOST_HAS_SYSEX_INSTALL_ENT" == no && "$HOST_PROFILE_HAS_SYSEX_INSTALL" == yes ]]; then
  fail "Developer ID profile authorizes sysex-install but host signature omits it; OSSystemExtensionRequest will fail at runtime"
fi
rm -f "$HOST_PROFILE_TMP"

echo
echo "=== embedded provisioning profiles ==="
[[ -f "$APP/Contents/embedded.provisionprofile" ]] || fail "host missing embedded.provisionprofile"
[[ -f "$SYSEX/Contents/embedded.provisionprofile" ]] || fail "sysex missing embedded.provisionprofile"
security cms -D -i "$APP/Contents/embedded.provisionprofile" | plutil -extract Name raw -o - -
security cms -D -i "$SYSEX/Contents/embedded.provisionprofile" | plutil -extract Name raw -o - -

echo
echo "=== Gatekeeper (requires notarization for clean pass off this Mac) ==="
if spctl --assess --type execute -vv "$APP" 2>&1; then
  echo "spctl: accepted"
else
  echo "spctl: not yet accepted (expected before notarization)"
fi

echo
echo "VERIFY OK: $APP"
