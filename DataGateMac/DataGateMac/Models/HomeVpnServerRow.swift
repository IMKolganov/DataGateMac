//
//  HomeVpnServerRow.swift
//  DataGateMac
//
//  One row for the Home VPN server picker (quota-allowed servers from api/v3 get-all-with-status).
//

import Foundation

struct HomeVpnServerRow: Identifiable, Hashable {
    let id: Int
    let displayName: String
    let isOnline: Bool
    let clientCount: Int
    /// `false` = issued .ovpn talks to OpenVPN directly (typically UDP). `true` = WSS bridge.
    let usesWss: Bool
    /// Backend `serverType == Xray`.
    let isXray: Bool
    /// `UDP` / `TCP` from backend tags (or the server name). Nil if unknown.
    let protocolLabel: String?
}
