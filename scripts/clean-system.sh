#!/bin/bash
# Remove installed DataGateMac artifacts from this Mac (keeps repo source tree).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
BUNDLE_ID="imkolganov.DataGateMac"
SYSEX_ID="imkolganov.DataGateMac.PacketTunnel"

echo "== Stopping DataGateMac =="
pkill -x DataGateMac 2>/dev/null || true
scutil --nc stop "DataGate" 2>/dev/null || true
sleep 1

echo "== Removing VPN profile =="
cat > /tmp/datagate-remove-vpn.swift <<'SWIFT'
import Foundation
import NetworkExtension

final class Runner {
    var finished = false
    func run() {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error {
                print("VPN load error: \(error.localizedDescription)")
                self.finished = true
                return
            }
            let matches = (managers ?? []).filter { $0.localizedDescription == "DataGate" }
            if matches.isEmpty {
                print("No DataGate VPN profile")
                self.finished = true
                return
            }
            let group = DispatchGroup()
            for mgr in matches {
                group.enter()
                mgr.removeFromPreferences { err in
                    if let err { print("Remove error: \(err.localizedDescription)") }
                    else { print("Removed VPN profile") }
                    group.leave()
                }
            }
            group.notify(queue: .main) { self.finished = true }
        }
        let deadline = Date(timeIntervalSinceNow: 30)
        while !finished && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }
    }
}
Runner().run()
SWIFT
swift -framework NetworkExtension -framework Foundation /tmp/datagate-remove-vpn.swift 2>/dev/null || true

echo "== System extension =="
systemextensionsctl uninstall RB28BRDVNP "$SYSEX_ID" 2>&1 || echo "(sysex uninstall may need System Settings or reboot)"

echo "== Unmounting DMG volumes =="
while IFS= read -r vol; do
  [[ -n "$vol" ]] || continue
  hdiutil detach "$vol" -force 2>/dev/null || true
  echo "Detached: $vol"
done < <(ls -d /Volumes/DataGateMac* 2>/dev/null || true)

echo "== Removing installed apps =="
for APP in \
  "/Applications/DataGateMac.app" \
  "$HOME/Applications/DataGateMac.app"
do
  if [[ -d "$APP" ]]; then
    [[ -x "$LSREGISTER" ]] && "$LSREGISTER" -u "$APP" 2>/dev/null || true
    rm -rf "$APP"
    echo "Removed: $APP"
  fi
done

echo "== Removing build artifacts in repo =="
rm -rf \
  "$REPO_DIR/dist" \
  "$REPO_DIR/DataGateMac/build" \
  "$HOME/Library/Developer/Xcode/DerivedData/DataGateMac-"* \
  2>/dev/null || true
echo "Removed dist/, DataGateMac/build/, DerivedData"

echo "== User Library data =="
USER_PATHS=(
  "$HOME/Library/Containers/$BUNDLE_ID"
  "$HOME/Library/Containers/$SYSEX_ID"
  "$HOME/Library/Group Containers/group.$BUNDLE_ID"
  "$HOME/Library/Group Containers/RB28BRDVNP.DataGateMac"
  "$HOME/Library/Application Scripts/$BUNDLE_ID"
  "$HOME/Library/Application Scripts/group.$BUNDLE_ID"
  "$HOME/Library/Application Scripts/$SYSEX_ID"
  "$HOME/Library/Application Scripts/RB28BRDVNP.DataGateMac"
  "$HOME/Library/HTTPStorages/$BUNDLE_ID"
  "$HOME/Library/Caches/$BUNDLE_ID"
  "$HOME/Library/Preferences/$BUNDLE_ID.plist"
  "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
  "$HOME/Library/WebKit/$BUNDLE_ID"
)
for P in "${USER_PATHS[@]}"; do
  if [[ -e "$P" ]]; then
    rm -rf "$P" 2>/dev/null && echo "Removed: $P" || echo "Could not remove (TCC): $P"
  fi
done
defaults delete "$BUNDLE_ID" 2>/dev/null && echo "Cleared defaults: $BUNDLE_ID" || true

echo "== Launch Services cleanup =="
if [[ -x "$REPO_DIR/scripts/unregister-duplicate-apps.sh" ]]; then
  # Unregister everything; no keep path since we removed /Applications copy.
  while IFS= read -r app; do
    [[ -n "$app" ]] && "$LSREGISTER" -u "$app" 2>/dev/null || true
  done < <(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null || true)
fi
for p in \
  "/Volumes/DataGateMac/DataGateMac.app" \
  "/Volumes/DataGateMac 1/DataGateMac.app" \
  "/Volumes/DataGateMac 2/DataGateMac.app" \
  "/private/tmp/DataGateMacDerivedData/Build/Products/Debug/DataGateMac.app" \
  "/private/tmp/DataGateMacSignedDerivedData/Build/Products/Debug/DataGateMac.app"
do
  "$LSREGISTER" -u "$p" 2>/dev/null || true
done
killall Finder 2>/dev/null || true

echo
echo "== Verification =="
ls -d /Applications/DataGateMac.app "$HOME/Applications/DataGateMac.app" 2>&1 | grep -v "No such file" || echo "Apps: none"
ls -d "$REPO_DIR/dist" 2>&1 | grep -v "No such file" || echo "dist/: removed"
scutil --nc list 2>&1 | grep -i datagate || echo "VPN profile: none"
systemextensionsctl list 2>&1 | grep -i datagate || echo "Sysex: none active (or pending reboot)"
mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null | head -5 || echo "Spotlight apps: none"
find /Library/SystemExtensions -maxdepth 2 -name '*imkolganov.DataGateMac*' 2>/dev/null | head -5 || echo "Sysex dirs: none or SIP-protected"
echo
echo "Done. Reboot if sysex still listed. Repo source at $REPO_DIR was kept."
