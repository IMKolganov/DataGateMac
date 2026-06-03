#!/bin/bash
# Check whether the host Developer ID provisioning profile authorizes sysex install.
set -euo pipefail

APP_ID="imkolganov.DataGateMac"
TEAM_PREFIX="RB28BRDVNP"
PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

found=0
for profile_path in "$PROFILE_DIR"/*.provisionprofile; do
  [[ -f "$profile_path" ]] || continue
  tmp="$(mktemp)"
  if ! security cms -D -i "$profile_path" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    continue
  fi
  profile_app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$tmp" 2>/dev/null || true)"
  profile_name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$tmp" 2>/dev/null || true)"
  created="$(/usr/libexec/PlistBuddy -c 'Print :CreationDate' "$tmp" 2>/dev/null || true)"
  has_sysex_install="$(
    /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.system-extension.install' "$tmp" >/dev/null 2>&1 && echo yes || echo no
  )"
  rm -f "$tmp"

  if [[ "$profile_app_id" != "${TEAM_PREFIX}.${APP_ID}" ]]; then
    continue
  fi
  if [[ "$profile_name" != *Developer\ ID* ]]; then
    continue
  fi

  found=1
  echo "Profile: $profile_name"
  echo "Path:    $profile_path"
  echo "Created: $created"
  if [[ "$has_sysex_install" == yes ]]; then
    echo "sysex-install: authorized (OK for VPN + release entitlements)"
    exit 0
  fi
  echo "sysex-install: MISSING"
  echo
  echo "Regenerate the profile on developer.apple.com:"
  echo "  1. Identifiers → $APP_ID → ensure System Extension is enabled"
  echo "  2. Profiles → DataGateMac Developer ID → Edit → Save"
  echo "  3. Download, double-click to install, then re-run this script"
  exit 1
done

if [[ "$found" -eq 0 ]]; then
  echo "Developer ID host profile not found for $APP_ID"
  exit 1
fi
