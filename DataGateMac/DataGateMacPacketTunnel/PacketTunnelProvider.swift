//
//  PacketTunnelProvider.swift
//  DataGateMacPacketTunnel
//
//  Packet Tunnel Provider: started by the system when the app calls startVPNTunnel().
//  Receives config (WSS + OVPN) via providerConfiguration; no ongoing IPC with the app.
//  Status is reported to the app indirectly via NEVPNStatus (system).
//

import Darwin
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
            return "Packet tunnel extension started, but the VPN engine is not integrated yet. The WSS bridge can start, but no VPN session is created."
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
        ExtensionLogWriter.beginNewSession()

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
        let pathRaw = providerConfig["path"] as? String ?? "/"
        let pathNormalized = pathRaw.hasPrefix("/") ? pathRaw : "/" + pathRaw
        let listenPort = (providerConfig["listenPort"] as? Int) ?? 18080
        let verifyServerCert = (providerConfig["verifyServerCert"] as? Bool) ?? false
        let linkProtocol = providerConfig["linkProtocol"] as? String ?? "tcp"
        let ovpnContent = providerConfig["ovpnContent"] as? String ?? ""
        let hasOvpn = !ovpnContent.isEmpty
        let upstreamWss = "wss://\(host):\(port)\(pathNormalized)"
        let serverDisplayName = (providerConfig["serverDisplayName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let serverId = providerConfig["serverId"] as? Int

        log.info("[Ext] Step 1: config host=\(host) port=\(port) path=\(pathNormalized) listenPort=\(listenPort) verifyCert=\(verifyServerCert) linkProtocol=\(linkProtocol) hasOvpn=\(hasOvpn)")
        ExtensionLogWriter.append("[Ext] Step 1: providerConfiguration host=\(host) remotePort=\(port) path=\(pathNormalized) linkProtocol=\(linkProtocol) verifyServerCert=\(verifyServerCert)")
        if !serverDisplayName.isEmpty {
            if let serverId {
                ExtensionLogWriter.append("[Ext] Step 1: backend server label=\(serverDisplayName) id=\(serverId)")
            } else {
                ExtensionLogWriter.append("[Ext] Step 1: backend server label=\(serverDisplayName)")
            }
        }
        ExtensionLogWriter.append("[Ext] Step 1: upstream WebSocket target \(upstreamWss)")
        ExtensionLogWriter.append("[Ext] Step 1: local profile TCP target 127.0.0.1:\(listenPort) (WSS bridge listen) ovpnBytes=\(ovpnContent.utf8.count)")

        guard !host.isEmpty else {
            fail(PacketTunnelStartupError.missingHost)
            return
        }
        guard hasOvpn else {
            fail(PacketTunnelStartupError.missingOpenVpnProfile)
            return
        }

        log.info("[Ext] Step 2: starting WSS bridge (TCP 127.0.0.1:\(listenPort) <-> \(upstreamWss))")
        ExtensionLogWriter.append("[Ext] Step 2: start WSS bridge local_listen=127.0.0.1:\(listenPort)/tcp upstream=\(upstreamWss)")
        let bridge = WSSBridge(host: host, port: port, path: pathRaw, listenPort: listenPort, verifyServerCert: verifyServerCert, log: log)
        wssBridge = bridge

        var localTcpTimeoutWorkItem: DispatchWorkItem?
        func cancelLocalTcpTimeout() {
            localTcpTimeoutWorkItem?.cancel()
            localTcpTimeoutWorkItem = nil
        }

        bridge.onFirstLocalTcpAccepted = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                cancelLocalTcpTimeout()
                self.log.info("[Ext] Step 3: first local TCP to bridge; setTunnelNetworkSettings (placeholder)...")
                ExtensionLogWriter.append("[Ext] Step 3: first TCP to local bridge (127.0.0.1:\(listenPort)); applying setTunnelNetworkSettings then packetFlow; upstream remains \(upstreamWss)")
                let tunnelNetworkSettings = self.createTunnelNetworkSettings()
                self.setTunnelNetworkSettings(tunnelNetworkSettings) { error in
                    if let error {
                        fail(error)
                        return
                    }
                    self.log.info("[Ext] Step 3: network settings applied")
                    ExtensionLogWriter.append("[Ext] Step 3: setTunnelNetworkSettings OK (IPv4 placeholder 10.8.0.2/24, excluded 127.0.0.0/8)")
                    self.log.info("[Ext] Step 4: starting packetFlow read loop")
                    ExtensionLogWriter.append("[Ext] Step 4: packetFlow read loop start (TUN packets; engine inject hook may be nil)")
                    let flowBridge = PacketFlowBridge(packetFlow: self.packetFlow, log: self.log)
                    self.packetFlowBridge = flowBridge
                    flowBridge.onPacketFromTun = { [weak self] packet in
                        guard let self, let runner = self.openVpnRunner, !packet.isEmpty else { return }
                        let ver = (packet[packet.startIndex] >> 4) & 0x0F
                        let family: Int32
                        if ver == 4 {
                            family = AF_INET
                        } else if ver == 6 {
                            family = AF_INET6
                        } else {
                            return
                        }
                        runner.injectDataPackets(fromTunnel: [packet], protocols: [NSNumber(value: family)])
                    }
                    flowBridge.startReadLoop()
                    succeed()
                }
            }
        }

        bridge.start { [weak self] bridgeError in
            guard let self else { return }
            if let bridgeError {
                cancelLocalTcpTimeout()
                fail(bridgeError)
                return
            }
            self.log.info("[Ext] Step 2: WSS bridge listening")
            ExtensionLogWriter.append("[Ext] Step 2: WSS bridge listening")

            let runner = OpenVPNRunnerBridge { line in
                ExtensionLogWriter.append(line)
            }
            self.openVpnRunner = runner
            runner.setPacketFlow(self.packetFlow)
            runner.setWssProxyHostnameForExclusion(host)
            runner.setNetworkSettingsUpdateHandler { [weak self] settings in
                guard let self else { return }
                self.setTunnelNetworkSettings(settings) { error in
                    if let error {
                        ExtensionLogWriter.append("[Ext] setTunnelNetworkSettings (server PUSH) failed: \(error.localizedDescription)")
                    } else {
                        ExtensionLogWriter.append("[Ext] setTunnelNetworkSettings applied from server PUSH (IPv4, default route, DNS, exclusions)")
                    }
                }
            }
            do {
                try runner.prepare(withOvpnContent: ovpnContent)
                self.log.info("[Ext] Step 5: VPN engine prepared (eval_config OK)")
                ExtensionLogWriter.append("[Ext] Step 5: VPN engine prepared (eval_config OK)")
                let timeoutSeconds: TimeInterval = 45
                let timeout = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    let detail = "No inbound TCP to WSS bridge within \(Int(timeoutSeconds))s. Expected profile client -> 127.0.0.1:\(listenPort)/tcp then relay -> \(upstreamWss)"
                    let err = NSError(
                        domain: "PacketTunnelProvider",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: detail]
                    )
                    self.log.error("[Ext] \(detail)")
                    ExtensionLogWriter.append("[Ext] FAIL: timeout \(Int(timeoutSeconds))s waiting first TCP to 127.0.0.1:\(listenPort) (bridge) while upstream=\(upstreamWss)")
                    fail(err)
                }
                localTcpTimeoutWorkItem = timeout
                ExtensionLogWriter.append("[Ext] Step 6: arm local TCP watchdog \(Int(timeoutSeconds))s (until first client hits 127.0.0.1:\(listenPort))")
                DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)

                runner.start()
                self.log.info("[Ext] Step 6: VPN engine connect() requested (tunnel routes applied after first local TCP)")
                ExtensionLogWriter.append("[Ext] Step 6: VPN engine connect() on worker thread (dials 127.0.0.1:\(listenPort) per OVPN); tunnel IPv4 applied only after that TCP is accepted")
            } catch {
                cancelLocalTcpTimeout()
                let message = error.localizedDescription
                self.log.error("[Ext] Step 5: VPN engine prepare failed: \(message)")
                ExtensionLogWriter.append("[Ext] Step 5: VPN engine prepare failed: \(message)")
                if !self.openVpnEngineWarningLogged {
                    self.openVpnEngineWarningLogged = true
                    ExtensionLogWriter.append("[Ext] Step 5: VPN engine runner is linked, but full connect() / packetFlow wiring is still pending")
                }
                fail(error)
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
        // Real implementation uses addresses/routes from the server PUSH options.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.8.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["10.8.0.2"], subnetMasks: ["255.255.255.0"])
        // Without this, some systems route 127.0.0.1 through the tunnel; the profile transport then cannot reach the local WSS bridge.
        ipv4.excludedRoutes = [NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0")]
        settings.ipv4Settings = ipv4
        settings.mtu = 1500
        return settings
    }
}
