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
        case cancelled

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
            case .cancelled:
                return nil
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
        static let commonNameKey = "imkolganov.DataGateMac.lastTunnelClientCommonName"
        static let issuedFileNameKey = "imkolganov.DataGateMac.lastTunnelIssuedFileName"
        static let serverNameKey = "imkolganov.DataGateMac.lastTunnelServerName"
        static let transportKey = "imkolganov.DataGateMac.lastTunnelTransport"
        static let protoKey = "imkolganov.DataGateMac.lastTunnelProto"
        static let endpointKey = "imkolganov.DataGateMac.lastTunnelEndpoint"
    }

    @Published var isConnected: Bool = false
    /// True while Connect cannot be tapped again (loading prefs, connect task, or tunnel is connecting / disconnecting). When status is Connected, this is false so Disconnect stays enabled.
    @Published var isBusy: Bool = false
    @Published var statusText: String = L10n.tr("vpn_status_disconnected", "Disconnected")
    /// Set when a backend tunnel config is applied (server label + WSS endpoint). Cleared when the tunnel is disconnected.
    @Published var activeTunnelSummary: String = ""
    @Published var activeServerName: String = ""
    @Published var activeTransport: String = ""
    @Published var activeProto: String = ""
    @Published var activeEndpoint: String = ""
    /// Device CN issued for this backend OpenVPN / Xray client. Empty for local profiles.
    @Published var activeClientCommonName: String = ""
    /// Issued OVPN / client-link file name from the backend, when available.
    @Published var activeIssuedFileName: String = ""
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
    @Published var liveTrafficSamples: [LiveTrafficSample] = []
    @Published var liveBytesIn: UInt64 = 0
    @Published var liveBytesOut: UInt64 = 0
    @Published var liveDownBytesPerSec: Double = 0
    @Published var liveUpBytesPerSec: Double = 0

    private let tunnelManager = VpnTunnelManager()
    private let manualProfileStore: ManualVpnProfileStore
    private var extensionLogPollTimer: Timer?
    private var liveTrafficPollTimer: Timer?
    private var lastLiveBytesIn: UInt64?
    private var lastLiveBytesOut: UInt64?
    private var lastLiveTrafficAt: Date?
    private var cancellables = Set<AnyCancellable>()
    /// Reading the shared App Group container from the host app triggers
    /// macOS "access data from other apps" prompts on some systems.
    /// Keep automatic reads off by default; use Console/shared file only when needed.
    private let autoReadExtensionLogsFromAppGroup = false
    /// True while loadOrCreateConfiguration / setConfiguration is in progress.
    private var isPreparing: Bool = false
    /// True from Connect tap until startTunnel() has been called (or failed). Prevents multiple connect taps.
    private var connectInProgress: Bool = false
    /// Bumped on each Connect/Disconnect so an in-flight connect cannot restart the tunnel after cancel.
    private var connectGeneration: Int = 0
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
        liveTrafficPollTimer?.invalidate()
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

    /// Disconnect when connected, reconnecting, still connecting, or while a connect attempt is in progress (cancel, including sysex activation).
    var canTapDisconnect: Bool {
        !isPreparing && (
            connectInProgress
            || tunnelManager.status == .connected
            || tunnelManager.status == .reasserting
            || tunnelManager.status == .connecting
        )
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
        ignoreTunnelSessionRestore = false
        connectedManualProfileId = nil
        let generation = beginConnectAttempt()
        isBusy = true
        statusText = L10n.tr("vpn_status_connecting", "Connecting...")
        extensionLogText = ""
        appendLog("[Connect flow] Connect tapped: starting...")

        Task { @MainActor in
            defer { endConnectAttempt(generation) }
            do {
                try await runConnectFlow(generation: generation, allowProfileRecreateRetry: true)
            } catch ConnectFlowError.cancelled {
                appendLog("[Connect flow] Connect cancelled.")
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
        ignoreTunnelSessionRestore = false
        connectedManualProfileId = id
        clearManualConnectError(id: id)
        let generation = beginConnectAttempt()
        isBusy = true
        statusText = L10n.tr("vpn_status_connecting", "Connecting...")
        extensionLogText = ""
        appendLog("[Connect flow] Local profile Connect tapped: starting...")

        Task { @MainActor in
            defer { endConnectAttempt(generation) }
            do {
                try await runManualConnectFlow(profileId: id, generation: generation, allowProfileRecreateRetry: true)
                guard generation == connectGeneration else { return }
                var errors = lastManualConnectErrorById
                errors.removeValue(forKey: id)
                lastManualConnectErrorById = errors
            } catch ConnectFlowError.cancelled {
                appendLog("[Connect flow] Local profile Connect cancelled.")
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
        connectedManualProfileId == id && (
            connectInProgress
            || tunnelManager.isConnectingOrConnected
            || tunnelManager.status == .disconnecting
        )
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

    var connectionIdentityRows: [TunnelSessionIdentityRow] {
        var rows: [TunnelSessionIdentityRow] = []
        let server = activeServerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !server.isEmpty {
            rows.append(TunnelSessionIdentityRow(
                id: "server",
                label: L10n.tr("home_identity_server", "Server"),
                value: server
            ))
        }
        let protocolValue = [activeTransport, activeProto]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        if !protocolValue.isEmpty {
            rows.append(TunnelSessionIdentityRow(
                id: "protocol",
                label: L10n.tr("home_identity_protocol", "Protocol"),
                value: protocolValue
            ))
        }
        let endpoint = activeEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !endpoint.isEmpty {
            rows.append(TunnelSessionIdentityRow(
                id: "address",
                label: L10n.tr("home_identity_address", "Address"),
                value: endpoint,
                usesMonospace: true
            ))
        }
        let cn = activeClientCommonName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cn.isEmpty {
            rows.append(TunnelSessionIdentityRow(
                id: "cn",
                label: L10n.tr("home_identity_cn", "CN"),
                value: cn,
                usesMonospace: true
            ))
        }
        if rows.isEmpty {
            let fallback = activeTunnelSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                rows.append(TunnelSessionIdentityRow(
                    id: "summary",
                    label: L10n.tr("home_identity_server", "Server"),
                    value: fallback
                ))
            }
        }
        return rows
    }

    func clearManualConnectError(id: UUID) {
        var errors = lastManualConnectErrorById
        errors.removeValue(forKey: id)
        lastManualConnectErrorById = errors
    }

    private func beginConnectAttempt() -> Int {
        connectGeneration += 1
        connectInProgress = true
        return connectGeneration
    }

    private func endConnectAttempt(_ generation: Int) {
        guard generation == connectGeneration else { return }
        connectInProgress = false
        syncFromTunnel()
    }

    private func throwIfConnectCancelled(_ generation: Int) throws {
        if generation != connectGeneration {
            throw ConnectFlowError.cancelled
        }
    }

    private func recordManualConnectError(id: UUID, message: String) {
        var errors = lastManualConnectErrorById
        errors[id] = message
        lastManualConnectErrorById = errors
    }

    /// Loads config, activates sysex, applies backend settings, starts tunnel; recreates VPN profile once on code 14.
    private func runConnectFlow(generation: Int, allowProfileRecreateRetry: Bool) async throws {
        await stopTunnelIfNeededForSwitch()
        try throwIfConnectCancelled(generation)
        appendLog("[Connect flow] Step 1: loadOrCreateConfiguration...")
        try await tunnelManager.loadOrCreateConfiguration()
        hasLoadedTunnelConfiguration = true
        try throwIfConnectCancelled(generation)
        appendLog("[Connect flow] Step 1b: activate packet tunnel system extension...")
        try await SystemExtensionInstaller.activateIfNeeded()
        try throwIfConnectCancelled(generation)
        appendLog("[Connect flow] Step 1b: system extension activation OK.")
        let config: TunnelConfig
        if let auth = authState {
            guard let token = await auth.getValidAccessToken() else {
                let reason = auth.lastTokenFailureDescription
                if let reason, !reason.isEmpty {
                    appendLog("[Connect flow] Step 2 FAIL: no valid auth token (\(reason)).")
                } else {
                    appendLog("[Connect flow] Step 2 FAIL: no valid auth token.")
                }
                throw ConnectFlowError.unauthorized
            }
            try throwIfConnectCancelled(generation)
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
        try throwIfConnectCancelled(generation)
        try await startTunnelWithConfiguration(config, generation: generation, allowProfileRecreateRetry: allowProfileRecreateRetry)
        showVpnProfileResetSuggestion = false
        showVpnProfileResetAlert = false
    }

    private func runManualConnectFlow(profileId: UUID, generation: Int, allowProfileRecreateRetry: Bool) async throws {
        await stopTunnelIfNeededForSwitch()
        try throwIfConnectCancelled(generation)
        appendLog("[Connect flow] Step 1: loadOrCreateConfiguration...")
        try await tunnelManager.loadOrCreateConfiguration()
        hasLoadedTunnelConfiguration = true
        try throwIfConnectCancelled(generation)
        appendLog("[Connect flow] Step 1b: activate packet tunnel system extension...")
        try await SystemExtensionInstaller.activateIfNeeded()
        try throwIfConnectCancelled(generation)
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
        try throwIfConnectCancelled(generation)
        try await startTunnelWithConfiguration(config, generation: generation, allowProfileRecreateRetry: allowProfileRecreateRetry)
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

    private func startTunnelWithConfiguration(_ config: TunnelConfig, generation: Int, allowProfileRecreateRetry: Bool) async throws {
        try throwIfConnectCancelled(generation)
        appendLog("[Connect flow] Step 3: setConfiguration(if changed) + reload + startTunnel...")
        applyTunnelSession(from: config)
        try await tunnelManager.setConfiguration(config)
        try throwIfConnectCancelled(generation)
        try await tunnelManager.reloadFromPreferences()
        try throwIfConnectCancelled(generation)
        try tunnelManager.startTunnel()
        appendLog("[Connect flow] Step 3: start requested; wait for status (Connecting -> Connected).")

        let outcome = await tunnelManager.waitForConnectOutcome(timeout: 3.0)
        try throwIfConnectCancelled(generation)
        if outcome == .connected {
            appendLog("[Connect flow] Step 3: tunnel connected.")
            return
        }
        guard allowProfileRecreateRetry else { return }

        let disconnectError = await tunnelManager.fetchLastDisconnectError()
        try throwIfConnectCancelled(generation)
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
        try throwIfConnectCancelled(generation)
        try await tunnelManager.setConfiguration(config)
        try await tunnelManager.reloadFromPreferences()
        try throwIfConnectCancelled(generation)
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
        connectGeneration += 1
        connectInProgress = false
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
        if isConnected || current == .reasserting {
            startLiveTrafficPolling()
        } else {
            stopLiveTrafficPolling()
        }
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
            serverName: "\(localPrefix)\(config.serverDisplayName)",
            transport: transport,
            proto: proto,
            endpoint: "\(config.host):\(config.port)",
            manualProfileId: config.manualProfileId,
            clientCommonName: config.clientCommonName,
            issuedFileName: config.issuedFileName
        )
    }

    private func persistTunnelSession(
        serverName: String,
        transport: String,
        proto: String,
        endpoint: String,
        manualProfileId: String?,
        clientCommonName: String?,
        issuedFileName: String?
    ) {
        let server = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let transportValue = transport.trimmingCharacters(in: .whitespacesAndNewlines)
        let protoValue = proto.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointValue = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let cn = clientCommonName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let file = issuedFileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        activeServerName = server
        activeTransport = transportValue
        activeProto = protoValue
        activeEndpoint = endpointValue
        activeClientCommonName = cn
        activeIssuedFileName = file
        activeTunnelSummary = [server, transportValue, protoValue, endpointValue]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        if let manualProfileId, let uuid = UUID(uuidString: manualProfileId) {
            connectedManualProfileId = uuid
        } else {
            connectedManualProfileId = nil
        }
        let defaults = UserDefaults.standard
        defaults.set(activeTunnelSummary, forKey: TunnelSessionPrefs.summaryKey)
        Self.setOptionalDefault(defaults, key: TunnelSessionPrefs.serverNameKey, value: server)
        Self.setOptionalDefault(defaults, key: TunnelSessionPrefs.transportKey, value: transportValue)
        Self.setOptionalDefault(defaults, key: TunnelSessionPrefs.protoKey, value: protoValue)
        Self.setOptionalDefault(defaults, key: TunnelSessionPrefs.endpointKey, value: endpointValue)
        Self.setOptionalDefault(defaults, key: TunnelSessionPrefs.commonNameKey, value: cn)
        Self.setOptionalDefault(defaults, key: TunnelSessionPrefs.issuedFileNameKey, value: file)
        if let connectedManualProfileId {
            defaults.set(connectedManualProfileId.uuidString, forKey: TunnelSessionPrefs.manualProfileIdKey)
        } else {
            defaults.removeObject(forKey: TunnelSessionPrefs.manualProfileIdKey)
        }
    }

    private static func setOptionalDefault(_ defaults: UserDefaults, key: String, value: String) {
        if value.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(value, forKey: key)
        }
    }

    private func restoreTunnelSessionFromDefaults() {
        let defaults = UserDefaults.standard
        activeTunnelSummary = defaults.string(forKey: TunnelSessionPrefs.summaryKey) ?? ""
        activeServerName = defaults.string(forKey: TunnelSessionPrefs.serverNameKey) ?? ""
        activeTransport = defaults.string(forKey: TunnelSessionPrefs.transportKey) ?? ""
        activeProto = defaults.string(forKey: TunnelSessionPrefs.protoKey) ?? ""
        activeEndpoint = defaults.string(forKey: TunnelSessionPrefs.endpointKey) ?? ""
        activeClientCommonName = defaults.string(forKey: TunnelSessionPrefs.commonNameKey) ?? ""
        activeIssuedFileName = defaults.string(forKey: TunnelSessionPrefs.issuedFileNameKey) ?? ""
        if activeServerName.isEmpty, activeEndpoint.isEmpty, !activeTunnelSummary.isEmpty {
            let parsed = Self.parsedIdentity(fromSummary: activeTunnelSummary)
            activeServerName = parsed.server
            activeTransport = parsed.transport
            activeProto = parsed.proto
            activeEndpoint = parsed.endpoint
        }
        if let raw = defaults.string(forKey: TunnelSessionPrefs.manualProfileIdKey) {
            connectedManualProfileId = UUID(uuidString: raw)
        } else {
            connectedManualProfileId = nil
        }
    }

    private static func parsedIdentity(fromSummary summary: String) -> (server: String, transport: String, proto: String, endpoint: String) {
        let parts = summary
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { part in
                let lower = part.lowercased()
                if lower.hasPrefix("cn:") { return false }
                if lower.hasPrefix("file:") { return false }
                if part.hasPrefix("Файл:") { return false }
                return true
            }
        switch parts.count {
        case 0:
            return ("", "", "", "")
        case 1:
            return (parts[0], "", "", "")
        case 2:
            return (parts[0], parts[1], "", "")
        case 3:
            return (parts[0], parts[1], parts[2], "")
        default:
            return (parts[0], parts[1], parts[2], parts.dropFirst(3).joined(separator: " · "))
        }
    }

    private func clearTunnelSession() {
        activeTunnelSummary = ""
        activeServerName = ""
        activeTransport = ""
        activeProto = ""
        activeEndpoint = ""
        activeClientCommonName = ""
        activeIssuedFileName = ""
        connectedManualProfileId = nil
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: TunnelSessionPrefs.summaryKey)
        defaults.removeObject(forKey: TunnelSessionPrefs.serverNameKey)
        defaults.removeObject(forKey: TunnelSessionPrefs.transportKey)
        defaults.removeObject(forKey: TunnelSessionPrefs.protoKey)
        defaults.removeObject(forKey: TunnelSessionPrefs.endpointKey)
        defaults.removeObject(forKey: TunnelSessionPrefs.commonNameKey)
        defaults.removeObject(forKey: TunnelSessionPrefs.issuedFileNameKey)
        defaults.removeObject(forKey: TunnelSessionPrefs.manualProfileIdKey)
    }

    func dismissVpnProfileResetAlertOnly() {
        showVpnProfileResetAlert = false
    }

    func dismissVpnProfileResetSuggestion() {
        showVpnProfileResetSuggestion = false
        showVpnProfileResetAlert = false
    }

    private func startLiveTrafficPolling() {
        guard liveTrafficPollTimer == nil else { return }
        liveTrafficPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollLiveTraffic()
            }
        }
        if let liveTrafficPollTimer {
            RunLoop.main.add(liveTrafficPollTimer, forMode: .common)
        }
        Task { @MainActor in
            await pollLiveTraffic()
        }
    }

    private func stopLiveTrafficPolling() {
        liveTrafficPollTimer?.invalidate()
        liveTrafficPollTimer = nil
        lastLiveBytesIn = nil
        lastLiveBytesOut = nil
        lastLiveTrafficAt = nil
        liveTrafficSamples = []
        liveBytesIn = 0
        liveBytesOut = 0
        liveDownBytesPerSec = 0
        liveUpBytesPerSec = 0
    }

    private func pollLiveTraffic() async {
        guard isConnected || tunnelManager.status == .reasserting else { return }
        guard let snap = await tunnelManager.fetchLiveTraffic() else { return }
        let now = Date()
        if let lastIn = lastLiveBytesIn, let lastOut = lastLiveBytesOut, let lastAt = lastLiveTrafficAt {
            let dt = now.timeIntervalSince(lastAt)
            if dt > 0, snap.bytesIn >= lastIn, snap.bytesOut >= lastOut {
                liveDownBytesPerSec = Double(snap.bytesIn - lastIn) / dt
                liveUpBytesPerSec = Double(snap.bytesOut - lastOut) / dt
                liveTrafficSamples.append(
                    LiveTrafficSample(at: now, downBytesPerSec: liveDownBytesPerSec, upBytesPerSec: liveUpBytesPerSec)
                )
                if liveTrafficSamples.count > 60 {
                    liveTrafficSamples.removeFirst(liveTrafficSamples.count - 60)
                }
            }
        }
        lastLiveBytesIn = snap.bytesIn
        lastLiveBytesOut = snap.bytesOut
        lastLiveTrafficAt = now
        liveBytesIn = snap.bytesIn
        liveBytesOut = snap.bytesOut
    }

    private func appendLog(_ line: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        logText += "[\(ts)] \(line)\n"
        if logText.count > 40_000 {
            logText = String(logText.suffix(20_000))
        }
    }
}

struct TunnelSessionIdentityRow: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: String
    var usesMonospace: Bool = false
}

struct LiveTrafficSample: Identifiable, Equatable, Sendable {
    let at: Date
    let downBytesPerSec: Double
    let upBytesPerSec: Double
    var id: Date { at }
}
