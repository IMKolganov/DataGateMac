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
        case tunnelBuild(TunnelConfigBuildError)
        case manualProfileMissing
        case manualProfileInvalid(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return L10n.tr("vpn_flow_sign_in_again", "Sign in again before connecting.")
            case .backendConfigUnavailable:
                return L10n.tr("vpn_flow_backend_unavailable", "Could not build VPN configuration from the backend.")
            case .tunnelBuild(let e):
                return e.errorDescription
            case .manualProfileMissing:
                return L10n.tr("profiles_err_missing", "That local profile is no longer on disk.")
            case .manualProfileInvalid(let detail):
                return detail
            }
        }
    }

    private enum HomeVpnPrefs {
        static let autoKey = "imkolganov.DataGateMac.homeVpnServerPickAutomatic"
        static let manualIdKey = "imkolganov.DataGateMac.homeVpnManualServerId"
    }

    private enum TunnelSessionPrefs {
        static let summaryKey = "imkolganov.DataGateMac.lastTunnelSummary"
        static let manualProfileIdKey = "imkolganov.DataGateMac.connectedManualProfileId"
    }

    @Published var isConnected: Bool = false
    /// True while Connect cannot be tapped again (loading prefs, connect task, or tunnel is connecting / disconnecting). When status is Connected, this is false so Disconnect stays enabled.
    @Published var isBusy: Bool = false
    @Published var statusText: String = L10n.tr("vpn_status_disconnected", "Disconnected")
    /// Set when a backend tunnel config is applied (server label + WSS endpoint). Cleared when the tunnel is disconnected.
    @Published var activeTunnelSummary: String = ""
    @Published var logText: String = ""
    /// Log lines written by the packet tunnel extension (read from App Group shared file); polled every second.
    @Published var extensionLogText: String = ""
    /// Inline troubleshooting (code 14 or VPN permission / error 5).
    @Published var showVpnProfileResetSuggestion = false
    /// One-shot alert after a configuration error; dismissing it keeps `showVpnProfileResetSuggestion` true.
    @Published var showVpnProfileResetAlert = false
    /// Servers for Home picker (refreshed from the same API as connect).
    @Published var vpnServerRows: [HomeVpnServerRow] = []
    @Published var isRefreshingServerList = false
    @Published var serverListBanner: String = ""
    /// `true` = automatic best server (Linux/Win-style). `false` = user-selected `manualServerId`.
    @Published var serverPickAutomatic = true
    @Published var manualServerId: Int = 0
    /// Local profile currently applied to the DataGate tunnel (cleared on backend Connect / disconnect).
    @Published var connectedManualProfileId: UUID?
    /// Last connect failure for a local profile, shown on the Profiles list.
    @Published var lastManualConnectErrorById: [UUID: String] = [:]

    private let tunnelManager = VpnTunnelManager()
    private let manualProfileStore: ManualVpnProfileStore
    private var extensionLogPollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    /// Reading the shared App Group container from the host app triggers
    /// macOS "access data from other apps" prompts on some systems.
    /// Keep automatic reads off by default; use Console/shared file only when needed.
    private let autoReadExtensionLogsFromAppGroup = false
    /// True while loadOrCreateConfiguration / setConfiguration is in progress.
    private var isPreparing: Bool = false
    /// True from Connect tap until startTunnel() has been called (or failed). Prevents multiple connect taps.
    private var connectInProgress: Bool = false
    private var previousTunnelStatus: NEVPNStatus = .invalid
    private var hasLoggedVpnDiagnostics: Bool = false
    private var hasLoadedTunnelConfiguration = false
    /// After Disconnect, NE status stays `.connected` until the stop completes; skip restoring the session from providerConfiguration.
    private var ignoreTunnelSessionRestore = false
    private var languageChangeObserver: NSObjectProtocol?
    /// When set, Connect uses backend (server list + OVPN file). When nil, uses placeholder config.
    private weak var authState: AuthStateStore?
    private var homeVpnPrefsLoaded = false

    init(authState: AuthStateStore? = nil, manualProfileStore: ManualVpnProfileStore? = nil) {
        self.authState = authState
        self.manualProfileStore = manualProfileStore ?? ManualVpnProfileStore.shared
        loadHomeVpnPrefsFromDefaults()
        restoreTunnelSessionFromDefaults()
        homeVpnPrefsLoaded = true
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

        languageChangeObserver = NotificationCenter.default.addObserver(
            forName: .appLanguageChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncFromTunnel() }
        }
    }

    deinit {
        extensionLogPollTimer?.invalidate()
        if let o = languageChangeObserver {
            NotificationCenter.default.removeObserver(o)
        }
    }

    private func startExtensionLogPolling() {
        guard autoReadExtensionLogsFromAppGroup else {
            extensionLogPollTimer?.invalidate()
            extensionLogPollTimer = nil
            return
        }
        extensionLogPollTimer?.invalidate()
        extensionLogPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshExtensionLog()
        }
        RunLoop.main.add(extensionLogPollTimer!, forMode: .common)
    }

    private func refreshExtensionLog() {
        guard autoReadExtensionLogsFromAppGroup else {
            extensionLogText = ""
            return
        }
        // Avoid reading the App Group from the host while idle or connecting — macOS 15+ may prompt
        // ("…access data from other apps") on each container access when the profile does not fully authorize the group.
        let s = tunnelManager.status
        guard s == .connected || s == .reasserting || s == .disconnecting else {
            extensionLogText = ""
            return
        }
        extensionLogText = ExtensionLogReader.read()
    }

    func toggle() {
        if isConnected {
            disconnect()
        } else {
            connect()
        }
    }

    /// Matches Windows home: Connect only when idle / disconnected; not while busy or already tunneling
    /// a backend server. Allowed while a local profile is connected so Home can switch back to the backend.
    var canTapConnect: Bool {
        guard !isBusy && !connectInProgress else { return false }
        let status = tunnelManager.status
        if status == .connecting || status == .disconnecting { return false }
        if (status == .connected || status == .reasserting) && connectedManualProfileId == nil {
            return false
        }
        if !serverPickAutomatic {
            return vpnServerRows.contains(where: { $0.id == manualServerId })
        }
        return true
    }

    /// Disconnect when connected or reasserting; disabled while connecting/disconnecting or other busy work.
    var canTapDisconnect: Bool {
        !isBusy && (tunnelManager.status == .connected || tunnelManager.status == .reasserting)
    }

    /// Call once when the UI appears so the tunnel config is ready for Connect.
    func ensureConfigurationLoaded(refreshServers: Bool = true) async {
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
            hasLoadedTunnelConfiguration = true
            showVpnProfileResetSuggestion = false
            showVpnProfileResetAlert = false
        } catch {
            appendLog("[Connect flow] Step 0 FAIL: \(tunnelConfigurationErrorLocalizedDescription(error, action: L10n.tr("vpn_action_loading_config", "loading VPN configuration")))")
            if shouldOfferVpnProfileResetAfterConfigurationError(error) {
                showVpnProfileResetSuggestion = true
                showVpnProfileResetAlert = true
            }
        }
        isPreparing = false
        syncFromTunnel()
        if refreshServers {
            await refreshServerList()
        }
    }

    func refreshServerList() async {
        guard let auth = authState else {
            vpnServerRows = []
            serverListBanner = ""
            return
        }
        guard let token = await auth.getValidAccessToken() else {
            vpnServerRows = []
            serverListBanner = L10n.tr("home_server_list_need_sign_in", "Sign in to load the server list.")
            return
        }
        isRefreshingServerList = true
        serverListBanner = ""
        defer { isRefreshingServerList = false }
        do {
            let servers = try await OpenVpnServersApiClient.shared.getAllWithStatus(token: token, withoutCache: true)
            vpnServerRows = TunnelConfigBuilder.homeRows(from: servers)
            normalizeManualServerSelection()
            if vpnServerRows.isEmpty {
                serverListBanner = L10n.tr("home_server_list_empty", "No servers returned for your account.")
            }
        } catch {
            serverListBanner = error.localizedDescription
        }
    }

    private func loadHomeVpnPrefsFromDefaults() {
        if UserDefaults.standard.object(forKey: HomeVpnPrefs.autoKey) != nil {
            serverPickAutomatic = UserDefaults.standard.bool(forKey: HomeVpnPrefs.autoKey)
        }
        let m = UserDefaults.standard.integer(forKey: HomeVpnPrefs.manualIdKey)
        if m > 0 {
            manualServerId = m
        }
    }

    private func persistHomeVpnPrefs() {
        guard homeVpnPrefsLoaded else { return }
        UserDefaults.standard.set(serverPickAutomatic, forKey: HomeVpnPrefs.autoKey)
        UserDefaults.standard.set(manualServerId, forKey: HomeVpnPrefs.manualIdKey)
    }

    /// After loading `vpnServerRows`, keep manual selection valid for the picker.
    private func normalizeManualServerSelection() {
        let ids = Set(vpnServerRows.map(\.id))
        if serverPickAutomatic { return }
        if manualServerId == 0 || !ids.contains(manualServerId), let first = vpnServerRows.first {
            manualServerId = first.id
            persistHomeVpnPrefs()
        }
    }

    func connect() {
        if connectInProgress {
            return
        }
        ignoreTunnelSessionRestore = false
        connectInProgress = true
        isBusy = true
        statusText = L10n.tr("vpn_status_connecting", "Connecting...")
        extensionLogText = ""
        appendLog("[Connect flow] Connect tapped: starting...")

        Task { @MainActor in
            defer { connectInProgress = false; syncFromTunnel() }
            do {
                try await runConnectFlow(allowProfileRecreateRetry: true)
            } catch let flow as ConnectFlowError {
                clearTunnelSession()
                appendLog("[Connect flow] FAIL: \(flow.errorDescription ?? "Unknown error")")
                tunnelManager.stopTunnel()
            } catch {
                clearTunnelSession()
                appendLog("[Connect flow] FAIL at step: \(tunnelConfigurationErrorLocalizedDescription(error, action: L10n.tr("vpn_action_updating_config", "updating VPN configuration")))")
                if shouldOfferVpnProfileResetAfterConfigurationError(error) {
                    showVpnProfileResetSuggestion = true
                    showVpnProfileResetAlert = true
                }
                tunnelManager.stopTunnel()
            }
        }
    }

    /// Starts the tunnel from a locally imported profile. Does not call the backend or require quota.
    func connectManualProfile(id: UUID) {
        if connectInProgress {
            return
        }
        ignoreTunnelSessionRestore = false
        connectInProgress = true
        isBusy = true
        statusText = L10n.tr("vpn_status_connecting", "Connecting...")
        extensionLogText = ""
        appendLog("[Connect flow] Local profile Connect tapped: starting...")

        Task { @MainActor in
            defer { connectInProgress = false; syncFromTunnel() }
            do {
                try await runManualConnectFlow(profileId: id, allowProfileRecreateRetry: true)
                var errors = lastManualConnectErrorById
                errors.removeValue(forKey: id)
                lastManualConnectErrorById = errors
            } catch let flow as ConnectFlowError {
                recordManualConnectError(id: id, message: flow.errorDescription ?? "Unknown error")
                clearTunnelSession()
                appendLog("[Connect flow] FAIL: \(flow.errorDescription ?? "Unknown error")")
                tunnelManager.stopTunnel()
            } catch {
                let message = tunnelConfigurationErrorLocalizedDescription(error, action: L10n.tr("vpn_action_updating_config", "updating VPN configuration"))
                recordManualConnectError(id: id, message: message)
                clearTunnelSession()
                appendLog("[Connect flow] FAIL at step: \(message)")
                if shouldOfferVpnProfileResetAfterConfigurationError(error) {
                    showVpnProfileResetSuggestion = true
                    showVpnProfileResetAlert = true
                }
                tunnelManager.stopTunnel()
            }
        }
    }

    var canTapManualConnect: Bool {
        !isBusy && !connectInProgress && tunnelManager.status != .connecting && tunnelManager.status != .disconnecting
    }

    func isManualProfileConnected(_ id: UUID) -> Bool {
        connectedManualProfileId == id && (tunnelManager.isConnectingOrConnected || tunnelManager.status == .disconnecting)
    }

    func noteRenamedManualProfile(id: UUID, displayName: String) {
        guard connectedManualProfileId == id, var config = tunnelManager.currentTunnelConfig() else { return }
        config.serverDisplayName = displayName
        applyTunnelSession(from: config)
    }

    var recentConnectLogExcerpt: String {
        let lines = logText.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(8).joined(separator: "\n")
    }

    private func recordManualConnectError(id: UUID, message: String) {
        var errors = lastManualConnectErrorById
        errors[id] = message
        lastManualConnectErrorById = errors
    }

    /// Loads config, activates sysex, applies backend settings, starts tunnel; recreates VPN profile once on code 14.
    private func runConnectFlow(allowProfileRecreateRetry: Bool) async throws {
        await stopTunnelIfNeededForSwitch()
        appendLog("[Connect flow] Step 1: loadOrCreateConfiguration...")
        try await tunnelManager.loadOrCreateConfiguration()
        hasLoadedTunnelConfiguration = true
        appendLog("[Connect flow] Step 1b: activate packet tunnel system extension...")
        try await SystemExtensionInstaller.activateIfNeeded()
        appendLog("[Connect flow] Step 1b: system extension activation OK.")
        let config: TunnelConfig
        if let auth = authState, let token = await auth.getValidAccessToken() {
            appendLog("[Connect flow] Step 2: build config from backend (TunnelConfigBuilder)...")
            let pick: TunnelServerPick = serverPickAutomatic
                ? .automatic
                : .manual(serverId: manualServerId)
            do {
                config = try await TunnelConfigBuilder.build(
                    token: token,
                    serverPick: pick,
                    onLog: { [weak self] msg in self?.appendLog(msg) }
                )
                appendLog("[Connect flow] Step 2: using backend config \(config.host):\(config.port)")
            } catch let e as TunnelConfigBuildError {
                appendLog("[Connect flow] Step 2 FAIL: \(e.localizedDescription)")
                throw ConnectFlowError.tunnelBuild(e)
            } catch {
                appendLog("[Connect flow] Step 2 FAIL: \(error.localizedDescription)")
                throw ConnectFlowError.backendConfigUnavailable
            }
        } else {
            appendLog("[Connect flow] Step 2 FAIL: no valid auth token.")
            throw ConnectFlowError.unauthorized
        }
        try await startTunnelWithConfiguration(config, allowProfileRecreateRetry: allowProfileRecreateRetry)
        showVpnProfileResetSuggestion = false
        showVpnProfileResetAlert = false
    }

    private func runManualConnectFlow(profileId: UUID, allowProfileRecreateRetry: Bool) async throws {
        await stopTunnelIfNeededForSwitch()
        appendLog("[Connect flow] Step 1: loadOrCreateConfiguration...")
        try await tunnelManager.loadOrCreateConfiguration()
        hasLoadedTunnelConfiguration = true
        appendLog("[Connect flow] Step 1b: activate packet tunnel system extension...")
        try await SystemExtensionInstaller.activateIfNeeded()
        appendLog("[Connect flow] Step 1b: system extension activation OK.")
        let profile: ManualVpnProfile
        do {
            profile = try manualProfileStore.profile(id: profileId)
        } catch {
            throw ConnectFlowError.manualProfileMissing
        }
        appendLog("[Connect flow] Step 2: using local profile \(profile.displayName) (\(profile.kind.rawValue))")
        let config: TunnelConfig
        do {
            config = try ManualVpnProfileImporter.makeTunnelConfig(from: profile)
        } catch {
            throw ConnectFlowError.manualProfileInvalid(error.localizedDescription)
        }
        appendLog("[Connect flow] Step 2: local endpoint \(config.host):\(config.port)")
        try await startTunnelWithConfiguration(config, allowProfileRecreateRetry: allowProfileRecreateRetry)
        showVpnProfileResetSuggestion = false
        showVpnProfileResetAlert = false
    }

    private func stopTunnelIfNeededForSwitch() async {
        guard tunnelManager.isConnectingOrConnected else { return }
        appendLog("[Connect flow] Stopping the current tunnel before applying a new profile...")
        tunnelManager.stopTunnel()
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if tunnelManager.status == .disconnected || tunnelManager.status == .invalid {
                break
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func startTunnelWithConfiguration(_ config: TunnelConfig, allowProfileRecreateRetry: Bool) async throws {
        appendLog("[Connect flow] Step 3: setConfiguration(if changed) + reload + startTunnel...")
        applyTunnelSession(from: config)
        try await tunnelManager.setConfiguration(config)
        try await tunnelManager.reloadFromPreferences()
        try tunnelManager.startTunnel()
        appendLog("[Connect flow] Step 3: start requested; wait for status (Connecting -> Connected).")

        let outcome = await tunnelManager.waitForConnectOutcome(timeout: 3.0)
        if outcome == .connected {
            appendLog("[Connect flow] Step 3: tunnel connected.")
            return
        }
        guard allowProfileRecreateRetry else { return }

        let disconnectError = await tunnelManager.fetchLastDisconnectError()
        let ns = disconnectError as NSError?
        let shouldRetry = VpnProfileMigrationPolicy.shouldRetryConnectAfterCode14(
            tunnelDisconnected: outcome == .disconnected,
            disconnectDomain: ns?.domain,
            disconnectCode: ns.map(\.code),
            allowRetry: true
        )
        guard shouldRetry else { return }

        appendLog("[Connect flow] Code 14 detected — recreating VPN profile and retrying Connect once...")
        try await tunnelManager.recreateDataGateProfile(reason: "code 14 after startVPNTunnel")
        try await tunnelManager.setConfiguration(config)
        try await tunnelManager.reloadFromPreferences()
        try tunnelManager.startTunnel()
        appendLog("[Connect flow] Step 3 (retry): start requested after profile recreate.")
    }

    func updateServerPickAutomatic(_ value: Bool) {
        serverPickAutomatic = value
        persistHomeVpnPrefs()
        if !value {
            normalizeManualServerSelection()
        }
    }

    func updateManualServerId(_ value: Int) {
        manualServerId = value
        persistHomeVpnPrefs()
    }

    func disconnect() {
        appendLog("[Connect flow] Disconnect tapped.")
        ignoreTunnelSessionRestore = true
        clearTunnelSession()
        tunnelManager.stopTunnel()
        syncFromTunnel()
    }

    /// Removes the DataGate VPN entry from preferences so the next Connect creates a fresh profile (often needed after moving the .app to /Applications).
    func resetVpnProfile() async {
        appendLog("[Connect flow] Reset VPN profile: removing saved DataGate configuration...")
        isBusy = true
        defer { isBusy = false; syncFromTunnel() }
        do {
            try await tunnelManager.recreateDataGateProfile(reason: "user requested reset")
            appendLog("[Connect flow] Reset VPN profile: done. Try Connect again.")
            showVpnProfileResetSuggestion = false
            showVpnProfileResetAlert = false
        } catch {
            appendLog("[Connect flow] Reset VPN profile FAIL: \(tunnelConfigurationErrorLocalizedDescription(error, action: L10n.tr("vpn_action_resetting_config", "resetting VPN configuration")))")
        }
    }

    private func syncFromTunnel() {
        refreshExtensionLog()
        let current = tunnelManager.status
        let oldStatus = previousTunnelStatus
        if oldStatus == .connecting && (current == .disconnected || current == .invalid) && extensionLogText.isEmpty {
            appendLog("[Connect flow] Tunnel failed (no extension log). Check [Diagnostics] lines above; then Console.app → neagent / networkextensiond while tapping Connect; or run scripts/diagnose-vpn-extension.sh on the .app you actually run.")
        }
        previousTunnelStatus = current
        statusText = tunnelManager.statusDisplayText
        if let err = tunnelManager.lastError, !err.isEmpty {
            statusText += " (\(err))"
        }
        isConnected = tunnelManager.isConnected
        // Do not treat `.connected` (or `.reasserting`) as "busy" for the main button — user must be able to Disconnect.
        isBusy = connectInProgress
            || isPreparing
            || current == .connecting
            || current == .disconnecting
        if current == .disconnected || current == .invalid {
            ignoreTunnelSessionRestore = false
            if hasLoadedTunnelConfiguration && !connectInProgress {
                clearTunnelSession()
            }
        } else if current == .connected || current == .connecting || current == .reasserting {
            if connectInProgress || ignoreTunnelSessionRestore {
                // Keep the session written for an in-flight connect, or the cleared session after Disconnect.
            } else if let config = tunnelManager.currentTunnelConfig() {
                applyTunnelSession(from: config)
            } else if activeTunnelSummary.isEmpty {
                restoreTunnelSessionFromDefaults()
            }
        }
    }

    private func applyTunnelSession(from config: TunnelConfig) {
        let transport: String
        switch config.transportMode {
        case .direct:
            transport = L10n.tr("home_server_openvpn_label", "OpenVPN")
        case .xray:
            transport = L10n.tr("home_server_xray_label", "Xray")
        case .wss:
            transport = "WSS"
        }
        let proto = config.linkProtocol.rawValue.uppercased()
        let localPrefix = config.manualProfileId == nil
            ? ""
            : L10n.tr("profiles_local_prefix", "Local") + " · "
        persistTunnelSession(
            summary: "\(localPrefix)\(config.serverDisplayName) · \(transport) · \(proto) · \(config.host):\(config.port)",
            manualProfileId: config.manualProfileId
        )
    }

    private func persistTunnelSession(summary: String, manualProfileId: String?) {
        activeTunnelSummary = summary
        if let manualProfileId, let uuid = UUID(uuidString: manualProfileId) {
            connectedManualProfileId = uuid
        } else {
            connectedManualProfileId = nil
        }
        UserDefaults.standard.set(summary, forKey: TunnelSessionPrefs.summaryKey)
        if let connectedManualProfileId {
            UserDefaults.standard.set(connectedManualProfileId.uuidString, forKey: TunnelSessionPrefs.manualProfileIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: TunnelSessionPrefs.manualProfileIdKey)
        }
    }

    private func restoreTunnelSessionFromDefaults() {
        activeTunnelSummary = UserDefaults.standard.string(forKey: TunnelSessionPrefs.summaryKey) ?? ""
        if let raw = UserDefaults.standard.string(forKey: TunnelSessionPrefs.manualProfileIdKey) {
            connectedManualProfileId = UUID(uuidString: raw)
        } else {
            connectedManualProfileId = nil
        }
    }

    private func clearTunnelSession() {
        activeTunnelSummary = ""
        connectedManualProfileId = nil
        UserDefaults.standard.removeObject(forKey: TunnelSessionPrefs.summaryKey)
        UserDefaults.standard.removeObject(forKey: TunnelSessionPrefs.manualProfileIdKey)
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
