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

/// Config passed to the Packet Tunnel extension (WSS + OVPN).
struct TunnelConfig: Sendable {
    var host: String
    var port: Int
    var path: String
    var ovpnContent: String
    var listenPort: Int
    var verifyServerCert: Bool

    func toProviderConfiguration() -> [String: Any] {
        [
            "host": host,
            "port": port,
            "path": path,
            "ovpnContent": ovpnContent,
            "listenPort": listenPort,
            "verifyServerCert": verifyServerCert,
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
            verifyServerCert: (dictionary["verifyServerCert"] as? Bool) ?? false
        )
    }
}

/// Packet Tunnel extension bundle identifier. Must match the extension target’s Product Bundle Identifier in Xcode.
private let packetTunnelBundleId = "imkolganov.DataGateMac.PacketTunnel"

@MainActor
final class VpnTunnelManager: ObservableObject {
    /// Current tunnel status (for UI).
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var lastError: String?

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    init() {
        startObservingStatus()
    }

    deinit {
        if let obs = statusObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    /// Загружает сохранённую конфигурацию и при необходимости создаёт новую.
    func loadOrCreateConfiguration() async throws {
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
            manager = existing
            status = existing.connection.status
            return
        }

        let newManager = NETunnelProviderManager()
        newManager.localizedDescription = "DataGate"
        newManager.protocolConfiguration = {
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = packetTunnelBundleId
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
    }

    /// Обновляет конфиг туннеля (WSS + OVPN) и сохраняет.
    func setConfiguration(_ config: TunnelConfig) async throws {
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
    }

    /// Запускает туннель. Перед этим нужно вызвать loadOrCreateConfiguration и setConfiguration.
    func startTunnel() throws {
        lastError = nil
        guard let manager else {
            lastError = "Configuration not loaded"
            throw NSError(domain: "VpnTunnelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Configuration not loaded"])
        }
        try manager.connection.startVPNTunnel(options: nil)
    }

    /// Останавливает туннель.
    func stopTunnel() {
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
        ) { [weak self] note in
            guard let self else { return }
            if let session = note.object as? NEVPNConnection {
                self.status = session.status
            }
        }
    }
}
