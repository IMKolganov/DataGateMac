//
//  HomePageView.swift
//  DataGateMac
//

import AppKit
import SwiftUI

struct HomePageView: View {
    @ObservedObject var authState: AuthStateStore
    @StateObject private var vm: VpnViewModel

    init(authState: AuthStateStore) {
        self.authState = authState
        _vm = StateObject(wrappedValue: VpnViewModel(authState: authState))
    }

    private var extensionSeparator: String {
        L10n.tr("vpn_extension_log_separator", "--- Extension ---")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.tr("home_welcome", "Welcome to DataGate"))
                    .font(.system(size: 20, weight: .semibold))

                homeCard {
                    Text(L10n.tr("home_server_section", "VPN server"))
                        .fontWeight(.semibold)
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

                    HStack(spacing: 12) {
                        Button(L10n.tr("home_server_refresh", "Refresh list")) {
                            Task { await vm.refreshServerList() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!authState.isAuthorized || vm.isRefreshingServerList)
                        if vm.isRefreshingServerList {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.top, 2)

                    if !vm.serverListBanner.isEmpty {
                        Text(vm.serverListBanner)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                homeCard {
                    Text(L10n.tr("home_conn_status", "Connection status"))
                        .fontWeight(.semibold)
                    Text(vm.statusText)
                        .foregroundStyle(.secondary)
                    if !vm.activeTunnelSummary.isEmpty {
                        Text(vm.activeTunnelSummary)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                    HStack(spacing: 12) {
                        Button(L10n.tr("home_connect", "Connect")) {
                            vm.connect()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(minWidth: 140)
                        .disabled(!vm.canTapConnect)

                        Button(L10n.tr("home_disconnect", "Disconnect")) {
                            vm.disconnect()
                        }
                        .buttonStyle(.bordered)
                        .frame(minWidth: 140)
                        .disabled(!vm.canTapDisconnect)
                    }
                    .padding(.top, 4)
                }

                if vm.statusText.contains("code 14") || vm.showVpnProfileResetSuggestion {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(vm.showVpnProfileResetSuggestion
                            ? L10n.tr("home_vpn_warn_blocked", "macOS may be blocking VPN profile updates (permission denied or error 5).")
                            : L10n.tr("home_vpn_warn_code14", "If tunnel failed with code 14:"))
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Button(L10n.tr("home_remove_vpn_profile", "Remove VPN profile and recreate")) {
                            Task { await vm.resetVpnProfile() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.isBusy)
                        Text(vm.showVpnProfileResetSuggestion
                            ? L10n.tr("home_vpn_hint_blocked", "Clears the saved DataGate VPN entry, then try Connect again and allow the system prompt. Also remove DataGate in System Settings → VPN if it still appears.")
                            : L10n.tr("home_vpn_hint_code14", "Use after copying the app to /Applications: clears the saved DataGate VPN entry so Connect registers the tunnel again."))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Button(L10n.tr("home_copy_log", "Copy command to capture system log")) {
                            let cmd = "/usr/bin/log show --last 2m 2>&1 | grep -iE \"networkextension|neagent\" | grep -v \"DataGateMac:\" > ~/Desktop/DataGateMac_NE_log.txt && open ~/Desktop/DataGateMac_NE_log.txt"
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cmd, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        Text(L10n.tr("home_log_cmd_hint", "Run in Terminal right after reproducing; then check the opened file for the real error."))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                homeCard {
                    Text(L10n.tr("home_engine_logs", "Engine logs"))
                        .fontWeight(.semibold)
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

    private func homeServerRowLabel(_ row: HomeVpnServerRow) -> String {
        let load = L10n.trFormat("home_server_clients_fmt", "%d clients", row.clientCount)
        var base = "\(row.displayName) · \(load)"
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

struct HomePageView_Previews: PreviewProvider {
    static var previews: some View {
        HomePageView(authState: AuthStateStore())
    }
}
