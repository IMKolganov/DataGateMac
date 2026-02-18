//
//  AuthStateStore.swift
//  DataGateMac
//
//  Single source of truth: are we authorized? Used to show Login vs Main.
//

import Foundation
import Combine

private let userDisplayNameKey = "userDisplayName"
private let userEmailKey = "userEmail"

@MainActor
final class AuthStateStore: ObservableObject {
    @Published private(set) var isAuthorized: Bool = false
    /// False until restoreFromStorage() has run (avoids flashing Login when we have a valid token).
    @Published private(set) var hasRestoredFromStorage: Bool = false
    @Published private(set) var displayName: String?
    @Published private(set) var email: String?

    private let session: AuthSession

    init(session: AuthSession = AuthSession()) {
        self.session = session
        displayName = UserDefaults.standard.string(forKey: userDisplayNameKey)
        email = UserDefaults.standard.string(forKey: userEmailKey)
    }

    /// Call at app launch: load stored token; if valid, set authorized.
    func restoreFromStorage() async {
        let token = await session.getValidAccessToken()
        isAuthorized = token != nil
        hasRestoredFromStorage = true
        if isAuthorized {
            displayName = UserDefaults.standard.string(forKey: userDisplayNameKey)
            email = UserDefaults.standard.string(forKey: userEmailKey)
        } else {
            displayName = nil
            email = nil
        }
    }

    /// Call after successful login (tokens already saved by login flow).
    func setAuthorized() {
        isAuthorized = true
    }

    /// Save tokens from login response and mark as authorized.
    func completeLogin(_ response: GoogleLoginResponse) {
        try? session.setFromLogin(response)
        isAuthorized = true
        displayName = response.displayName.isEmpty ? nil : response.displayName
        email = response.email
        UserDefaults.standard.set(displayName, forKey: userDisplayNameKey)
        UserDefaults.standard.set(email, forKey: userEmailKey)
    }

    /// Call on logout: clear tokens and switch back to login.
    func clear() {
        try? session.logout()
        isAuthorized = false
        displayName = nil
        email = nil
        UserDefaults.standard.removeObject(forKey: userDisplayNameKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
    }

    /// Returns valid access token (refreshes if expired). Used by API clients.
    func getValidAccessToken() async -> String? {
        await session.getValidAccessToken()
    }
}
