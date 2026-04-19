#!/bin/bash
# See whether PlugInKit lists the packet tunnel (compare with system log "Found 0 registrations").
APP="${1:-/Applications/DataGateMac.app}"
echo "=== App ==="
echo "$APP"
echo ""
echo "=== pluginkit (verbose, filter DataGate / PacketTunnel) ==="
pluginkit -mDv 2>/dev/null | grep -iE "datagate|packettunnel|imkolganov" || echo "(no matching lines)"
echo ""
echo "=== codesign verify ==="
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1
echo ""
echo "=== Appex verify ==="
codesign --verify --deep --strict --verbose=2 "$APP/Contents/PlugIns/DataGateMacPacketTunnel.appex" 2>&1
