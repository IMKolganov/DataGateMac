//
//  VpnProfileMigrationPolicy.swift
//  DataGateMac
//
//  Pure decision logic for when to recreate the saved VPN profile (unit-testable).
//

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

    /// When non-nil, the saved VPN profile should be removed and recreated (new session UUID).
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

    /// Matches NEVPN / NEVPNConnection disconnect code 14 (extension not loaded).
    static func isPacketTunnelUnavailableDisconnect(domain: String, code: Int) -> Bool {
        (domain == "NEVPNErrorDomain" || domain == "NEVPNConnectionErrorDomain") && code == 14
    }

    /// After startVPNTunnel, retry once with a fresh profile when the tunnel failed immediately with code 14.
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
