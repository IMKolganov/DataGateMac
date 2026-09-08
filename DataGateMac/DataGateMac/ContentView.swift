//
//  ContentView.swift
//  DataGateMac
//
//  Created by Ivan Kolganov on 01/02/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var vm = VpnViewModel()

    private var extensionSeparator: String {
        L10n.tr("vpn_extension_log_separator", "--- Extension ---")
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.tr("content_title", "DataGateMac"))
                .font(.title2)
                .bold()

            Text(vm.statusText)
                .font(.callout)
                .foregroundStyle(vm.isConnected ? .green : .secondary)

            TunnelSessionIdentityList(rows: vm.connectionIdentityRows)

            Button {
                vm.toggle()
            } label: {
                Text(vm.isConnected ? L10n.tr("home_disconnect", "Disconnect") : L10n.tr("home_connect", "Connect"))
                    .frame(width: 180)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isBusy)

            ScrollView {
                Text(
                    vm.extensionLogText.isEmpty
                        ? vm.logText
                        : vm.logText + "\n" + extensionSeparator + "\n" + vm.extensionLogText
                )
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(height: 260)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
        .padding()
        .task { await vm.ensureConfigurationLoaded() }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
