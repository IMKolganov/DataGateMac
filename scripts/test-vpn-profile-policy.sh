#!/bin/bash
# Unit-style checks for VpnProfileMigrationPolicy (no NetworkExtension / sysex required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="${TMPDIR:-/tmp}"
RUNNER="$TMPDIR/datagate-vpn-policy-test-$$.swift"
BIN="$TMPDIR/datagate-vpn-policy-test-$$"

cat >"$RUNNER" <<'SWIFT'
import Foundation

enum VpnProfileMigrationPolicy {
    struct ProfileSnapshot: Equatable {
        var savedProviderBundleIdentifier: String?
        var lastRecordedHostAppPath: String?
        var currentHostAppPath: String
        var hostAppBundleIdentifier: String
        var expectedProviderBundleIdentifier: String
        var hasExistingProfile: Bool
    }

    static func recreateReason(for profile: ProfileSnapshot) -> String? {
        if profile.hasExistingProfile, profile.lastRecordedHostAppPath == nil {
            return "migrating saved VPN profile to current app install"
        }
        if let last = profile.lastRecordedHostAppPath, last != profile.currentHostAppPath {
            return "host app path changed (\(last) -> \(profile.currentHostAppPath))"
        }
        let saved = profile.savedProviderBundleIdentifier ?? "(nil)"
        if saved == profile.hostAppBundleIdentifier {
            return "providerBundleIdentifier was host app id \(saved)"
        }
        if profile.savedProviderBundleIdentifier != profile.expectedProviderBundleIdentifier {
            return "providerBundleIdentifier mismatch (\(saved))"
        }
        return nil
    }

    static func isPacketTunnelUnavailableDisconnect(domain: String, code: Int) -> Bool {
        (domain == "NEVPNErrorDomain" || domain == "NEVPNConnectionErrorDomain") && code == 14
    }

    static func shouldRetryConnectAfterCode14(
        tunnelDisconnected: Bool,
        disconnectDomain: String?,
        disconnectCode: Int?,
        allowRetry: Bool
    ) -> Bool {
        guard allowRetry, tunnelDisconnected else { return false }
        guard let domain = disconnectDomain, let code = disconnectCode else { return false }
        return isPacketTunnelUnavailableDisconnect(domain: domain, code: code)
    }
}

func expectNil(_ value: String?, _ label: String) {
    guard value == nil else {
        fputs("FAIL \(label): expected nil, got \(value!)\n", stderr)
        exit(1)
    }
}

func expectEqual(_ lhs: String?, _ rhs: String, _ label: String) {
    guard lhs == rhs else {
        fputs("FAIL \(label): expected \(rhs), got \(lhs ?? "nil")\n", stderr)
        exit(1)
    }
}

func expectTrue(_ value: Bool, _ label: String) {
    guard value else {
        fputs("FAIL \(label): expected true\n", stderr)
        exit(1)
    }
}

func expectFalse(_ value: Bool, _ label: String) {
    guard !value else {
        fputs("FAIL \(label): expected false\n", stderr)
        exit(1)
    }
}

let hostId = "imkolganov.DataGateMac"
let sysexId = "imkolganov.DataGateMac.PacketTunnel"
let appsPath = "/Applications/DataGateMac.app"
let derivedPath = "/Users/me/DerivedData/DataGateMac.app"

func snapshot(
    saved: String? = sysexId,
    lastPath: String? = appsPath,
    currentPath: String = appsPath,
    hasProfile: Bool = true
) -> VpnProfileMigrationPolicy.ProfileSnapshot {
    VpnProfileMigrationPolicy.ProfileSnapshot(
        savedProviderBundleIdentifier: saved,
        lastRecordedHostAppPath: lastPath,
        currentHostAppPath: currentPath,
        hostAppBundleIdentifier: hostId,
        expectedProviderBundleIdentifier: sysexId,
        hasExistingProfile: hasProfile
    )
}

expectNil(VpnProfileMigrationPolicy.recreateReason(for: snapshot()), "current profile")
expectEqual(
    VpnProfileMigrationPolicy.recreateReason(for: snapshot(lastPath: nil)),
    "migrating saved VPN profile to current app install",
    "migration helper"
)
expectEqual(
    VpnProfileMigrationPolicy.recreateReason(for: snapshot(lastPath: derivedPath, currentPath: appsPath)),
    "host app path changed (\(derivedPath) -> \(appsPath))",
    "path change"
)
expectEqual(
    VpnProfileMigrationPolicy.recreateReason(for: snapshot(saved: hostId)),
    "providerBundleIdentifier was host app id \(hostId)",
    "stale host id"
)
expectNil(
    VpnProfileMigrationPolicy.recreateReason(for: snapshot(lastPath: nil, hasProfile: false)),
    "no profile without recorded path"
)
expectTrue(
    VpnProfileMigrationPolicy.shouldRetryConnectAfterCode14(
        tunnelDisconnected: true,
        disconnectDomain: "NEVPNErrorDomain",
        disconnectCode: 14,
        allowRetry: true
    ),
    "retry on code 14"
)
expectFalse(
    VpnProfileMigrationPolicy.shouldRetryConnectAfterCode14(
        tunnelDisconnected: true,
        disconnectDomain: "NEVPNErrorDomain",
        disconnectCode: 14,
        allowRetry: false
    ),
    "no retry when disabled"
)

print("OK: VpnProfileMigrationPolicy (\(8) checks)")
SWIFT

swiftc -o "$BIN" "$RUNNER"
"$BIN"
rm -f "$RUNNER" "$BIN"
