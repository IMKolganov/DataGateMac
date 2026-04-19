//
//  VpnViewModel.swift
//  DataGateMac
//
//  Uses VpnTunnelManager (Network Extension) for Connect/Disconnect and status.
//

import Combine
import Foundation
import NetworkExtension

@MainActor
final class VpnViewModel: ObservableObject {
    private enum ConnectFlowError: LocalizedError {
        case unauthorized
        case backendConfigUnavailable

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Sign in again before connecting."
            case .backendConfigUnavailable:
                return "Could not build VPN configuration from the backend."
            }
        }
    }

    @Published var isConnected: Bool = false
    @Published var isBusy: Bool = false
    @Published var statusText: String = "Disconnected"
    @Published var logText: String = ""
    /// Log lines written by the packet tunnel extension (read from App Group shared file); polled every second.
    @Published var extensionLogText: String = ""
    /// Inline troubleshooting (code 14 or VPN permission / error 5).
    @Published var showVpnProfileResetSuggestion = false
    /// One-shot alert after a configuration error; dismissing it keeps `showVpnProfileResetSuggestion` true.
    @Published var showVpnProfileResetAlert = false

    private let tunnelManager = VpnTunnelManager()
    private var extensionLogPollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    /// True while loadOrCreateConfiguration / setConfiguration is in progress.
    private var isPreparing: Bool = false
    /// True from Connect tap until startTunnel() has been called (or failed). Prevents multiple connect taps.
    private var connectInProgress: Bool = false
    private var previousTunnelStatus: NEVPNStatus = .invalid
    private var hasLoggedVpnDiagnostics: Bool = false
    /// When set, Connect uses backend (server list + OVPN file). When nil, uses placeholder config.
    private weak var authState: AuthStateStore?

    init(authState: AuthStateStore? = nil) {
        self.authState = authState
        tunnelManager.onLog = { [weak self] msg in self?.appendLog(msg) }
        tunnelManager.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncFromTunnel() }
            .store(in: &cancellables)
        tunnelManager.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncFromTunnel() }
            .store(in: &cancellables)
        startExtensionLogPolling()
    }

    deinit {
        extensionLogPollTimer?.invalidate()
    }

    private func startExtensionLogPolling() {
        extensionLogPollTimer?.invalidate()
        extensionLogPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshExtensionLog()
        }
        RunLoop.main.add(extensionLogPollTimer!, forMode: .common)
    }

    private func refreshExtensionLog() {
        extensionLogText = ExtensionLogReader.read()
    }

    func toggle() {
        if isConnected {
            disconnect()
        } else {
            connect()
        }
    }

    /// Call once when the UI appears so the tunnel config is ready for Connect.
    func ensureConfigurationLoaded() async {
        guard !isPreparing else { return }
        isPreparing = true
        if !hasLoggedVpnDiagnostics {
            hasLoggedVpnDiagnostics = true
            for line in VpnDiagnostics.buildReport().split(separator: "\n", omittingEmptySubsequences: false) {
                appendLog(String(line))
            }
        }
        appendLog("[Connect flow] Step 0: ensureConfigurationLoaded - loading tunnel config...")
        do {
            try await tunnelManager.loadOrCreateConfiguration()
            appendLog("[Connect flow] Step 0: tunnel configuration ready.")
            showVpnProfileResetSuggestion = false
            showVpnProfileResetAlert = false
        } catch {
            appendLog("[Connect flow] Step 0 FAIL: \(tunnelConfigurationErrorEnglishDescription(error, action: "loading VPN configuration"))")
            if shouldOfferVpnProfileResetAfterConfigurationError(error) {
                showVpnProfileResetSuggestion = true
                showVpnProfileResetAlert = true
            }
        }
        isPreparing = false
        syncFromTunnel()
    }

    func connect() {
        if connectInProgress || tunnelManager.isConnectingOrConnected {
            return
        }
        connectInProgress = true
        isBusy = true
        statusText = "Connecting..."
        ExtensionLogReader.clear()
        appendLog("[Connect flow] Connect tapped: starting...")

        Task { @MainActor in
            defer { connectInProgress = false; syncFromTunnel() }
            do {
                appendLog("[Connect flow] Step 1: loadOrCreateConfiguration...")
                try await tunnelManager.loadOrCreateConfiguration()
                let config: TunnelConfig
                if let auth = authState, let token = await auth.getValidAccessToken() {
                    appendLog("[Connect flow] Step 2: build config from backend (TunnelConfigBuilder)...")
                    if let backendConfig = await TunnelConfigBuilder.build(token: token, onLog: { [weak self] msg in self?.appendLog(msg) }) {
                        config = backendConfig
                        appendLog("[Connect flow] Step 2: using backend config \(config.host):\(config.port)")
                    } else {
                        appendLog("[Connect flow] Step 2 FAIL: backend did not return a usable tunnel config.")
                        throw ConnectFlowError.backendConfigUnavailable
                    }
                } else {
                    appendLog("[Connect flow] Step 2 FAIL: no valid auth token.")
                    throw ConnectFlowError.unauthorized
                }
                appendLog("[Connect flow] Step 3: setConfiguration + reload + startTunnel...")
                try await tunnelManager.setConfiguration(config)
                try await tunnelManager.reloadFromPreferences()
                try tunnelManager.startTunnel()
                appendLog("[Connect flow] Step 3: start requested; wait for status (Connecting -> Connected).")
                showVpnProfileResetSuggestion = false
                showVpnProfileResetAlert = false
            } catch {
                appendLog("[Connect flow] FAIL at step: \(tunnelConfigurationErrorEnglishDescription(error, action: "updating VPN configuration"))")
                if shouldOfferVpnProfileResetAfterConfigurationError(error) {
                    showVpnProfileResetSuggestion = true
                    showVpnProfileResetAlert = true
                }
                tunnelManager.stopTunnel()
            }
        }
    }

    func disconnect() {
        appendLog("[Connect flow] Disconnect tapped.")
        tunnelManager.stopTunnel()
        syncFromTunnel()
    }

    /// Removes the DataGate VPN entry from preferences so the next Connect creates a fresh profile (often needed after moving the .app to /Applications).
    func resetVpnProfile() async {
        appendLog("[Connect flow] Reset VPN profile: removing saved DataGate configuration...")
        isBusy = true
        defer { isBusy = false; syncFromTunnel() }
        do {
            try await tunnelManager.removeDataGateFromPreferences()
            try await tunnelManager.loadOrCreateConfiguration()
            appendLog("[Connect flow] Reset VPN profile: done. Try Connect again.")
            showVpnProfileResetSuggestion = false
            showVpnProfileResetAlert = false
        } catch {
            appendLog("[Connect flow] Reset VPN profile FAIL: \(tunnelConfigurationErrorEnglishDescription(error, action: "resetting VPN configuration"))")
        }
    }

    private func syncFromTunnel() {
        refreshExtensionLog()
        let current = tunnelManager.status
        if previousTunnelStatus == .connecting && (current == .disconnected || current == .invalid) && extensionLogText.isEmpty {
            appendLog("[Connect flow] Tunnel failed (no extension log). Check [Diagnostics] lines above; then Console.app → neagent / networkextensiond while tapping Connect; or run scripts/diagnose-vpn-extension.sh on the .app you actually run.")
        }
        previousTunnelStatus = current
        statusText = tunnelManager.statusDisplayText
        if let err = tunnelManager.lastError, !err.isEmpty {
            statusText += " (\(err))"
        }
        isConnected = tunnelManager.isConnected
        isBusy = connectInProgress || isPreparing || tunnelManager.isConnectingOrConnected
    }

    func dismissVpnProfileResetAlertOnly() {
        showVpnProfileResetAlert = false
    }

    func dismissVpnProfileResetSuggestion() {
        showVpnProfileResetSuggestion = false
        showVpnProfileResetAlert = false
    }

    private func appendLog(_ line: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        logText += "[\(ts)] \(line)\n"
    }
}
