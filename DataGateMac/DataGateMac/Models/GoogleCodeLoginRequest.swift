//
//  GoogleCodeLoginRequest.swift
//  DataGateMac
//
//  Matches OpenVPNGateMonitor.SharedModels.DataGateMonitorBackend.Auth.Requests.GoogleCodeLoginRequest
//

import Foundation

struct GoogleCodeLoginRequest: Encodable {
    let code: String
    let codeVerifier: String
    let redirectUri: String

    enum CodingKeys: String, CodingKey {
        case code
        case codeVerifier
        case redirectUri
    }
}
