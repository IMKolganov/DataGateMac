//
//  AppUpdateViewModel.swift
//  DataGateMac
//
//  State for Settings update checks.
//

import Combine
import Foundation

@MainActor
final class AppUpdateViewModel: ObservableObject {
    @Published private(set) var currentVersion: String
    @Published private(set) var availableVersionText: String = L10n.tr("settings_updates_unknown", "Unknown")
    @Published private(set) var statusText: String = ""
    @Published private(set) var isChecking = false
    @Published private(set) var releaseURL: URL?
    @Published private(set) var releasesPageURL: URL

    private let service: AppUpdateService
    private var hasCheckedOnce = false

    init(service: AppUpdateService = AppUpdateService(), bundle: Bundle = .main) {
        self.service = service
        currentVersion = AppUpdateService.currentAppVersion(bundle: bundle)
        releasesPageURL = service.releasesPageURL
    }

    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        statusText = L10n.tr("settings_updates_checking", "Checking GitHub releases…")
        defer { isChecking = false }

        let result = await service.checkForUpdates(currentVersion: currentVersion)
        apply(result)
        hasCheckedOnce = true
    }

    func checkForUpdatesIfNeeded() async {
        guard !hasCheckedOnce else { return }
        await checkForUpdates()
    }

    private func apply(_ result: AppUpdateCheckResult) {
        switch result {
        case .updateAvailable(let currentVersion, let latest):
            self.currentVersion = currentVersion
            availableVersionText = latest.version
            statusText = String(
                format: L10n.tr("settings_updates_available_fmt", "Update available: %@ → %@"),
                locale: L10n.activeLocaleForFormatting(),
                currentVersion,
                latest.version
            )
            releaseURL = latest.htmlURL
        case .upToDate(let currentVersion, let latest):
            self.currentVersion = currentVersion
            availableVersionText = latest?.version ?? currentVersion
            statusText = latest == nil
                ? L10n.tr("settings_updates_uptodate", "You are using the latest version.")
                : String(
                    format: L10n.tr("settings_updates_uptodate_fmt", "You are using the latest version: %@"),
                    locale: L10n.activeLocaleForFormatting(),
                    latest!.version
                )
            releaseURL = latest?.htmlURL
        case .noReleases(let currentVersion, let releasesPageURL):
            self.currentVersion = currentVersion
            availableVersionText = L10n.tr("settings_updates_none", "No releases yet")
            statusText = L10n.tr("settings_updates_none_detail", "No GitHub releases have been published for this repository yet.")
            self.releasesPageURL = releasesPageURL
            releaseURL = nil
        case .failed(let currentVersion, let message):
            self.currentVersion = currentVersion
            availableVersionText = L10n.tr("settings_updates_unknown", "Unknown")
            statusText = String(
                format: L10n.tr("settings_updates_failed_fmt", "Could not check for updates: %@"),
                locale: L10n.activeLocaleForFormatting(),
                message
            )
            releaseURL = nil
        }
    }
}
