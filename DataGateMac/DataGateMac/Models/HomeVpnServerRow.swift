//
//  HomeVpnServerRow.swift
//  DataGateMac
//
//  One row for the Home VPN server picker (WSS-capable servers from get-all-with-status).
//

import Foundation

struct HomeVpnServerRow: Identifiable, Hashable {
    let id: Int
    let displayName: String
    let isOnline: Bool
    let clientCount: Int
}
