#!/bin/bash
# Re-sign DataGateMac + embedded sysex for Developer ID distribution.
# Xcode exportArchive does not produce valid Developer ID NE sysex signatures (FB12163991).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${1:-}"
HOST_ENTITLEMENTS="${HOST_ENTITLEMENTS:-$REPO_DIR/DataGateMac/DataGateMac/DataGateMacRelease.entitlements}"
SYSEX_ENTITLEMENTS="${SYSEX_ENTITLEMENTS:-$REPO_DIR/DataGateMac/DataGateMacPacketTunnel/DataGateMacPacketTunnelRelease.entitlements}"
HOST_PROFILE="${HOST_PROFILE:-}"
SYSEX_PROFILE="${SYSEX_PROFILE:-}"
SIGN_ID="${SIGN_ID:-}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

find_profile_by_app_id() {
  local app_id="$1"
  local profile_path data name profile_app_id tmp
  for profile_path in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.provisionprofile; do
    [[ -f "$profile_path" ]] || continue
    tmp="$(mktemp)"
    if ! security cms -D -i "$profile_path" > "$tmp" 2>/dev/null; then
      rm -f "$tmp"
      continue
    fi
    name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$tmp" 2>/dev/null || true)"
    profile_app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$tmp" 2>/dev/null || true)"
    rm -f "$tmp"
    if [[ "$profile_app_id" == "RB28BRDVNP.${app_id}" ]] && [[ "$name" == *Developer\ ID* ]]; then
      printf '%s' "$profile_path"
      return 0
    fi
  done
  return 1
}

if [[ -z "$APP_PATH" ]]; then
  echo "Usage: $0 /path/to/DataGateMac.app"
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  exit 1
fi

require_command codesign
require_command security
require_command plutil

if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
if [[ -z "$SIGN_ID" ]]; then
  echo "Developer ID Application certificate not found in keychain."
  exit 1
fi

if [[ -z "$HOST_PROFILE" ]]; then
  HOST_PROFILE="$(find_profile_by_app_id "imkolganov.DataGateMac")" || {
    echo "Developer ID host provisioning profile not found for imkolganov.DataGateMac"
    exit 1
  }
fi

if [[ -z "$SYSEX_PROFILE" ]]; then
  SYSEX_PROFILE="$(find_profile_by_app_id "imkolganov.DataGateMac.PacketTunnel")" || {
    echo "Developer ID sysex provisioning profile not found for imkolganov.DataGateMac.PacketTunnel"
    exit 1
  }
fi

SYSEX="$(find "$APP_PATH/Contents/Library/SystemExtensions" -maxdepth 1 -name '*.systemextension' -print -quit)"
if [[ -z "$SYSEX" ]]; then
  echo "No system extension found in $APP_PATH"
  exit 1
fi

for entitlements in "$HOST_ENTITLEMENTS" "$SYSEX_ENTITLEMENTS"; do
  if [[ ! -f "$entitlements" ]]; then
    echo "Entitlements file not found: $entitlements"
    exit 1
  fi
done

echo "Signing identity: $SIGN_ID"
echo "Host profile: $HOST_PROFILE"
echo "Sysex profile: $SYSEX_PROFILE"
echo "Sysex bundle: $SYSEX"

cp "$HOST_PROFILE" "$APP_PATH/Contents/embedded.provisionprofile"
cp "$SYSEX_PROFILE" "$SYSEX/Contents/embedded.provisionprofile"

# Sign nested Mach-O files inside the sysex (static libs are linked into the main binary only).
SYSEX_EXECUTABLE="$SYSEX/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$SYSEX/Contents/Info.plist" 2>/dev/null || basename "$SYSEX" .systemextension)"
if [[ -f "$SYSEX_EXECUTABLE" ]]; then
  codesign --force --options runtime --timestamp \
    --entitlements "$SYSEX_ENTITLEMENTS" \
    --sign "$SIGN_ID" \
    "$SYSEX_EXECUTABLE"
fi

codesign --force --options runtime --timestamp \
  --entitlements "$SYSEX_ENTITLEMENTS" \
  --sign "$SIGN_ID" \
  "$SYSEX"

codesign --force --options runtime --timestamp \
  --entitlements "$HOST_ENTITLEMENTS" \
  --sign "$SIGN_ID" \
  "$APP_PATH"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "Developer ID re-sign complete: $APP_PATH"
