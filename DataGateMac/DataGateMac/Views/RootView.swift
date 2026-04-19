//
//  RootView.swift
//  DataGateMac
//
//  Checks token on launch: if authorized → Main, else → Login.
//

import SwiftUI

struct RootView: View {
    @StateObject private var authState = AuthStateStore()
    @AppStorage(AppAppearanceStorage.key) private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage(AppLanguageStorage.key) private var appPreferredLanguage: String = AppStoredLocale.SYSTEM.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    private var localeForEnvironment: Locale {
        let key = AppStoredLocale.normalizeStorageValue(appPreferredLanguage)
        guard let loc = AppStoredLocale(rawValue: key), loc != .SYSTEM,
              let tag = loc.bcp47Identifier else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: tag)
    }

    var body: some View {
        Group {
            if !authState.hasRestoredFromStorage {
                ProgressView(L10n.tr("auth_checking", "Checking authorization…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if authState.isAuthorized {
                MainView(authState: authState)
            } else {
                LoginView(authState: authState)
            }
        }
        .environment(\.locale, localeForEnvironment)
        .preferredColorScheme(appearance.preferredColorScheme)
        .task {
            await authState.restoreFromStorage()
        }
    }
}
