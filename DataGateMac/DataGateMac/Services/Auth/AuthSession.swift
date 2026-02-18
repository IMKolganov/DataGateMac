//
//  AuthSession.swift
//  DataGateMac
//
//  Loads/saves tokens, returns valid access token (checks expiration).
//

import Foundation

final class AuthSession {
    private let store: FileTokenStore
    private let validMargin: TimeInterval = 60 // consider valid if expires in > 60s

    init(store: FileTokenStore = FileTokenStore()) {
        self.store = store
    }

    /// Returns current token if still valid (or after refresh); nil if not authorized.
    func getValidAccessToken() async -> String? {
        guard let tokens = try? store.load() else { return nil }
        if isAccessValid(tokens) {
            return tokens.token
        }
        // TODO: refresh via API when needed
        return nil
    }

    func setFromLogin(_ response: GoogleLoginResponse) throws {
        try store.save(response.asAuthTokens)
    }

    func logout() throws {
        try store.clear()
    }

    private func isAccessValid(_ t: AuthTokensResponse) -> Bool {
        t.expiration > Date().addingTimeInterval(validMargin)
    }
}
