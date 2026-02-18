//
//  SettingsPageView.swift
//  DataGateMac
//

import SwiftUI

struct SettingsPageView: View {
    @ObservedObject var authState: AuthStateStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Account")
                        .font(.headline)
                    Text("Sign out from the application.")
                        .foregroundStyle(.secondary)
                    Button {
                        authState.clear()
                    } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Application")
                        .font(.headline)
                    Text("Current version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .foregroundStyle(.secondary)
                }

                Divider()

                Button {
                    if let url = URL(string: "https://github.com/IMKolganov/DataGateMac") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("About", systemImage: "info.circle")
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
