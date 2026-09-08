//
//  SettingsPageView.swift
//  DataGateMac
//

import SwiftUI

struct SettingsPageView: View {
    @ObservedObject var authState: AuthStateStore
    @StateObject private var updateVM = AppUpdateViewModel()
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
                IconSectionTitle(title: L10n.tr("settings_title", "Settings"), systemImage: "gearshape.fill", style: .page)

                VStack(alignment: .leading, spacing: 16) {
                    IconSectionTitle(title: L10n.tr("settings_language", "Language"), systemImage: "globe")
                    Text(L10n.tr("settings_language_hint", "Choose the interface language. \"Follow system language\" uses macOS settings."))
                        .foregroundStyle(.secondary)
                    HStack {
                        AppLanguagePicker()
                        Spacer(minLength: 0)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    IconSectionTitle(title: L10n.tr("settings_appearance", "Appearance"), systemImage: "circle.lefthalf.filled")
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
                    IconSectionTitle(title: L10n.tr("settings_account", "Account"), systemImage: "person.crop.circle")
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
                    IconSectionTitle(title: L10n.tr("settings_application", "Application"), systemImage: "app.badge")
                    Text(String(format: L10n.tr("settings_version_fmt", "Current version: %@"), locale: L10n.activeLocaleForFormatting(), versionString))
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    IconSectionTitle(title: L10n.tr("settings_updates_title", "Updates"), systemImage: "arrow.down.app")
                    Text(L10n.tr("settings_updates_hint", "Check GitHub releases for a newer version of DataGate Mac."))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(
                            format: L10n.tr("settings_updates_current_fmt", "Current version: %@"),
                            locale: L10n.activeLocaleForFormatting(),
                            updateVM.currentVersion
                        ))
                        .foregroundStyle(.secondary)

                        Text(String(
                            format: L10n.tr("settings_updates_latest_fmt", "Latest available: %@"),
                            locale: L10n.activeLocaleForFormatting(),
                            updateVM.availableVersionText
                        ))
                        .foregroundStyle(.secondary)

                        if !updateVM.statusText.isEmpty {
                            Text(updateVM.statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await updateVM.checkForUpdates() }
                        } label: {
                            if updateVM.isChecking {
                                Label(L10n.tr("settings_updates_checking", "Checking GitHub releases…"), systemImage: "arrow.triangle.2.circlepath")
                            } else {
                                Label(L10n.tr("settings_updates_check_button", "Check for updates"), systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(updateVM.isChecking)

                        if let releaseURL = updateVM.releaseURL {
                            Link(destination: releaseURL) {
                                Label(L10n.tr("settings_updates_open_release", "Open latest release"), systemImage: "arrow.up.right.square")
                            }
                        } else {
                            Link(destination: updateVM.releasesPageURL) {
                                Label(L10n.tr("settings_updates_open_releases", "Open releases page"), systemImage: "arrow.up.right.square")
                            }
                        }
                    }
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
        .task { await updateVM.checkForUpdatesIfNeeded() }
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
