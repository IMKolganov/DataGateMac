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

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.tr("settings_title", "Settings"))
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.tr("settings_language", "Language"))
                        .font(.headline)
                    Text(L10n.tr("settings_language_hint", "Choose the interface language. \"Follow system language\" uses macOS settings."))
                        .foregroundStyle(.secondary)
                    HStack {
                        AppLanguagePicker()
                        Spacer(minLength: 0)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.tr("settings_appearance", "Appearance"))
                        .font(.headline)
                    Text(L10n.tr("settings_appearance_hint", "Choose the application theme."))
                        .foregroundStyle(.secondary)
                    Picker(L10n.tr("settings_theme", "Theme"), selection: appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.tr("settings_account", "Account"))
                        .font(.headline)
                    Text(L10n.tr("settings_account_hint", "Sign out from the application."))
                        .foregroundStyle(.secondary)
                    Button {
                        authState.clear()
                    } label: {
                        Label(L10n.tr("settings_logout", "Logout"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("settings_application", "Application"))
                        .font(.headline)
                    Text(String(format: L10n.tr("settings_version_fmt", "Current version: %@"), locale: L10n.activeLocaleForFormatting(), versionString))
                        .foregroundStyle(.secondary)
                }

                Divider()

                Button {
                    showAbout = true
                } label: {
                    Label(L10n.tr("settings_about", "About"), systemImage: "info.circle")
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

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("about_title", "DataGate Mac"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(String(format: L10n.tr("about_version_fmt", "Current version: %@"), locale: L10n.activeLocaleForFormatting(), versionString))
                        .foregroundStyle(.secondary)
                    Text(L10n.tr("about_description", "Secure VPN client for the DataGate platform."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 10) {
                Link(destination: URL(string: "https://datagateapp.com")!) {
                    Label(L10n.tr("about_link_site", "https://datagateapp.com"), systemImage: "globe")
                }
                Link(destination: URL(string: "https://github.com/IMKolganov/DataGateMac")!) {
                    Label(L10n.tr("about_link_github", "GitHub"), systemImage: "link")
                }
            }
            .padding(.bottom, 16)

            Divider()
                .padding(.bottom, 12)

            HStack {
                Spacer()
                Button(L10n.tr("about_close", "Close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 300)
    }
}
