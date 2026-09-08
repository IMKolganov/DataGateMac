//
//  GoogleLoginResponse.swift
//  DataGateMac
//
//  Matches DataGateMonitor.SharedModels.DataGateMonitor.Auth.Responses.GoogleLoginResponse
//  (LoginResponse + isNewUser, avatarUrl from Google picture).
//

import Foundation

struct GoogleLoginResponse: Codable {
    var token: String
    var expiration: Date
    var refreshToken: String?
    var refreshExpiration: Date?
    var userId: Int
    var displayName: String
    var email: String?
    var isNewUser: Bool
    /// HTTPS profile image from Google (`picture` claim), when the backend stored it.
    var avatarUrl: String?
    /// Admin accounts with TOTP enabled: tokens are not issued until `/api/auth/totp/verify-login`.
    var requiresTotp: Bool
    var loginChallengeId: String?
    var requiresTotpSetup: Bool

    var isTotpChallenge: Bool {
        requiresTotp && !(loginChallengeId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var hasAccessToken: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case token
        case expiration
        case refreshToken
        case refreshExpiration
        case userId
        case displayName
        case email
        case isNewUser
        case avatarUrl
        case requiresTotp
        case loginChallengeId
        case requiresTotpSetup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = (try? c.decode(String.self, forKey: .token)) ?? ""
        expiration = (try? Self.decodeDate(c, forKey: .expiration)) ?? Date.distantPast
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
        refreshExpiration = try? Self.decodeDateIfPresent(c, forKey: .refreshExpiration)
        userId = (try? c.decode(Int.self, forKey: .userId)) ?? 0
        displayName = (try? c.decode(String.self, forKey: .displayName)) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email)
        isNewUser = (try? c.decode(Bool.self, forKey: .isNewUser)) ?? false
        avatarUrl = ProfileImageURL.normalizedString(try c.decodeIfPresent(String.self, forKey: .avatarUrl))
        requiresTotp = (try? c.decode(Bool.self, forKey: .requiresTotp)) ?? false
        loginChallengeId = try c.decodeIfPresent(String.self, forKey: .loginChallengeId)
        requiresTotpSetup = (try? c.decode(Bool.self, forKey: .requiresTotpSetup)) ?? false
    }

    private static func decodeDate(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date {
        try AuthJSONDate.decode(container, forKey: key)
    }

    private static func decodeDateIfPresent(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        try AuthJSONDate.decodeIfPresent(container, forKey: key)
    }

    /// For saving/loading as AuthTokensResponse (token store)
    var asAuthTokens: AuthTokensResponse {
        AuthTokensResponse(
            token: token,
            expiration: expiration,
            refreshToken: refreshToken,
            refreshExpiration: refreshExpiration
        )
    }
}

// Allow init for AuthTokensResponse from plain fields (used in asAuthTokens)
extension AuthTokensResponse {
    init(token: String, expiration: Date, refreshToken: String?, refreshExpiration: Date?) {
        self.token = token
        self.expiration = expiration
        self.refreshToken = refreshToken
        self.refreshExpiration = refreshExpiration
    }
}
