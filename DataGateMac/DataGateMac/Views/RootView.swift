//
//  RootView.swift
//  DataGateMac
//
//  Checks token on launch: if authorized → Main, else → Login.
//

import SwiftUI

struct RootView: View {
    @StateObject private var authState = AuthStateStore()

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
        .task {
            await authState.restoreFromStorage()
        }
    }
}
