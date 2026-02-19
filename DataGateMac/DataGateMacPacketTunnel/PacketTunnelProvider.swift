//
//  PacketTunnelProvider.swift
//  DataGateMacPacketTunnel
//
//  Packet Tunnel Provider: started by the system when the app calls startVPNTunnel().
//  Receives config (WSS + OVPN) via providerConfiguration; no ongoing IPC with the app.
//  Status is reported to the app indirectly via NEVPNStatus (system).
//

import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = Logger(subsystem: "imkolganov.DataGateMac.PacketTunnel", category: "Tunnel")

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // Config is in protocolConfiguration.providerConfiguration (set by the app before start).
        let config = protocolConfiguration as? NETunnelProviderProtocol
        let providerConfig = config?.providerConfiguration ?? [:]

        let host = providerConfig["host"] as? String ?? ""
        let port = (providerConfig["port"] as? Int) ?? 443
        let path = providerConfig["path"] as? String ?? "/"
        let hasOvpn = (providerConfig["ovpnContent"] as? String)?.isEmpty == false

        log.info("startTunnel: host=\(host) port=\(port) path=\(path) hasOvpn=\(hasOvpn)")

        // Minimal tunnel setup so the system marks the tunnel as "running".
        // Real implementation: start WSS bridge + OpenVPN, then set network settings from pushed routes.
        let tunnelNetworkSettings = createTunnelNetworkSettings()
        setTunnelNetworkSettings(tunnelNetworkSettings) { [weak self] error in
            if let error {
                self?.log.error("setTunnelNetworkSettings failed: \(error.localizedDescription)")
                completionHandler(error)
                return
            }
            self?.log.info("Tunnel network settings applied; tunnel is up (placeholder).")
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("stopTunnel: reason=\(String(describing: reason))")
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Optional: app can send messages via connection.sendProviderMessage(_:responseHandler:).
        // We don't use it for now; status is via NEVPNStatus only.
        completionHandler?(nil)
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        // System is about to sleep; pause traffic if needed.
        completionHandler()
    }

    override func wake() {
        // System woke; resume traffic if needed.
    }

    // MARK: - Private

    private func createTunnelNetworkSettings() -> NEPacketTunnelNetworkSettings {
        // Placeholder: a minimal IPv4 setting so the tunnel interface exists.
        // Real implementation uses addresses/routes pushed by OpenVPN.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.8.0.1")
        settings.ipv4Settings = NEIPv4Settings(addresses: ["10.8.0.2"], subnetMasks: ["255.255.255.0"])
        settings.mtu = 1500
        return settings
    }
}
