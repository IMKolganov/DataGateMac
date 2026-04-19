//
//  RefreshRequest.swift
//  DataGateMac
//
//  Matches OpenVPNGateMonitor.SharedModels.DataGateMonitorBackend.Auth.Requests.RefreshRequest
//

import Foundation

struct RefreshRequest: Encodable {
    let refreshToken: String
    let deviceId: String?
    let userAgent: String?

    enum CodingKeys: String, CodingKey {
        case refreshToken
        case deviceId
        case userAgent
    }
}
