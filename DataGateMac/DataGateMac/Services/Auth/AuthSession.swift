//
//  AuthSession.swift
//  DataGateMac
//
//  Loads/saves tokens, returns valid access token (refresh when expired).
//

import Foundation
import os

extension Notification.Name {
    static let authSessionRejected = Notification.Name("imkolganov.DataGateMac.authSessionRejected")
}

final class AuthSession {
    private let log = Logger(subsystem: "imkolganov.DataGateMac", category: "AuthSession")
    private let store: FileTokenStore
    private let validMargin: TimeInterval = 60
    private let refreshTimeout: TimeInterval = 30
    private var current: AuthTokensResponse?
    private let lock = NSLock()
    private var refreshTask: Task<AuthTokensResponse?, Never>?
    private var lastFailure: String?

    init(store: FileTokenStore = FileTokenStore()) {
        self.store = store
        if let tokens = try? store.load() {
            current = tokens
        }
    }

    /// Last refresh/token failure, for Connect logs. Cleared on the next successful token read.
    var lastFailureDescription: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastFailure
    }

    /// Returns current token if valid or after refresh; nil if not authorized.
    func getValidAccessToken() async -> String? {
        lock.lock()
        lastFailure = nil
        var tokens = current ?? (try? store.load())
        lock.unlock()

        if tokens == nil {
            tokens = try? store.load()
            if let t = tokens { setCurrent(t) }
        }
        guard let t = tokens else {
            setFailure("no stored tokens")
            return nil
        }

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
        setFailure(nil)
    }

    func logout() throws {
        try store.clear()
        setCurrent(nil)
        setFailure(nil)
    }

    private func setCurrent(_ tokens: AuthTokensResponse?) {
        lock.lock()
        current = tokens
        lock.unlock()
    }

    private func setFailure(_ message: String?) {
        lock.lock()
        lastFailure = message
        lock.unlock()
    }

    private func clearInvalidSession() {
        try? store.clear()
        setCurrent(nil)
        NotificationCenter.default.post(name: .authSessionRejected, object: nil)
    }

    private func isAccessValid(_ t: AuthTokensResponse) -> Bool {
        let deadline = Date().addingTimeInterval(validMargin)
        if t.expiration > deadline {
            return true
        }
        if let jwtExp = JwtClaimReader.expiration(fromJwt: t.token), jwtExp > deadline {
            return true
        }
        return false
    }

    private func isRefreshExpired(_ t: AuthTokensResponse) -> Bool {
        guard let refreshExp = t.refreshExpiration else { return false }
        return refreshExp <= Date().addingTimeInterval(5)
    }

    private func refresh() async -> AuthTokensResponse? {
        lock.lock()
        if let task = refreshTask {
            lock.unlock()
            return await task.value
        }
        let tokens = current ?? (try? store.load())
        guard let t = tokens, let refreshToken = t.refreshToken, !refreshToken.isEmpty else {
            lock.unlock()
            setFailure("no refresh token")
            log.error("Refresh skipped: no refresh token in store")
            return nil
        }
        if isRefreshExpired(t) {
            lock.unlock()
            setFailure("refresh token expired")
            log.error("Refresh skipped: refreshExpiration is in the past")
            clearInvalidSession()
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
        guard let previous = tokens, let refreshToken = previous.refreshToken, !refreshToken.isEmpty else {
            setFailure("no refresh token")
            return nil
        }

        guard let config = try? AppConfig.load() else {
            setFailure("app config missing")
            log.error("Refresh failed: AppConfig.load() returned nil")
            return nil
        }
        let request = RefreshRequest(
            refreshToken: refreshToken,
            deviceId: InstallationIdService().getOrCreate(),
            userAgent: "DataGateMac/1.0"
        )
        let url = URL(string: "\(config.apiBaseUrl)/api/auth/refresh")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try JSONEncoder().encode(request)
        } catch {
            setFailure("refresh request encode failed")
            log.error("Refresh encode failed: \(error.localizedDescription)")
            return nil
        }
        req.timeoutInterval = refreshTimeout

        let data: Data
        let http: HTTPURLResponse
        do {
            let (body, resp) = try await URLSession.shared.data(for: req)
            guard let httpResp = resp as? HTTPURLResponse else {
                setFailure("refresh returned a non-HTTP response")
                return nil
            }
            data = body
            http = httpResp
        } catch {
            setFailure("refresh network error: \(error.localizedDescription)")
            log.error("Refresh network error: \(error.localizedDescription)")
            return nil
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            let detail = Self.briefBody(data)
            setFailure("refresh rejected (\(http.statusCode)) \(detail)")
            log.error("Refresh rejected HTTP \(http.statusCode) \(detail)")
            clearInvalidSession()
            return nil
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = Self.briefBody(data)
            setFailure("refresh HTTP \(http.statusCode) \(detail)")
            log.error("Refresh HTTP \(http.statusCode) \(detail)")
            return nil
        }

        guard let newTokens = Self.decodeRefreshPayload(data) else {
            setFailure("refresh response did not decode")
            log.error("Refresh decode failed: \(Self.briefBody(data))")
            return nil
        }
        guard !newTokens.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setFailure("refresh response had an empty access token")
            return nil
        }

        let merged = Self.mergingRefreshToken(newTokens, previous: previous)
        do {
            try store.save(merged)
        } catch {
            setFailure("could not save refreshed tokens")
            log.error("Refresh save failed: \(error.localizedDescription)")
            return nil
        }
        setCurrent(merged)
        setFailure(nil)
        log.info("Refresh OK; access exp=\(merged.expiration.timeIntervalSince1970)")
        return merged
    }

    nonisolated static func mergingRefreshToken(
        _ incoming: AuthTokensResponse,
        previous: AuthTokensResponse
    ) -> AuthTokensResponse {
        var result = incoming
        let hasNewRefresh = !(result.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if !hasNewRefresh {
            result.refreshToken = previous.refreshToken
            if result.refreshExpiration == nil {
                result.refreshExpiration = previous.refreshExpiration
            }
        }
        return result
    }

    nonisolated static func decodeRefreshPayload(_ data: Data) -> AuthTokensResponse? {
        let snake = JSONDecoder()
        snake.keyDecodingStrategy = .convertFromSnakeCase
        let plain = JSONDecoder()
        for decoder in [snake, plain] {
            if let wrapped = try? decoder.decode(ApiResponse<AuthTokensResponse>.self, from: data),
               let tokens = wrapped.data,
               !tokens.token.isEmpty {
                return tokens
            }
            if let tokens = try? decoder.decode(AuthTokensResponse.self, from: data),
               !tokens.token.isEmpty {
                return tokens
            }
        }
        return nil
    }

    private static func briefBody(_ data: Data) -> String {
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty { return "" }
        if text.count <= 180 { return text }
        return String(text.prefix(180))
    }
}
