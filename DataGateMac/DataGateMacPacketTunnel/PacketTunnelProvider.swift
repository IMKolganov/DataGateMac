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

private enum PacketTunnelStartupError: LocalizedError {
    case missingProviderConfiguration
    case missingHost
    case missingOpenVpnProfile
    case openVpnEngineNotIntegrated

    var errorDescription: String? {
        switch self {
        case .missingProviderConfiguration:
            return "Provider configuration is missing."
        case .missingHost:
            return "Tunnel host is missing from provider configuration."
        case .missingOpenVpnProfile:
            return "OVPN profile content is empty. Backend config was not loaded."
        case .openVpnEngineNotIntegrated:
            return "Packet tunnel extension started, but the OpenVPN engine is not integrated yet. WSS bridge can start, but no VPN session is created."
        }
    }
}

/// Exposed to the ObjC runtime for `NSExtensionPrincipalClass` (PlugInKit / NE loads the class by name).
@objc(PacketTunnelProvider)
class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = Logger(subsystem: "imkolganov.DataGateMac.PacketTunnel", category: "Tunnel")
    private var wssBridge: WSSBridge?
    private var packetFlowBridge: PacketFlowBridge?
    private var openVpnRunner: OpenVPNRunnerBridge?
    private var openVpnEngineWarningLogged = false

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        /// Any failure: log to shared file and complete with error so the extension never crashes and the app can see the reason (via extension log or status).
        func fail(_ error: Error) {
            let msg = "[Ext] FAIL: \(error.localizedDescription)"
            log.error("\(msg)")
            ExtensionLogWriter.append(msg)
            completionHandler(error)
        }
        func succeed() {
            completionHandler(nil)
        }

        ExtensionLogWriter.append("[Ext] startTunnel entered")
        log.info("[Ext] Step 1: startTunnel called, reading providerConfiguration")
        ExtensionLogWriter.append("[Ext] Step 1: startTunnel called, reading providerConfiguration")
        ExtensionLogWriter.append("[Ext] Extension bundle: \(Bundle.main.bundlePath)")
        ExtensionLogWriter.append("[Ext] Extension bundle id: \(Bundle.main.bundleIdentifier ?? "(nil)")")
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ExtensionLogWriter.appGroupId) {
            ExtensionLogWriter.append("[Ext] App Group container OK: \(container.path)")
        } else {
            ExtensionLogWriter.append("[Ext] App Group container unavailable for \(ExtensionLogWriter.appGroupId)")
        }

        guard let config = protocolConfiguration as? NETunnelProviderProtocol else {
            fail(PacketTunnelStartupError.missingProviderConfiguration)
            return
        }
        let providerConfig = config.providerConfiguration ?? [:]

        let host = (providerConfig["host"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let port = (providerConfig["port"] as? Int) ?? 443
        let path = providerConfig["path"] as? String ?? "/"
        let listenPort = (providerConfig["listenPort"] as? Int) ?? 18080
        let verifyServerCert = (providerConfig["verifyServerCert"] as? Bool) ?? false
        let linkProtocol = providerConfig["linkProtocol"] as? String ?? "tcp"
        let ovpnContent = providerConfig["ovpnContent"] as? String ?? ""
        let hasOvpn = !ovpnContent.isEmpty

        log.info("[Ext] Step 1: config host=\(host) port=\(port) path=\(path) listenPort=\(listenPort) verifyCert=\(verifyServerCert) linkProtocol=\(linkProtocol) hasOvpn=\(hasOvpn)")
        ExtensionLogWriter.append("[Ext] Step 1: config host=\(host) port=\(port) path=\(path) listenPort=\(listenPort) verifyCert=\(verifyServerCert) linkProtocol=\(linkProtocol) hasOvpn=\(hasOvpn)")

        guard !host.isEmpty else {
            fail(PacketTunnelStartupError.missingHost)
            return
        }
        guard hasOvpn else {
            fail(PacketTunnelStartupError.missingOpenVpnProfile)
            return
        }

        log.info("[Ext] Step 2: starting WSS bridge (TCP 127.0.0.1:\(listenPort) <-> wss://host:port/path)")
        ExtensionLogWriter.append("[Ext] Step 2: starting WSS bridge (TCP 127.0.0.1:\(listenPort) <-> wss://host:port/path)")
        let bridge = WSSBridge(host: host, port: port, path: path, listenPort: listenPort, verifyServerCert: verifyServerCert, log: log)
        wssBridge = bridge
        bridge.start { [weak self] bridgeError in
            guard let self else { return }
            if let bridgeError {
                fail(bridgeError)
                return
            }
            self.log.info("[Ext] Step 2: WSS bridge listening")
            ExtensionLogWriter.append("[Ext] Step 2: WSS bridge listening")
            self.log.info("[Ext] Step 3: setTunnelNetworkSettings (placeholder)...")
            ExtensionLogWriter.append("[Ext] Step 3: setTunnelNetworkSettings (placeholder)...")
            let tunnelNetworkSettings = self.createTunnelNetworkSettings()
            self.setTunnelNetworkSettings(tunnelNetworkSettings) { error in
                if let error {
                    fail(error)
                    return
                }
                self.log.info("[Ext] Step 3: network settings applied")
                ExtensionLogWriter.append("[Ext] Step 3: network settings applied")
                self.log.info("[Ext] Step 4: starting packetFlow read loop")
                ExtensionLogWriter.append("[Ext] Step 4: starting packetFlow read loop")
                let flowBridge = PacketFlowBridge(packetFlow: self.packetFlow, log: self.log)
                self.packetFlowBridge = flowBridge
                flowBridge.startReadLoop()
                let runner = OpenVPNRunnerBridge { line in
                    ExtensionLogWriter.append(line)
                }
                self.openVpnRunner = runner
                do {
                    try runner.prepare(withOvpnContent: ovpnContent)
                    self.log.info("[Ext] Step 5: OpenVPN3 bridge prepared (eval_config OK)")
                    ExtensionLogWriter.append("[Ext] Step 5: OpenVPN3 bridge prepared (eval_config OK)")
                    runner.start()
                    self.log.info("[Ext] Step 6: OpenVPN3 connect() requested")
                    ExtensionLogWriter.append("[Ext] Step 6: OpenVPN3 connect() requested")
                } catch {
                    let message = error.localizedDescription
                    self.log.error("[Ext] Step 5: OpenVPN3 prepare failed: \(message)")
                    ExtensionLogWriter.append("[Ext] Step 5: OpenVPN3 prepare failed: \(message)")
                    if !self.openVpnEngineWarningLogged {
                        self.openVpnEngineWarningLogged = true
                        ExtensionLogWriter.append("[Ext] Step 5: OpenVPN runner is linked, but full connect() / packetFlow wiring is still pending")
                    }
                }
                succeed()
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("[Ext] stopTunnel: reason=\(String(describing: reason))")
        ExtensionLogWriter.append("[Ext] stopTunnel: reason=\(String(describing: reason))")
        wssBridge?.stop()
        wssBridge = nil
        packetFlowBridge?.stop()
        packetFlowBridge = nil
        openVpnRunner?.stop()
        openVpnRunner = nil
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
