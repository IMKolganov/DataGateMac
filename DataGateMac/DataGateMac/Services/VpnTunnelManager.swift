//
//  VpnTunnelManager.swift
//  DataGateMac
//
//  VPN management via Network Extension (as in README):
//  configuration and Start/Stop tunnel via NETunnelProviderManager.
//

import Combine
import Foundation
import NetworkExtension

enum TunnelLinkProtocol: String, Sendable {
    case tcp
    case udp

    var configProtoDirective: String {
        switch self {
        case .tcp:
            return "proto tcp-client"
        case .udp:
            return "proto udp"
        }
    }

    var proxyMode: String { rawValue }

    static func fromOvpnConfigContent(_ content: String) -> TunnelLinkProtocol {
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for raw in lines {
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                continue
            }
            if let commentIndex = line.firstIndex(where: { $0 == "#" || $0 == ";" }) {
                line = String(line[..<commentIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty {
                    continue
                }
            }
            let lowered = line.lowercased()
            guard lowered.hasPrefix("proto ") else { continue }
            let tokens = lowered.split(whereSeparator: \.isWhitespace)
            guard tokens.count >= 2 else { continue }
            let proto = String(tokens[1])
            if proto.hasPrefix("udp") { return .udp }
            if proto.hasPrefix("tcp") { return .tcp }
        }
        return .tcp
    }
}

func patchOvpnConfigForLocalBridge(_ originalContent: String, listenPort: Int, linkProtocol: TunnelLinkProtocol) -> String {
    let lines = originalContent.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
    var out: [String] = []
    out.reserveCapacity(lines.count + 2)

    var remoteWritten = false
    var protoWritten = false

    for raw in lines {
        let line = String(raw).trimmingCharacters(in: .newlines)
        let lowered = line.trimmingCharacters(in: .whitespaces).lowercased()

        if lowered.hasPrefix("remote ") {
            if !remoteWritten {
                out.append("remote 127.0.0.1 \(listenPort)")
                remoteWritten = true
            }
            continue
        }

        if lowered.hasPrefix("proto ") {
            out.append(linkProtocol.configProtoDirective)
            protoWritten = true
            continue
        }

        out.append(line)
    }

    if !protoWritten {
        out.insert(linkProtocol.configProtoDirective, at: 0)
    }
    if !remoteWritten {
        out.insert("remote 127.0.0.1 \(listenPort)", at: 0)
    }

    return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
}

/// Config passed to the Packet Tunnel extension (WSS + OVPN).
struct TunnelConfig: Sendable {
    var host: String
    var port: Int
    var path: String
    var ovpnContent: String
    var listenPort: Int
    var verifyServerCert: Bool
    var linkProtocol: TunnelLinkProtocol

    func toProviderConfiguration() -> [String: Any] {
        [
            "host": host,
            "port": port,
            "path": path,
            "ovpnContent": ovpnContent,
            "listenPort": listenPort,
            "verifyServerCert": verifyServerCert,
            "linkProtocol": linkProtocol.rawValue,
        ]
    }

    static func from(dictionary: [String: Any]) -> TunnelConfig? {
        guard let host = dictionary["host"] as? String,
              let port = dictionary["port"] as? Int,
              let path = dictionary["path"] as? String,
              let ovpnContent = dictionary["ovpnContent"] as? String
        else { return nil }
        return TunnelConfig(
            host: host,
            port: port,
            path: path,
            ovpnContent: ovpnContent,
            listenPort: (dictionary["listenPort"] as? Int) ?? 18080,
            verifyServerCert: (dictionary["verifyServerCert"] as? Bool) ?? false,
            linkProtocol: TunnelLinkProtocol(rawValue: (dictionary["linkProtocol"] as? String ?? "").lowercased()) ?? .tcp
        )
    }
}

/// Returns an English description for tunnel errors so logs/UI stay in English (system may return localizedDescription in user locale).
private func tunnelErrorEnglishDescription(_ error: Error) -> String {
    let ns = error as NSError
    switch (ns.domain, ns.code) {
    case ("NEVPNErrorDomain", 1), (NEVPNConnectionErrorDomain, 1):
        return "VPN configuration invalid (e.g. packet tunnel extension not installed). Run the app from Xcode and try Connect again."
    case ("NEVPNErrorDomain", 4):
        return "VPN configuration stale; reload and try again."
    case ("NEVPNErrorDomain", 5):
        return "VPN configuration read/write failed (check entitlements)."
    case ("NEVPNErrorDomain", 14), (NEVPNConnectionErrorDomain, 14):
        return "Packet tunnel extension not available (code 14). The OS did not load the embedded appex (PlugInKit often reports 0 matches). If the app is already in /Applications and [Diagnostics] shows the appex OK: verify App ID imkolganov.DataGateMac.PacketTunnel in Apple Developer (Network Extension + same App Group), reboot, check Console (neagent/pkd). Otherwise install from /Applications and avoid Run from Xcode for VPN tests."
    default:
        return "Connection failed (\(ns.domain) code \(ns.code))"
    }
}

/// Returns a more actionable description for configuration read/write failures
/// (load/save/remove in Network Extension preferences).
func tunnelConfigurationErrorEnglishDescription(_ error: Error, action: String) -> String {
    let ns = error as NSError
    let lowerDescription = ns.localizedDescription.lowercased()
    let isPermissionDenied =
        lowerDescription.contains("permission denied")
        || (ns.domain == "NEConfigurationErrorDomain" && ns.code == 10)
        || (ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError)

    if isPermissionDenied {
        return "Permission denied while \(action). macOS blocked VPN configuration changes for this app, so saveToPreferences/loadFromPreferences did not complete. This usually means the VPN approval prompt was denied earlier or the existing DataGate profile is stale. Remove DataGate in System Settings -> VPN, relaunch /Users/rackot/Applications/DataGateMac.app, then try Connect again and allow the system prompt if it appears. [\(ns.domain) code \(ns.code)]"
    }

    return "\(ns.localizedDescription) [\(ns.domain) code \(ns.code)]"
}

@MainActor
final class VpnTunnelManager: ObservableObject {
    /// Current tunnel status (for UI).
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var lastError: String?

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    /// Fallback when `NEVPNStatusDidChange` does not fire (macOS sometimes uses a different connection instance than `manager.connection`).
    private var statusPollTimer: Timer?

