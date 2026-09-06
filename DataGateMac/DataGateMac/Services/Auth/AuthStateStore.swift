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
private let userIdKey = "authUserId"
private let userAvatarUrlKey = "userAvatarUrl"
private let mainSidebarNavSelectionKey = "mainSidebarNavSelection"

@MainActor
final class AuthStateStore: ObservableObject {
    @Published private(set) var isAuthorized: Bool = false
    /// False until restoreFromStorage() has run (avoids flashing Login when we have a valid token).
    @Published private(set) var hasRestoredFromStorage: Bool = false
    @Published private(set) var displayName: String?
    @Published private(set) var email: String?
    /// HTTPS Google profile photo URL when the backend (or JWT) provided one.
    @Published private(set) var avatarUrl: String?
    /// Backend user id (for quota and other user-scoped APIs). Persisted across launches after login.
    @Published private(set) var userId: Int?

    private let session: AuthSession

    init(session: AuthSession = AuthSession()) {
        self.session = session
        displayName = UserDefaults.standard.string(forKey: userDisplayNameKey)
        email = UserDefaults.standard.string(forKey: userEmailKey)
        avatarUrl = ProfileImageURL.normalizedString(UserDefaults.standard.string(forKey: userAvatarUrlKey))
        let storedId = UserDefaults.standard.integer(forKey: userIdKey)
        userId = storedId > 0 ? storedId : nil
    }

    /// Call at app launch: load stored token; if valid, set authorized.
    func restoreFromStorage() async {
        let token = await session.getValidAccessToken()
        isAuthorized = token != nil
        hasRestoredFromStorage = true
        if isAuthorized {
            displayName = UserDefaults.standard.string(forKey: userDisplayNameKey)
            email = UserDefaults.standard.string(forKey: userEmailKey)
            avatarUrl = ProfileImageURL.normalizedString(UserDefaults.standard.string(forKey: userAvatarUrlKey))
            let storedId = UserDefaults.standard.integer(forKey: userIdKey)
            userId = storedId > 0 ? storedId : nil
            hydrateAvatarFromTokenIfNeeded(token)
        } else {
            displayName = nil
            email = nil
            avatarUrl = nil
            userId = nil
        }
    }

    /// Call after successful login (tokens already saved by login flow).
    func setAuthorized() {
        isAuthorized = true
    }

    /// Save tokens from login response and mark as authorized.
    func completeLogin(_ response: GoogleLoginResponse) {
        guard response.hasAccessToken else { return }
        try? session.setFromLogin(response)
        isAuthorized = true
        displayName = response.displayName.isEmpty ? nil : response.displayName
        email = response.email
        persistAvatarUrl(
            response.avatarUrl ?? (response.hasAccessToken ? JwtClaimReader.getAvatarUrl(fromJwt: response.token) : nil)
        )
        UserDefaults.standard.set(displayName, forKey: userDisplayNameKey)
        UserDefaults.standard.set(email, forKey: userEmailKey)
        if response.userId > 0 {
            userId = response.userId
            UserDefaults.standard.set(response.userId, forKey: userIdKey)
        } else {
            userId = nil
            UserDefaults.standard.removeObject(forKey: userIdKey)
        }
    }

    /// Call on logout: clear tokens and switch back to login.
    func clear() {
        try? session.logout()
        isAuthorized = false
        displayName = nil
        email = nil
        avatarUrl = nil
        userId = nil
        UserDefaults.standard.removeObject(forKey: userDisplayNameKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
        UserDefaults.standard.removeObject(forKey: userAvatarUrlKey)
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: mainSidebarNavSelectionKey)
    }

    /// Returns valid access token (refreshes if expired). Used by API clients.
    func getValidAccessToken() async -> String? {
        await session.getValidAccessToken()
    }

    /// User id for `/api/user-quota-plans/...` and similar; falls back to JWT claims when unset.
    func resolvedUserId(accessToken: String) -> Int? {
        if let id = userId, id > 0 { return id }
        return JwtClaimReader.getUserId(fromJwt: accessToken)
    }

    private func hydrateAvatarFromTokenIfNeeded(_ token: String?) {
        guard avatarUrl == nil, let token, !token.isEmpty else { return }
        persistAvatarUrl(JwtClaimReader.getAvatarUrl(fromJwt: token))
    }

    private func persistAvatarUrl(_ raw: String?) {
        let normalized = ProfileImageURL.normalizedString(raw)
        avatarUrl = normalized
        if let normalized {
            UserDefaults.standard.set(normalized, forKey: userAvatarUrlKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userAvatarUrlKey)
        }
    }
}
