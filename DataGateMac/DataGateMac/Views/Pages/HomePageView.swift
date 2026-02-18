//
//  HomePageView.swift
//  DataGateMac
//

import SwiftUI

struct HomePageView: View {
    @StateObject private var vm = VpnViewModel()

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

                VStack(alignment: .leading, spacing: 12) {
                    Text("Engine logs")
                        .fontWeight(.semibold)
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(vm.logText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 260)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
        }
        .frame(minWidth: 400, minHeight: 400)
    }
}
