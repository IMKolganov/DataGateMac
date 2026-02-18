//
//  AccessPageView.swift
//  DataGateMac
//
//  Server list (table) — matches Windows Access page.
//

import SwiftUI

struct AccessPageView: View {
    @ObservedObject var authState: AuthStateStore
    @State private var servers: [OpenVpnServerWithStatusDto] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let api = OpenVpnServersApiClient.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Access")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    Task { await loadServers() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }

            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading servers…")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else if servers.isEmpty {
                Text("No servers available")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                serverTable
            }
        }
        .padding(24)
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await loadServers()
        }
        .refreshable {
            await loadServers()
        }
    }

    private var serverTable: some View {
        Table(servers, columns: {
            TableColumn("Server") { row in
                Text(row.openVpnServerResponses.openVpnServer.serverName)
            }
            TableColumn("Clients") { row in
                Text("\(row.countConnectedClients)")
                    .monospacedDigit()
            }
            TableColumn("In") { row in
                Text(formatBytes(row.totalBytesIn))
                    .monospacedDigit()
            }
            TableColumn("Out") { row in
                Text(formatBytes(row.totalBytesOut))
                    .monospacedDigit()
            }
            TableColumn("Online") { row in
                Image(systemName: (row.openVpnServerResponses.openVpnServer.isOnline ?? false) ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle((row.openVpnServerResponses.openVpnServer.isOnline ?? false) ? .green : .red)
            }
        })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func loadServers() async {
        guard let token = await authState.getValidAccessToken() else {
            errorMessage = "Not authorized"
            return
        }
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            servers = try await api.getAllWithStatus(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }
}
