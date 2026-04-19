//
//  OpenVpnServerModels.swift
//  DataGateMac
//
//  Matches backend OpenVpnServerWithStatusesResponse, OpenVpnServerWithStatusDto, etc.
//

import Foundation

struct OpenVpnServerWithStatusesResponse: Decodable {
    let openVpnServerWithStatuses: [OpenVpnServerWithStatusDto]

    enum CodingKeys: String, CodingKey {
        case openVpnServerWithStatuses
    }
}

struct OpenVpnServerWithStatusDto: Decodable, Identifiable {
    var id: Int { openVpnServerResponses.openVpnServer.id }

    let openVpnServerResponses: OpenVpnServerResponse
    let openVpnServerStatusLogResponse: OpenVpnServerStatusLogResponse?
    let countConnectedClients: Int
    let countSessions: Int
    let totalBytesIn: Int64
    let totalBytesOut: Int64

    enum CodingKeys: String, CodingKey {
        case openVpnServerResponses
        case openVpnServerStatusLogResponse
        case countConnectedClients
        case countSessions
        case totalBytesIn
        case totalBytesOut
    }
}

struct OpenVpnServerResponse: Decodable {
    let openVpnServer: OpenVpnServerDto

    enum CodingKeys: String, CodingKey {
        case openVpnServer
    }
}

struct OpenVpnServerDto: Decodable {
    let id: Int
    let serverName: String
    let isOnline: Bool?
    let isDefault: Bool
    let apiUrl: String
    let latitude: Double?
    let longitude: Double?
    let isEnableWss: Bool?
    let createDate: String
    let lastUpdate: String
    /// When the API omits this field, treat the server as allowed (same as DataGate Linux).
    let isAccessibleForUserQuotaPlan: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case serverName
        case isOnline
        case isDefault
        case apiUrl
        case latitude
        case longitude
        case isEnableWss
        case createDate
        case lastUpdate
        case isAccessibleForUserQuotaPlan
        case isAccessibleForUserQuotaPlanPascal = "IsAccessibleForUserQuotaPlan"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        serverName = (try? c.decode(String.self, forKey: .serverName)) ?? ""
        isOnline = try? c.decodeIfPresent(Bool.self, forKey: .isOnline)
        isDefault = (try? c.decode(Bool.self, forKey: .isDefault)) ?? false
        apiUrl = (try? c.decode(String.self, forKey: .apiUrl)) ?? ""
        latitude = try? c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try? c.decodeIfPresent(Double.self, forKey: .longitude)
        isEnableWss = try? c.decodeIfPresent(Bool.self, forKey: .isEnableWss)
        createDate = (try? c.decode(String.self, forKey: .createDate)) ?? ""
        lastUpdate = (try? c.decode(String.self, forKey: .lastUpdate)) ?? ""
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .isAccessibleForUserQuotaPlan) {
            isAccessibleForUserQuotaPlan = v
        } else if let v = try? c.decodeIfPresent(Bool.self, forKey: .isAccessibleForUserQuotaPlanPascal) {
            isAccessibleForUserQuotaPlan = v
        } else {
            isAccessibleForUserQuotaPlan = true
        }
    }
}

struct OpenVpnServerStatusLogResponse: Decodable {
    let vpnServerId: Int
    let sessionId: String
    let upSince: String
    let serverLocalIp: String
    let serverRemoteIp: String
    let bytesIn: Int64
    let bytesOut: Int64
    let version: String

    enum CodingKeys: String, CodingKey {
        case vpnServerId
        case sessionId
        case upSince
        case serverLocalIp
        case serverRemoteIp
        case bytesIn
        case bytesOut
        case version
    }
}
