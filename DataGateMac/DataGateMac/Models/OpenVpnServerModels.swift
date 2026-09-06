//
//  OpenVpnServerModels.swift
//  DataGateMac
//
//  Matches backend v3 GET /api/v3/open-vpn-servers/get-all-with-status
//  (legacy v1 JSON aliases still accepted).
//

import Foundation

/// Backend `VpnServerType`: OpenVpn = 0, Xray = 1.
enum VpnServerType: Equatable, Sendable {
    case openVpn
    case xray
    case unknown
}

struct OpenVpnServerWithStatusesResponse: Decodable {
    let openVpnServerWithStatuses: [OpenVpnServerWithStatusDto]

    enum CodingKeys: String, CodingKey {
        case openVpnServerWithStatuses
        case vpnServerWithStatuses
        case OpenVpnServerWithStatuses
        case VpnServerWithStatuses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        openVpnServerWithStatuses =
            JSONKeyAlt.decode([OpenVpnServerWithStatusDto].self, from: c, keys: [
                .openVpnServerWithStatuses,
                .vpnServerWithStatuses,
                .OpenVpnServerWithStatuses,
                .VpnServerWithStatuses,
            ]) ?? []
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
        case vpnServerResponses
        case OpenVpnServerResponses
        case VpnServerResponses
        case openVpnServerStatusLogResponse
        case vpnServerStatusLogResponse
        case countConnectedClients
        case countSessions
        case totalBytesIn
        case totalBytesOut
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let responses = JSONKeyAlt.decode(OpenVpnServerResponse.self, from: c, keys: [
            .openVpnServerResponses,
            .vpnServerResponses,
            .OpenVpnServerResponses,
            .VpnServerResponses,
        ]) else {
            throw DecodingError.keyNotFound(
                CodingKeys.openVpnServerResponses,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing vpn/openVpn server object")
            )
        }
        openVpnServerResponses = responses
        openVpnServerStatusLogResponse = JSONKeyAlt.decode(
            OpenVpnServerStatusLogResponse.self,
            from: c,
            keys: [.openVpnServerStatusLogResponse, .vpnServerStatusLogResponse]
        )
        countConnectedClients = (try? c.decode(Int.self, forKey: .countConnectedClients)) ?? 0
        countSessions = (try? c.decode(Int.self, forKey: .countSessions)) ?? 0
        totalBytesIn = (try? c.decode(Int64.self, forKey: .totalBytesIn)) ?? 0
        totalBytesOut = (try? c.decode(Int64.self, forKey: .totalBytesOut)) ?? 0
    }

    var isOpenVpnConnectable: Bool {
        let s = openVpnServerResponses.openVpnServer
        return s.serverType != .xray && isConnectable
    }

    /// Quota-allowed, not deleted/disabled — OpenVPN or Xray.
    var isConnectable: Bool {
        let s = openVpnServerResponses.openVpnServer
        return !s.isDeleted && !s.isDisabled && s.isAccessibleForUserQuotaPlan
    }
}

struct OpenVpnServerResponse: Decodable {
    let openVpnServer: OpenVpnServerDto

    enum CodingKeys: String, CodingKey {
        case openVpnServer
        case vpnServer
        case OpenVpnServer
        case VpnServer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let server = JSONKeyAlt.decode(OpenVpnServerDto.self, from: c, keys: [
            .openVpnServer,
            .vpnServer,
            .OpenVpnServer,
            .VpnServer,
        ]) else {
            throw DecodingError.keyNotFound(
                CodingKeys.openVpnServer,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing vpn/openVpn server")
            )
        }
        openVpnServer = server
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
    /// Backend tags; first `udp` / `tcp` is the Access-list protocol (same as Android).
    let tags: [String]
    /// When the API omits this field, treat the server as allowed (same as DataGate Linux).
    let isAccessibleForUserQuotaPlan: Bool
    let serverType: VpnServerType
    let isDeleted: Bool
    let isDisabled: Bool

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
        case tags
        case tagsPascal = "Tags"
        case isAccessibleForUserQuotaPlan
        case isAccessibleForUserQuotaPlanPascal = "IsAccessibleForUserQuotaPlan"
        case serverType
        case isDeleted
        case isDisabled
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
        createDate = JSONKeyAlt.decodeString(from: c, key: .createDate)
        lastUpdate = JSONKeyAlt.decodeString(from: c, key: .lastUpdate)
        if let t = try? c.decodeIfPresent([String].self, forKey: .tags) {
            tags = t
        } else if let t = try? c.decodeIfPresent([String].self, forKey: .tagsPascal) {
            tags = t
        } else {
            tags = []
        }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .isAccessibleForUserQuotaPlan) {
            isAccessibleForUserQuotaPlan = v
        } else if let v = try? c.decodeIfPresent(Bool.self, forKey: .isAccessibleForUserQuotaPlanPascal) {
            isAccessibleForUserQuotaPlan = v
        } else {
            isAccessibleForUserQuotaPlan = true
        }
        serverType = JSONKeyAlt.decodeServerType(from: c, key: .serverType)
        isDeleted = (try? c.decode(Bool.self, forKey: .isDeleted)) ?? false
        isDisabled = (try? c.decode(Bool.self, forKey: .isDisabled)) ?? false
    }

    /// UDP/TCP for the server picker, from `tags` then from the display name (Android uses tags.first).
    var listedLinkProtocol: String? {
        if serverType == .xray { return "Xray" }
        return VpnServerListLabel.linkProtocol(tags: tags, serverName: serverName)
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vpnServerId = (try? c.decode(Int.self, forKey: .vpnServerId)) ?? 0
        sessionId = (try? c.decode(String.self, forKey: .sessionId)) ?? ""
        upSince = JSONKeyAlt.decodeString(from: c, key: .upSince)
        serverLocalIp = (try? c.decode(String.self, forKey: .serverLocalIp)) ?? ""
        serverRemoteIp = (try? c.decode(String.self, forKey: .serverRemoteIp)) ?? ""
        bytesIn = (try? c.decode(Int64.self, forKey: .bytesIn)) ?? 0
        bytesOut = (try? c.decode(Int64.self, forKey: .bytesOut)) ?? 0
        version = (try? c.decode(String.self, forKey: .version)) ?? ""
    }
}

private enum JSONKeyAlt {
    static func decode<T: Decodable, K: CodingKey>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<K>,
        keys: [K]
    ) -> T? {
        for key in keys {
            if let v = try? container.decode(T.self, forKey: key) {
                return v
            }
        }
        return nil
    }

    static func decodeString<K: CodingKey>(from container: KeyedDecodingContainer<K>, key: K) -> String {
        if let s = try? container.decode(String.self, forKey: key) {
            return s
        }
        return ""
    }

    static func decodeServerType<K: CodingKey>(from container: KeyedDecodingContainer<K>, key: K) -> VpnServerType {
        if let i = try? container.decode(Int.self, forKey: key) {
            if i == 1 { return .xray }
            if i == 0 { return .openVpn }
            return .unknown
        }
        if let s = try? container.decode(String.self, forKey: key) {
            switch s.lowercased() {
            case "xray": return .xray
            case "openvpn", "open_vpn": return .openVpn
            default: return .unknown
            }
        }
        return .openVpn
    }
}
