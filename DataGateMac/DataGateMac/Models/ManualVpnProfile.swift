//
//  ManualVpnProfile.swift
//  DataGateMac
//
//  Local OpenVPN / VLESS profiles stored on disk (not issued by the backend).
//

import Foundation

enum ManualVpnProfileKind: String, Codable, Sendable {
    case openVpn
    case xray

    var payloadFileExtension: String {
        switch self {
        case .openVpn: return "ovpn"
        case .xray: return "vless"
        }
    }
}

struct ManualVpnProfile: Identifiable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var kind: ManualVpnProfileKind
    var payload: String
    var createdAt: Date
    var updatedAt: Date
}

struct ManualVpnProfileDraft: Equatable, Sendable {
    var displayName: String
    var kind: ManualVpnProfileKind
    var payload: String
}
