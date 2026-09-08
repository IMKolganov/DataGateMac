//
//  AuthTokensResponse.swift
//  DataGateMac
//
//  Matches OpenVPNGateMonitor.SharedModels.DataGateMonitorBackend.Auth.Responses.AuthTokensResponse
//

import Foundation

struct AuthTokensResponse: Codable {
    var token: String
    var expiration: Date
    var refreshToken: String?
    var refreshExpiration: Date?

    enum CodingKeys: String, CodingKey {
        case token
        case expiration
        case refreshToken
        case refreshExpiration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decode(String.self, forKey: .token)
        expiration = try Self.decodeDate(c, forKey: .expiration)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
        refreshExpiration = try Self.decodeDateIfPresent(c, forKey: .refreshExpiration)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(token, forKey: .token)
        try c.encode(expiration, forKey: .expiration)
        try c.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try c.encodeIfPresent(refreshExpiration, forKey: .refreshExpiration)
    }

    private static func decodeDate(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date {
        try AuthJSONDate.decode(container, forKey: key)
    }

    private static func decodeDateIfPresent(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        try AuthJSONDate.decodeIfPresent(container, forKey: key)
    }
}
