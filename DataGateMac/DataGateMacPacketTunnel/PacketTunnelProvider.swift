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
    case missingXrayProfile
    case openVpnEngineNotIntegrated

    var errorDescription: String? {
        switch self {
        case .missingProviderConfiguration:
            return "Provider configuration is missing."
        case .missingHost:
            return "Tunnel host is missing from provider configuration."
        case .missingOpenVpnProfile:
            return "OVPN profile content is empty. Backend config was not loaded."
        case .missingXrayProfile:
            return "Xray VLESS share link is empty. Backend config was not loaded."
        case .openVpnEngineNotIntegrated:
            return "Packet tunnel extension started, but the VPN engine is not integrated yet. The WSS bridge can start, but no VPN session is created."
        }
    }
}

/// Loaded by NE via `NEProviderClasses` → `$(PRODUCT_MODULE_NAME).PacketTunnelProvider` in the sysex Info.plist.
class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = Logger(subsystem: "imkolganov.DataGateMac.PacketTunnel", category: "Tunnel")
    private var wssBridge: WSSBridge?
    private var packetFlowBridge: PacketFlowBridge?
    private var openVpnRunner: OpenVPNRunnerBridge?
    private var xrayRunner: XrayRunnerBridge?
    private var openVpnEngineWarningLogged = false

    override init() {
        super.init()
        log.info("[Ext] PacketTunnelProvider init")
    }

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

        guard let config = protocolConfiguration as? NETunnelProviderProtocol else {
            fail(PacketTunnelStartupError.missingProviderConfiguration)
            return
        }
        let providerConfig = config.providerConfiguration ?? [:]

        let host = (providerConfig["host"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Self.intFromProvider(providerConfig["port"]) ?? 443
        let pathRaw = providerConfig["path"] as? String ?? "/"
        let pathNormalized = pathRaw.hasPrefix("/") ? pathRaw : "/" + pathRaw
        let listenPort = Self.intFromProvider(providerConfig["listenPort"]) ?? 18080
        let verifyServerCert = (providerConfig["verifyServerCert"] as? Bool) ?? false
        let linkProtocol = providerConfig["linkProtocol"] as? String ?? "tcp"
        let ovpnContent = providerConfig["ovpnContent"] as? String ?? ""
        let xrayShareLink = providerConfig["xrayShareLink"] as? String ?? ""
        let hasOvpn = !ovpnContent.isEmpty
        let transportMode = (providerConfig["transportMode"] as? String ?? "").lowercased()
        let useDirect = transportMode == "direct"
        let useXray = transportMode == "xray"
        let upstreamWss = "wss://\(host):\(port)\(pathNormalized)"
        let serverDisplayName = (providerConfig["serverDisplayName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let serverId = Self.intFromProvider(providerConfig["serverId"])
        let clientCommonName = (providerConfig["clientCommonName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        log.info("[Ext] Step 1: config mode=\(transportMode) useDirect=\(useDirect) useXray=\(useXray) host=\(host) port=\(port) path=\(pathNormalized) listenPort=\(listenPort) verifyCert=\(verifyServerCert) linkProtocol=\(linkProtocol) hasOvpn=\(hasOvpn) hasXray=\(!xrayShareLink.isEmpty)")
        ExtensionLogWriter.append("[Ext] Step 1: providerConfiguration mode=\(transportMode) useDirect=\(useDirect) useXray=\(useXray) host=\(host) remotePort=\(port) path=\(pathNormalized) linkProtocol=\(linkProtocol) verifyServerCert=\(verifyServerCert)")
        if !serverDisplayName.isEmpty {
            if let serverId {
                ExtensionLogWriter.append("[Ext] Step 1: backend server label=\(serverDisplayName) id=\(serverId)")
            } else {
                ExtensionLogWriter.append("[Ext] Step 1: backend server label=\(serverDisplayName)")
            }
        }
        if !clientCommonName.isEmpty {
            ExtensionLogWriter.append("[Ext] Step 1: client CN=\(clientCommonName)")
        }
        let issuedFileName = (providerConfig["issuedFileName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !issuedFileName.isEmpty {
            ExtensionLogWriter.append("[Ext] Step 1: issued file=\(issuedFileName)")
        }

        guard !host.isEmpty else {
            fail(PacketTunnelStartupError.missingHost)
            return
        }
        if useXray {
            guard !xrayShareLink.isEmpty else {
                fail(PacketTunnelStartupError.missingXrayProfile)
                return
            }
            startXray(host: host, port: port, shareLink: xrayShareLink, fail: fail, succeed: succeed)
            return
        }
        guard hasOvpn else {
            fail(PacketTunnelStartupError.missingOpenVpnProfile)
            return
        }

        if useDirect {
            startDirectOpenVpn(host: host, port: port, ovpnContent: ovpnContent, linkProtocol: linkProtocol, fail: fail, succeed: succeed)
            return
        }

        log.info("[Ext] Step 2: starting WSS bridge (TCP 127.0.0.1:\(listenPort) <-> \(upstreamWss))")
        ExtensionLogWriter.append("[Ext] Step 1: upstream WebSocket target \(upstreamWss)")
        ExtensionLogWriter.append("[Ext] Step 1: local profile TCP target 127.0.0.1:\(listenPort) (WSS bridge listen) ovpnBytes=\(ovpnContent.utf8.count)")
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
                    self.bindTrafficInterface()
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
        xrayRunner?.stopXray()
        xrayRunner = nil
        TunnelTrafficMeter.reset()
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard String(data: messageData, encoding: .utf8) == "stats" else {
            completionHandler?(nil)
            return
        }
        let snap = TunnelTrafficMeter.snapshot() ?? (bytesIn: UInt64(0), bytesOut: UInt64(0))
        let payload: [String: Any] = [
            "in": snap.bytesIn,
            "out": snap.bytesOut,
        ]
        completionHandler?(try? JSONSerialization.data(withJSONObject: payload))
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        // System is about to sleep; pause traffic if needed.
        completionHandler()
    }

    override func wake() {
        // System woke; resume traffic if needed.
    }

    // MARK: - Direct OpenVPN (no WSS)

    private func startDirectOpenVpn(
        host: String,
        port: Int,
        ovpnContent: String,
        linkProtocol: String,
        fail: @escaping (Error) -> Void,
        succeed: @escaping () -> Void
    ) {
        log.info("[Ext] Step 2: direct OpenVPN to \(host):\(port) proto=\(linkProtocol) (no WSS)")
        ExtensionLogWriter.append("[Ext] Step 2: direct OpenVPN remote=\(host):\(port) proto=\(linkProtocol); using OVPN remotes as-is")
        ExtensionLogWriter.append("[Ext] Step 3: skip placeholder setTunnelNetworkSettings (apply once from OpenVPN PUSH)")

        var finished = false
        let finishLock = NSLock()
        var pushTimeoutWorkItem: DispatchWorkItem?
        func finish(_ error: Error?) {
            finishLock.lock()
            defer { finishLock.unlock() }
            guard !finished else { return }
            finished = true
            pushTimeoutWorkItem?.cancel()
            pushTimeoutWorkItem = nil
            if let error {
                fail(error)
            } else {
                succeed()
            }
        }

        let runner = OpenVPNRunnerBridge { line in
            ExtensionLogWriter.append(line)
        }
        openVpnRunner = runner
        runner.setPacketFlow(packetFlow)
        runner.setWssProxyHostnameForExclusion(host)
        runner.setNetworkSettingsUpdateHandler { [weak self] settings in
            guard let self else { return }
            self.setTunnelNetworkSettings(settings) { error in
                if let error {
                    ExtensionLogWriter.append("[Ext] setTunnelNetworkSettings (server PUSH) failed: \(error.localizedDescription)")
                    finish(error)
                    return
                }
                ExtensionLogWriter.append("[Ext] setTunnelNetworkSettings applied from server PUSH (IPv4, default route, DNS, exclusions)")
                if self.packetFlowBridge == nil {
                    self.startPacketFlowBridge()
                }
                ExtensionLogWriter.append("[Ext] Step 6: OpenVPN PUSH applied; direct session is up")
                finish(nil)
            }
        }
        do {
            try runner.prepare(withOvpnContent: ovpnContent)
            log.info("[Ext] Step 5: VPN engine prepared (eval_config OK)")
            ExtensionLogWriter.append("[Ext] Step 5: VPN engine prepared (eval_config OK)")
            let timeoutSeconds: TimeInterval = 45
            let timeout = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let detail = "OpenVPN did not complete handshake within \(Int(timeoutSeconds))s to \(host):\(port)."
                self.log.error("[Ext] \(detail)")
                ExtensionLogWriter.append("[Ext] FAIL: \(detail)")
                finish(NSError(domain: "PacketTunnelProvider", code: -3, userInfo: [NSLocalizedDescriptionKey: detail]))
            }
            pushTimeoutWorkItem = timeout
            ExtensionLogWriter.append("[Ext] Step 6: arm OpenVPN PUSH watchdog \(Int(timeoutSeconds))s for \(host):\(port)")
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
            runner.start()
            log.info("[Ext] Step 6: VPN engine connect() requested")
            ExtensionLogWriter.append("[Ext] Step 6: VPN engine connect() using profile remotes; waiting for PUSH")
        } catch {
            let message = error.localizedDescription
            log.error("[Ext] Step 5: VPN engine prepare failed: \(message)")
            ExtensionLogWriter.append("[Ext] Step 5: VPN engine prepare failed: \(message)")
            finish(error)
        }
    }

    private func startPacketFlowBridge() {
        log.info("[Ext] Step 4: starting packetFlow read loop")
        ExtensionLogWriter.append("[Ext] Step 4: packetFlow read loop start (TUN packets)")
        let flowBridge = PacketFlowBridge(packetFlow: packetFlow, log: log)
        packetFlowBridge = flowBridge
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
        bindTrafficInterface()
    }

    // MARK: - Xray (VLESS via libXray)

    private func startXray(
        host: String,
        port: Int,
        shareLink: String,
        fail: @escaping (Error) -> Void,
        succeed: @escaping () -> Void
    ) {
        log.info("[Ext] Step 2: Xray VLESS \(host):\(port)")
        ExtensionLogWriter.append("[Ext] Step 2: Xray remote=\(host):\(port) shareBytes=\(shareLink.utf8.count)")

        let settings = createXrayTunnelNetworkSettings(remoteHost: host)
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else { return }
            if let error {
                fail(error)
                return
            }
            ExtensionLogWriter.append("[Ext] Step 3: setTunnelNetworkSettings OK (10.51.0.2/24 default route, exclude VLESS host)")

            let tunFd = self.packetFlowSocketFileDescriptor()
            guard let tunFd else {
                fail(NSError(
                    domain: "PacketTunnelProvider",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Could not read the packet-flow utun file descriptor for Xray."]
                ))
                return
            }
            ExtensionLogWriter.append("[Ext] Step 3: packetFlow utun fd=\(tunFd)")
            TunnelTrafficMeter.bind(utunFd: tunFd)

            let runner = XrayRunnerBridge { line in
                ExtensionLogWriter.append(line)
            }
            self.xrayRunner = runner

            var shareConfig: NSDictionary?
            do {
                try runner.convertShareLink(shareLink, outboundConfig: &shareConfig)
            } catch {
                fail(error)
                return
            }
            guard let shareConfig = shareConfig as? [String: Any] else {
                fail(XrayConfigError.noOutbounds)
                return
            }

            let xrayJson: String
            do {
                xrayJson = try XrayConfigAssembler.makeRuntimeConfig(
                    shareConfig: shareConfig,
                    tunFileDescriptor: tunFd
                )
            } catch {
                fail(error)
                return
            }
            ExtensionLogWriter.append("[Ext] Step 4: Xray JSON ready (\(xrayJson.utf8.count) bytes) socks=127.0.0.1:\(XrayConfigAssembler.socksListenPort) tunFd=\(tunFd)")
            _ = setenv("xray.tun.fd", String(tunFd), 1)
            _ = setenv("XRAY_TUN_FD", String(tunFd), 1)

            do {
                try runner.runXrayJson(xrayJson)
            } catch {
                fail(error)
                return
            }
            self.log.info("[Ext] Step 5: libXray runXray OK")
            ExtensionLogWriter.append("[Ext] Step 5: libXray runXray OK")
            succeed()
        }
    }

    /// NEPacketTunnelFlow's underlying utun socket (KVC, then scan like Xray-core iOS notes).
    private func packetFlowSocketFileDescriptor() -> Int32? {
        let flow = packetFlow as NSObject
        if let number = flow.value(forKeyPath: "socket.fileDescriptor") as? NSNumber {
            let fd = number.int32Value
            if fd >= 0 { return fd }
        }
        var buf = [CChar](repeating: 0, count: 16)
        for fd in Int32(0)...1024 {
            var len = socklen_t(buf.count)
            let rc = buf.withUnsafeMutableBytes { raw -> Int32 in
                guard let base = raw.baseAddress else { return -1 }
                return getsockopt(fd, 2, 2, base, &len)
            }
            if rc == 0 {
                let name = String(cString: buf)
                if name.hasPrefix("utun") {
                    return fd
                }
            }
        }
        return nil
    }

    private func createXrayTunnelNetworkSettings(remoteHost: String) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remoteHost)
        let ipv4 = NEIPv4Settings(addresses: ["10.51.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: "0.0.0.0", subnetMask: "0.0.0.0")]
        var excluded: [NEIPv4Route] = []
        if let ip = Self.ipv4Address(forHost: remoteHost) {
            excluded.append(NEIPv4Route(destinationAddress: ip, subnetMask: "255.255.255.255"))
            ExtensionLogWriter.append("[Ext] Step 3: exclude VLESS endpoint \(ip)/32")
        }
        if !excluded.isEmpty {
            ipv4.excludedRoutes = excluded
        }
        settings.ipv4Settings = ipv4
        let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        settings.mtu = 1500
        return settings
    }

    private static func ipv4Address(forHost host: String) -> String? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        var addr = in_addr()
        if inet_pton(AF_INET, trimmed, &addr) == 1 {
            return trimmed
        }
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(trimmed, nil, &hints, &result) == 0 else { return nil }
        defer { freeaddrinfo(result) }
        guard let first = result else { return nil }
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(
            first.pointee.ai_addr,
            socklen_t(first.pointee.ai_addrlen),
            &hostname,
            socklen_t(hostname.count),
            nil,
            0,
            NI_NUMERICHOST
        ) == 0 else {
            return nil
        }
        return String(cString: hostname)
    }

    private static func intFromProvider(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String, let i = Int(s) { return i }
        return nil
    }

    private func bindTrafficInterface() {
        if let fd = packetFlowSocketFileDescriptor() {
            TunnelTrafficMeter.bind(utunFd: fd)
        }
    }

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

/// Device-side utun byte counters for the live Home traffic chart (not backend stats).
enum TunnelTrafficMeter {
    private static let lock = NSLock()
    private static var interfaceName: String?

    static func reset() {
        lock.lock()
        interfaceName = nil
        lock.unlock()
    }

    static func bind(utunFd fd: Int32) {
        guard let name = utunInterfaceName(from: fd) else { return }
        lock.lock()
        interfaceName = name
        lock.unlock()
    }

    static func snapshot() -> (bytesIn: UInt64, bytesOut: UInt64)? {
        lock.lock()
        let name = interfaceName
        lock.unlock()
        guard let name, let counts = interfaceByteCounts(ifName: name) else {
            return interfaceByteCountsForAnyUtun()
        }
        return counts
    }

    private static func utunInterfaceName(from fd: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 16)
        var len = socklen_t(buf.count)
        let rc = buf.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return getsockopt(fd, 2, 2, base, &len)
        }
        guard rc == 0 else { return nil }
        let name = String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.hasPrefix("utun") ? name : nil
    }

    private static func interfaceByteCounts(ifName: String) -> (bytesIn: UInt64, bytesOut: UInt64)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            if name == ifName,
               let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               let data = current.pointee.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                return (UInt64(stats.ifi_ibytes), UInt64(stats.ifi_obytes))
            }
            ptr = current.pointee.ifa_next
        }
        return nil
    }

    private static func interfaceByteCountsForAnyUtun() -> (bytesIn: UInt64, bytesOut: UInt64)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var best: (bytesIn: UInt64, bytesOut: UInt64)?
        var bestTotal: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            if name.hasPrefix("utun"),
               let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               let data = current.pointee.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                let inn = UInt64(stats.ifi_ibytes)
                let out = UInt64(stats.ifi_obytes)
                let total = inn &+ out
                if total >= bestTotal {
                    bestTotal = total
                    best = (inn, out)
                }
            }
            ptr = current.pointee.ifa_next
        }
        return best
    }
}
