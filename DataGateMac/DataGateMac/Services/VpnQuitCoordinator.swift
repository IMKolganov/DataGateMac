//
//  VpnQuitCoordinator.swift
//  DataGateMac
//
//  Reads the system VPN profile (same name as VpnTunnelManager) so we can confirm quit
//  and stop the tunnel when the UI (HomePageView) is not on screen.
//

import Foundation
import NetworkExtension

enum VpnQuitCoordinator {
    /// Must match `VpnTunnelManager` when creating the profile (`localizedDescription`).
    private static let tunnelProfileLocalizedDescription = "DataGate"

    /// True when quitting should prompt (tunnel up or still negotiating).
    static func needsConfirmationBeforeQuitting() async -> Bool {
        guard let manager = await loadDataGateManager() else { return false }
        switch manager.connection.status {
        case .connected, .connecting, .reasserting:
            return true
        case .disconnecting, .disconnected, .invalid:
            return false
        @unknown default:
            return true
        }
    }

    static func stopDataGateTunnelIfPresent() async {
        guard let manager = await loadDataGateManager() else { return }
        manager.connection.stopVPNTunnel()
    }

    private static func loadDataGateManager() async -> NETunnelProviderManager? {
        await withCheckedContinuation { continuation in
            NETunnelProviderManager.loadAllFromPreferences { managers, _ in
                let list = managers ?? []
                let match = list.first { $0.localizedDescription == tunnelProfileLocalizedDescription }
                continuation.resume(returning: match)
            }
        }
    }
}
