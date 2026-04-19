//
//  ContentView.swift
//  DataGateMac
//
//  Created by Ivan Kolganov on 01/02/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var vm = VpnViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Text("DataGateMac")
                .font(.title2)
                .bold()

            Text(vm.statusText)
                .font(.callout)
                .foregroundStyle(vm.isConnected ? .green : .secondary)

            Button {
                vm.toggle()
            } label: {
                Text(vm.isConnected ? "Disconnect" : "Connect")
                    .frame(width: 180)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isBusy)

            ScrollView {
                Text(
                    vm.extensionLogText.isEmpty
                        ? vm.logText
                        : vm.logText + "\n--- Extension ---\n" + vm.extensionLogText
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
