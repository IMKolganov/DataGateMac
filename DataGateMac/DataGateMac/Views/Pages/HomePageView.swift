//
//  HomePageView.swift
//  DataGateMac
//

import AppKit
import SwiftUI

struct HomePageView: View {
    @ObservedObject var authState: AuthStateStore
    @ObservedObject var vm: VpnViewModel
    @AppStorage("homeShowEngineLogs") private var showEngineLogs = false

    private var extensionSeparator: String {
        L10n.tr("vpn_extension_log_separator", "--- Extension ---")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                IconSectionTitle(
                    title: L10n.tr("home_welcome", "Welcome to DataGate"),
                    systemImage: "shield.checkered",
                    style: .page
                )

                homeCard {
                    HStack(alignment: .center, spacing: 12) {
                        IconSectionTitle(
                            title: L10n.tr("home_server_section", "VPN server"),
                            systemImage: "globe"
                        )
                        Spacer(minLength: 8)
                        Button {
                            Task { await vm.refreshServerList() }
                        } label: {
                            Label(L10n.tr("home_server_refresh", "Refresh list"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!authState.isAuthorized || vm.isRefreshingServerList)
                        if vm.isRefreshingServerList {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    Text(L10n.tr("home_server_section_hint", "Choose a specific location or let the app pick the best available server (same idea as DataGate on Windows and Linux)."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { vm.serverPickAutomatic },
                        set: { vm.updateServerPickAutomatic($0) }
                    )) {
                        Text(L10n.tr("home_server_mode_auto", "Best available")).tag(true)
                        Text(L10n.tr("home_server_mode_manual", "Choose server…")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(!authState.isAuthorized)

                    if !vm.serverPickAutomatic {
                        if vm.vpnServerRows.isEmpty {
                            Text(L10n.tr("home_server_manual_need_list", "Load the server list with Refresh, then pick a server."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker(L10n.tr("home_server_pick_label", "Server"), selection: Binding(
                                get: { vm.manualServerId },
                                set: { vm.updateManualServerId($0) }
                            )) {
                                ForEach(vm.vpnServerRows) { row in
                                    Text(homeServerRowLabel(row)).tag(row.id)
                                }
                            }
                            .disabled(!authState.isAuthorized)
                        }
                    }

                    if !vm.serverListBanner.isEmpty {
                        Label(vm.serverListBanner, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                homeCard {
                    IconSectionTitle(
                        title: L10n.tr("home_conn_status", "Connection status"),
                        systemImage: statusIcon
                    )
                    Text(vm.statusText)
                        .foregroundStyle(vm.isConnected ? Color.green : Color.secondary)
                    TunnelSessionIdentityList(rows: vm.connectionIdentityRows)
                    if vm.connectedManualProfileId != nil {
                        Label(
                            L10n.tr("home_connected_local_profile", "Connected with a local profile from Profiles. Connect here switches to a DataGate server."),
                            systemImage: "internaldrive"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Button {
                            vm.connect()
                        } label: {
                            Label(L10n.tr("home_connect", "Connect"), systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(minWidth: 140)
                        .disabled(!vm.canTapConnect)

                        Button {
                            vm.disconnect()
                        } label: {
                            Label(L10n.tr("home_disconnect", "Disconnect"), systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .frame(minWidth: 140)
                        .disabled(!vm.canTapDisconnect)
                    }
                    .padding(.top, 4)
                }

                if vm.statusText.contains("code 14") || vm.showVpnProfileResetSuggestion {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            vm.showVpnProfileResetSuggestion
                                ? L10n.tr("home_vpn_warn_blocked", "macOS may be blocking VPN profile updates (permission denied or error 5).")
                                : L10n.tr("home_vpn_warn_code14", "If tunnel failed with code 14:"),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        Button {
                            Task { await vm.resetVpnProfile() }
                        } label: {
                            Label(L10n.tr("home_remove_vpn_profile", "Remove VPN profile and recreate"), systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.isBusy)
                        Text(vm.showVpnProfileResetSuggestion
                            ? L10n.tr("home_vpn_hint_blocked", "Clears the saved DataGate VPN entry, then try Connect again and allow the system prompt. Also remove DataGate in System Settings → VPN if it still appears.")
                            : L10n.tr("home_vpn_hint_code14", "Use after copying the app to /Applications: clears the saved DataGate VPN entry so Connect registers the tunnel again."))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Button {
                            let cmd = "/usr/bin/log show --last 2m 2>&1 | grep -iE \"networkextension|neagent\" | grep -v \"DataGateMac:\" > ~/Desktop/DataGateMac_NE_log.txt && open ~/Desktop/DataGateMac_NE_log.txt"
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cmd, forType: .string)
                        } label: {
                            Label(L10n.tr("home_copy_log", "Copy command to capture system log"), systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        Text(L10n.tr("home_log_cmd_hint", "Run in Terminal right after reproducing; then check the opened file for the real error."))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if vm.isConnected {
                    homeCard {
                        LiveTrafficChart(
                            samples: vm.liveTrafficSamples,
                            bytesIn: vm.liveBytesIn,
                            bytesOut: vm.liveBytesOut,
                            downBytesPerSec: vm.liveDownBytesPerSec,
                            upBytesPerSec: vm.liveUpBytesPerSec
                        )
                    }
                }

                homeCard {
                    HStack(alignment: .firstTextBaseline) {
                        IconSectionTitle(
                            title: L10n.tr("home_engine_logs", "Engine logs"),
                            systemImage: "terminal"
                        )
                        Spacer()
                    }
                    Toggle(isOn: $showEngineLogs) {
                        Label(L10n.tr("home_show_engine_logs", "Show engine logs"), systemImage: "eye")
                    }
                    .toggleStyle(.checkbox)
                    if showEngineLogs {
                        TextEditor(text: Binding(
                            get: {
                                vm.extensionLogText.isEmpty
                                    ? vm.logText
                                    : vm.logText + "\n" + extensionSeparator + "\n" + vm.extensionLogText
                            },
                            set: { _ in }
                        ))
                        .font(.system(.caption, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(height: 260)
                        .padding(8)
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 400, minHeight: 400)
        .task { await vm.ensureConfigurationLoaded() }
        .alert(L10n.tr("home_alert_reset_title", "Reset VPN profile?"), isPresented: $vm.showVpnProfileResetAlert) {
            Button(L10n.tr("home_alert_remove", "Remove saved profile")) {
                Task { await vm.resetVpnProfile() }
            }
            Button(L10n.tr("home_alert_not_now", "Not now"), role: .cancel) {
                vm.dismissVpnProfileResetAlertOnly()
            }
        } message: {
            Text(L10n.tr("home_alert_reset_msg", "macOS blocked updating the VPN configuration (often error 5 or permission denied). Removing the in-app DataGate profile and trying Connect again usually fixes it. You can also use System Settings → VPN."))
        }
    }

    private var statusIcon: String {
        if vm.isConnected { return "checkmark.shield.fill" }
        if vm.statusText.lowercased().contains("connect") && !vm.statusText.lowercased().contains("disconnect") {
            return "arrow.triangle.2.circlepath"
        }
        return "shield"
    }

    private func homeServerRowLabel(_ row: HomeVpnServerRow) -> String {
        let load = L10n.trFormat("home_server_clients_fmt", "%d clients", row.clientCount)
        var base = "\(row.displayName) · \(load)"
        if row.isXray {
            base += L10n.tr("home_server_xray_suffix", " · Xray")
        } else if row.usesWss {
            base += L10n.tr("home_server_wss_suffix", " · WSS")
        } else {
            base += L10n.tr("home_server_openvpn_suffix", " · OpenVPN")
        }
        if let proto = row.protocolLabel {
            base += " · \(proto)"
        }
        if !row.isOnline {
            base += L10n.tr("home_server_offline_suffix", " (offline)")
        }
        return base
    }

    private func homeCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

struct HomePageView_Previews: PreviewProvider {
    static var previews: some View {
        HomePageView(authState: AuthStateStore(), vm: VpnViewModel())
    }
}
