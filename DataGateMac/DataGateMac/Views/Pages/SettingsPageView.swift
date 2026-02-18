//
//  SettingsPageView.swift
//  DataGateMac
//

import SwiftUI

struct SettingsPageView: View {
    @ObservedObject var authState: AuthStateStore
    @State private var showAbout = false
    @AppStorage(AppAppearanceStorage.key) private var appearanceRaw: String = AppAppearance.system.rawValue

    private var appearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Appearance")
                        .font(.headline)
                    Text("Choose the application theme.")
                        .foregroundStyle(.secondary)
                    Picker("Theme", selection: appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Divider()

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
                    showAbout = true
                } label: {
                    Label("About", systemImage: "info.circle")
                }
                .buttonStyle(.bordered)
                .sheet(isPresented: $showAbout) {
                    AboutSheet()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

private struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text("DataGate Mac")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Current version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .foregroundStyle(.secondary)
                    Text("Secure VPN client for the DataGate platform.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 10) {
                Link(destination: URL(string: "https://datagateapp.com")!) {
                    Label("https://datagateapp.com", systemImage: "globe")
                }
                Link(destination: URL(string: "https://github.com/IMKolganov/DataGateMac")!) {
                    Label("GitHub", systemImage: "link")
                }
            }
            .padding(.bottom, 16)

            Divider()
                .padding(.bottom, 12)

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 300)
    }
}
