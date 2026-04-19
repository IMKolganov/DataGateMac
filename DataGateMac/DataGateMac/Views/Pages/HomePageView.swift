//
//  HomePageView.swift
//  DataGateMac
//

import SwiftUI

struct HomePageView: View {
    @ObservedObject var authState: AuthStateStore
    @StateObject private var vm: VpnViewModel

    init(authState: AuthStateStore) {
        self.authState = authState
        _vm = StateObject(wrappedValue: VpnViewModel(authState: authState))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Welcome to DataGate OpenVPN 3")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Connection status")
                        .fontWeight(.semibold)
                    Text(vm.statusText)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button(vm.isConnected ? "Disconnect" : "Connect") {
                            vm.toggle()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isBusy)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if vm.statusText.contains("code 14") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("If tunnel failed with code 14:")
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Button("Remove VPN profile and recreate") {
                            Task { await vm.resetVpnProfile() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.isBusy)
                        Text("Use after copying the app to /Applications: clears the saved DataGate VPN entry so Connect registers the tunnel again.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Button("Copy command to capture system log") {
                            let cmd = "/usr/bin/log show --last 2m 2>&1 | grep -iE \"networkextension|neagent\" | grep -v \"DataGateMac:\" > ~/Desktop/DataGateMac_NE_log.txt && open ~/Desktop/DataGateMac_NE_log.txt"
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cmd, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        Text("Run in Terminal right after reproducing; then check the opened file for the real error.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Engine logs")
                        .fontWeight(.semibold)
                    TextEditor(text: Binding(
                        get: {
                            vm.extensionLogText.isEmpty
                                ? vm.logText
                                : vm.logText + "\n--- Extension ---\n" + vm.extensionLogText
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
            .padding(24)
        }
        .frame(minWidth: 400, minHeight: 400)
        .task { await vm.ensureConfigurationLoaded() }
    }
}

struct HomePageView_Previews: PreviewProvider {
    static var previews: some View {
        HomePageView(authState: AuthStateStore())
    }
}
