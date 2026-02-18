//
//  GoogleLoginResponse.swift
//  DataGateMac
//
//  Matches OpenVPNGateMonitor.SharedModels.DataGateMonitorBackend.Auth.Responses.GoogleLoginResponse
//  (extends AuthTokensResponse + userId, displayName, email, isNewUser)
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

    enum CodingKeys: String, CodingKey {
        case token
        case expiration
        case refreshToken
        case refreshExpiration
        case userId
        case displayName
        case email
        case isNewUser
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decode(String.self, forKey: .token)
        expiration = try Self.decodeDate(c, forKey: .expiration)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
        refreshExpiration = try Self.decodeDateIfPresent(c, forKey: .refreshExpiration)
        userId = (try? c.decode(Int.self, forKey: .userId)) ?? 0
        displayName = (try? c.decode(String.self, forKey: .displayName)) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email)
        isNewUser = (try? c.decode(Bool.self, forKey: .isNewUser)) ?? false
    }

    private static func decodeDate(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date {
        if let str = try? container.decode(String.self, forKey: key) {
            return ISO8601DateFormatter().date(from: str) ?? ISO8601DateFormatter().date(from: str.replacingOccurrences(of: "Z", with: "+00:00")) ?? Date()
        }
        let secs = try container.decode(Double.self, forKey: key)
        return Date(timeIntervalSince1970: secs)
    }

    private static func decodeDateIfPresent(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        guard container.contains(key) else { return nil }
        if let str = try? container.decode(String.self, forKey: key) {
            return ISO8601DateFormatter().date(from: str) ?? ISO8601DateFormatter().date(from: str.replacingOccurrences(of: "Z", with: "+00:00"))
        }
        if let secs = try? container.decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: secs)
        }
        return nil
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
