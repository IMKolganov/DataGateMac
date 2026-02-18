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

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        Group {
            if !authState.hasRestoredFromStorage {
                ProgressView("Checking authorization…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if authState.isAuthorized {
                MainView(authState: authState)
            } else {
                LoginView(authState: authState)
            }
        }
        .preferredColorScheme(appearance.preferredColorScheme)
        .task {
            await authState.restoreFromStorage()
        }
    }
}
