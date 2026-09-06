//
//  AuthSession.swift
//  DataGateMac
//
//  Loads/saves tokens, returns valid access token (refresh when expired).
//

import Foundation

final class AuthSession {
    private let store: FileTokenStore
    private let validMargin: TimeInterval = 60
    private let refreshTimeout: TimeInterval = 15
    private var current: AuthTokensResponse?
    private let lock = NSLock()
    private var refreshTask: Task<AuthTokensResponse?, Never>?

    init(store: FileTokenStore = FileTokenStore()) {
        self.store = store
        if let tokens = try? store.load() {
            current = tokens
        }
    }

    /// Returns current token if valid or after refresh; nil if not authorized.
    func getValidAccessToken() async -> String? {
        lock.lock()
        var tokens = current ?? (try? store.load())
        lock.unlock()

        if tokens == nil {
            tokens = try? store.load()
            if let t = tokens { setCurrent(t) }
        }
        guard let t = tokens else { return nil }

        if isAccessValid(t) {
            return t.token
        }
        guard let refreshed = await refresh() else { return nil }
        return refreshed.token
    }

    func setFromLogin(_ response: GoogleLoginResponse) throws {
        guard response.hasAccessToken else { return }
        let tokens = response.asAuthTokens
        try store.save(tokens)
        setCurrent(tokens)
    }

    func logout() throws {
        try store.clear()
        setCurrent(nil)
    }

    private func setCurrent(_ tokens: AuthTokensResponse?) {
        lock.lock()
        current = tokens
        lock.unlock()
    }

    private func clearInvalidSession() {
        try? store.clear()
        setCurrent(nil)
    }

    private func isAccessValid(_ t: AuthTokensResponse) -> Bool {
        t.expiration > Date().addingTimeInterval(validMargin)
    }

    private func refresh() async -> AuthTokensResponse? {
        lock.lock()
        if let task = refreshTask {
            lock.unlock()
            return await task.value
        }
        let tokens = current ?? (try? store.load())
        guard let t = tokens, t.refreshToken != nil else {
            lock.unlock()
            return nil
        }
        let task = Task<AuthTokensResponse?, Never> {
            await doRefresh()
        }
        refreshTask = task
        lock.unlock()
        let result = await task.value
        lock.lock()
        refreshTask = nil
        lock.unlock()
        return result
    }

    private func doRefresh() async -> AuthTokensResponse? {
        lock.lock()
        let tokens = current ?? (try? store.load())
        lock.unlock()
        guard let t = tokens, let refreshToken = t.refreshToken else { return nil }
        if let refreshExp = t.refreshExpiration, refreshExp <= Date().addingTimeInterval(5) { return nil }

        guard let config = try? AppConfig.load() else { return nil }
        let request = RefreshRequest(
            refreshToken: refreshToken,
            deviceId: nil,
            userAgent: "DataGateMac/1.0"
        )
        let url = URL(string: "\(config.apiBaseUrl)/api/auth/refresh")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = (try? JSONEncoder().encode(request))
        req.timeoutInterval = refreshTimeout

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else {
            clearInvalidSession()
            return nil
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            clearInvalidSession()
            return nil
        }
        guard (200...299).contains(http.statusCode) else {
            clearInvalidSession()
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let apiResp = try? decoder.decode(ApiResponse<AuthTokensResponse>.self, from: data),
              apiResp.success, let newTokens = apiResp.data else {
            clearInvalidSession()
            return nil
        }

        try? store.save(newTokens)
        setCurrent(newTokens)
        return newTokens
    }
}