    /// When set, critical steps are logged here (e.g. for UI display). Callbacks are invoked on main.
    var onLog: ((String) -> Void)?

    init() {
        startObservingStatus()
    }

    deinit {
        if let obs = statusObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        statusPollTimer?.invalidate()
    }

    /// Syncs `status` from `manager.connection` and updates last disconnect error if needed.
    private func applyStatusFromManagerConnection(reason: String) {
        guard let manager else { return }
        let conn = manager.connection
        let newStatus = conn.status
        let oldStatus = status
        if newStatus != oldStatus {
            status = newStatus
            onLog?("[Tunnel] Status sync (\(reason)): \(oldStatus.rawValue) -> \(newStatus.rawValue)")
            if newStatus == .disconnected || newStatus == .invalid {
                let wasTerminal = oldStatus == .disconnected || oldStatus == .invalid
                if !wasTerminal {
                    conn.fetchLastDisconnectError { [weak self] error in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            let message = error.map { tunnelErrorEnglishDescription($0) }
                            self.lastError = message
                            if let msg = message {
                                self.onLog?("[Tunnel] Last disconnect error: \(msg)")
                            }
                        }
                    }
                }
            } else {
                lastError = nil
            }
        }
    }

    private func stopStatusPollTimer() {
        statusPollTimer?.invalidate()
        statusPollTimer = nil
    }

