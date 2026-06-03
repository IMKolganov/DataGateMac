#!/bin/bash
# Keep a single Launch Services entry for DataGateMac (/Applications by default).
set -euo pipefail

KEEP_APP="${1:-/Applications/DataGateMac.app}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_HELPER="$(mktemp /tmp/datagate-ls-urls.XXXXXX.swift)"
trap 'rm -f "$SWIFT_HELPER"' EXIT

canonical_path() {
  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null || realpath "$1" 2>/dev/null || echo "$1"
}

KEEP_CANON="$(canonical_path "$KEEP_APP")"

unregister_app() {
  local app="$1"
  [[ -n "$app" ]] || return 0
  if [[ -d "$app" ]]; then
    local canon
    canon="$(canonical_path "$app")"
    [[ "$canon" == "$KEEP_CANON" ]] && return 0
  fi
  if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -u "$app" 2>/dev/null || true
    echo "Unregistered: $app"
  fi
}

cat > "$SWIFT_HELPER" <<SWIFT
import Foundation
import CoreServices

let keep = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath().path
let id = "imkolganov.DataGateMac" as CFString
guard let urls = LSCopyApplicationURLsForBundleIdentifier(id, nil)?.takeRetainedValue() as? [URL] else {
    exit(0)
}
for url in urls {
    let path = url.resolvingSymlinksInPath().path
    if path != keep {
        print(path)
    }
}
SWIFT

# Unmount installer DMG volumes — Finder registers apps on /Volumes/DataGateMac*.
while IFS= read -r vol; do
  [[ -n "$vol" ]] || continue
  hdiutil detach "$vol" -force 2>/dev/null || true
done < <(ls -d /Volumes/DataGateMac* 2>/dev/null || true)

while IFS= read -r app; do
  unregister_app "$app"
done < <(swift "$SWIFT_HELPER" "$KEEP_APP" 2>/dev/null || true)

while IFS= read -r app; do
  unregister_app "$app"
done < <(mdfind "kMDItemCFBundleIdentifier == 'imkolganov.DataGateMac'" 2>/dev/null || true)

unregister_app "$REPO_DIR/dist/export/DataGateMac.app"
unregister_app "$REPO_DIR/dist/DataGateMac.xcarchive/Products/Applications/DataGateMac.app"
unregister_app "$REPO_DIR/DataGateMac/build/Debug/DataGateMac.app"
unregister_app "$HOME/Library/Developer/Xcode/DerivedData/DataGateMac-fkhtnirgittrncacjzaklbeyhrgi/Build/Products/Debug/DataGateMac.app"
unregister_app "$HOME/Library/Developer/Xcode/DerivedData/DataGateMac-fkhtnirgittrncacjzaklbeyhrgi/Index.noindex/Build/Products/Debug/DataGateMac.app"

if [[ -d "$REPO_DIR/dist" ]]; then
  mdutil -i off "$REPO_DIR/dist" >/dev/null 2>&1 || true
fi

if [[ -d "$KEEP_APP" && -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f -R -trusted "$KEEP_APP" 2>/dev/null || true
  echo "Registered: $KEEP_APP"
fi

killall Finder 2>/dev/null || true

COUNT="$(swift -framework CoreServices -framework Foundation -e 'import Foundation, CoreServices; let id = "imkolganov.DataGateMac" as CFString; print((LSCopyApplicationURLsForBundleIdentifier(id, nil)?.takeRetainedValue() as? [URL])?.count ?? 0)' 2>/dev/null || echo "?")"
echo "Launch Services bundle URLs: $COUNT"
