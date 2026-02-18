//
//  AuthStateStore.swift
//  DataGateMac
//
//  Single source of truth: are we authorized? Used to show Login vs Main.
//

import Foundation
import Combine

@MainActor
final class AuthStateStore: ObservableObject {
    @Published private(set) var isAuthorized: Bool = false
    /// False until restoreFromStorage() has run (avoids flashing Login when we have a valid token).
    @Published private(set) var hasRestoredFromStorage: Bool = false

    private let session: AuthSession

    init(session: AuthSession = AuthSession()) {
        self.session = session
    }

    /// Call at app launch: load stored token; if valid, set authorized.
    func restoreFromStorage() async {
        let token = await session.getValidAccessToken()
        isAuthorized = token != nil
        hasRestoredFromStorage = true
    }

    /// Call after successful login (tokens already saved by login flow).
    func setAuthorized() {
        isAuthorized = true
    }

    /// Save tokens from login response and mark as authorized.
    func completeLogin(_ response: GoogleLoginResponse) {
        try? session.setFromLogin(response)
        isAuthorized = true
    }

    /// Call on logout: clear tokens and switch back to login.
    func clear() {
        try? session.logout()
        isAuthorized = false
    }

    /// Returns valid access token (refreshes if expired). Used by API clients.
    func getValidAccessToken() async -> String? {
        await session.getValidAccessToken()
    }
}