    /// Polls connection status for a short window — notifications alone are unreliable on macOS.
    private func startStatusPollAfterTunnelStart() {
        stopStatusPollTimer()
        var tick = 0
        let maxTicks = 30 // ~60s at 2s interval
        statusPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            tick += 1
            guard let manager = self.manager else {
                timer.invalidate()
                return
            }
            let s = manager.connection.status
            self.applyStatusFromManagerConnection(reason: "poll \(tick)")
            if s == .connecting, tick % 5 == 0 {
                self.onLog?("[Tunnel] Still connecting (poll \(tick), ~\(tick * 2)s); if this never ends, extension likely did not start — check Console (neagent).")
            }
            if s == .connected || s == .disconnected || s == .invalid {
                self.onLog?("[Tunnel] Status poll: terminal state \(s.rawValue), stopping poll.")
                timer.invalidate()
                self.statusPollTimer = nil
                return
            }
            if tick >= maxTicks {
                self.onLog?("[Tunnel] Status poll: still non-terminal after ~\(tick * 2)s (last raw=\(s.rawValue)). Check Console (neagent/pkd) or try Disconnect.")
                timer.invalidate()
                self.statusPollTimer = nil
            }
        }
        if let t = statusPollTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    /// Loads saved tunnel configuration or creates a new one.
    func loadOrCreateConfiguration() async throws {
        onLog?("[Tunnel] Step: loading preferences...")
        let managers = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: managers ?? [])
            }
        }

        if let existing = managers.first(where: { $0.localizedDescription == "DataGate" }) {
            if !existing.isEnabled {
                onLog?("[Tunnel] Step: VPN manager was disabled; enabling and saving...")
                existing.isEnabled = true
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    existing.saveToPreferences { error in
                        if let error {
                            cont.resume(throwing: error)
                        } else {
                            cont.resume()
                        }
                    }
                }
            }
            manager = existing
            status = existing.connection.status
            onLog?("[Tunnel] Step: using existing manager, status=\(status.rawValue)")
            return
        }

        onLog?("[Tunnel] Step: creating new manager...")
        let newManager = NETunnelProviderManager()
        newManager.localizedDescription = "DataGate"
        newManager.isEnabled = true
        newManager.protocolConfiguration = {
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = TunnelConstants.packetTunnelBundleIdentifier
            proto.serverAddress = "datagate"
            return proto
        }()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            newManager.saveToPreferences { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
        manager = newManager
        status = .invalid
        onLog?("[Tunnel] Step: new manager saved.")
    }

    /// Updates tunnel config (WSS + OVPN) and saves.
    func setConfiguration(_ config: TunnelConfig) async throws {
        onLog?("[Tunnel] Step: setting config host=\(config.host):\(config.port)...")
        guard let manager else {
            try await loadOrCreateConfiguration()
            return try await setConfiguration(config)
        }
        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else { return }
        proto.providerConfiguration = config.toProviderConfiguration()
        manager.protocolConfiguration = proto
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
        onLog?("[Tunnel] Step: config saved.")
    }

    /// Reloads manager from system preferences so the system sees the current app/extension path (helps avoid code 14 when running from Xcode).
    func reloadFromPreferences() async throws {
        guard let manager else { return }
        onLog?("[Tunnel] Step: reloading from preferences...")
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
        onLog?("[Tunnel] Step: reloaded.")
    }

    /// Deletes the saved "DataGate" VPN profile from System Settings. Use after copying the app to /Applications or if code 14 persists (stale profile tied to an old install path).
    func removeDataGateFromPreferences() async throws {
        onLog?("[Tunnel] Step: loading preferences to remove DataGate profile...")
        let managers = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: managers ?? [])
            }
        }
        guard let match = managers.first(where: { $0.localizedDescription == "DataGate" }) else {
            onLog?("[Tunnel] Step: no DataGate profile in preferences (nothing to remove).")
            manager = nil
            status = .invalid
            return
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            match.removeFromPreferences { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
        manager = nil
        status = .invalid
        onLog?("[Tunnel] Step: DataGate profile removed. Also delete DataGate in System Settings → VPN if it still appears, then Connect to recreate.")
    }

    /// Starts the tunnel. Call loadOrCreateConfiguration, setConfiguration, and optionally reloadFromPreferences first.
    func startTunnel() throws {
        lastError = nil
        let appPath = Bundle.main.bundlePath
        onLog?("[Tunnel] App path: \(appPath)")
        if !AppBundleLocation.isStandardApplicationsInstall {
            onLog?("[Tunnel] WARNING: Not under /Applications or ~/Applications. Extension often fails (code 14). Quit, open DataGateMac.app from Finder (Applications folder), then Connect.")
        }
        onLog?("[Tunnel] Step: calling startVPNTunnel()...")
        guard let manager else {
            lastError = "Configuration not loaded"
            throw NSError(domain: "VpnTunnelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Configuration not loaded"])
        }
        try manager.connection.startVPNTunnel(options: nil)
        onLog?("[Tunnel] Step: startVPNTunnel() returned (system will start extension).")
        applyStatusFromManagerConnection(reason: "right after startVPNTunnel")
        startStatusPollAfterTunnelStart()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.applyStatusFromManagerConnection(reason: "0.3s after start")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.applyStatusFromManagerConnection(reason: "1.5s after start")
        }
    }

    /// Stops the tunnel.
    func stopTunnel() {
        stopStatusPollTimer()
        manager?.connection.stopVPNTunnel()
    }

    /// Current status text for UI (Connected / Disconnected / Connecting etc.).
    var statusDisplayText: String {
        switch status {
        case .invalid: return "Not configured"
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .reasserting: return "Reconnecting..."
        case .disconnecting: return "Disconnecting..."
        @unknown default: return "Unknown"
        }
    }

    var isConnected: Bool { status == .connected }
    var isConnectingOrConnected: Bool { status == .connecting || status == .connected || status == .reasserting }

    private func startObservingStatus() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Do not compare `note.object` to `manager.connection` — on macOS they may differ; always read our manager.
            guard let manager = self.manager else { return }
            let conn = manager.connection
            let oldStatus = self.status
            let newStatus = conn.status
            if newStatus != oldStatus {
                self.status = newStatus
                self.onLog?("[Tunnel] Status changed: \(oldStatus.rawValue) -> \(newStatus.rawValue)")
            }
            if newStatus == .disconnected || newStatus == .invalid {
                let wasTerminal = oldStatus == .disconnected || oldStatus == .invalid
                if !wasTerminal {
                    conn.fetchLastDisconnectError { [weak self] error in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            let message = error.map { tunnelErrorEnglishDescription($0) }
                            self.lastError = message
                            if let msg = message {
                                self.onLog?("[Tunnel] Last disconnect error: \(msg)")
                            }
                        }
                    }
                }
            } else {
                self.lastError = nil
            }
        }
    }
}
