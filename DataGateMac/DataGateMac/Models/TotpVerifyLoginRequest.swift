//
//  TotpVerifyLoginRequest.swift
//  DataGateMac
//
//  POST /api/auth/totp/verify-login
//

import Foundation

struct TotpVerifyLoginRequest: Encodable {
    let loginChallengeId: String
    let code: String
}
