//
//  ApiResponse.swift
//  DataGateMac
//
//  Matches OpenVPNGateMonitor.SharedModels.Responses.ApiResponse<T>
//

import Foundation

struct ApiResponse<T: Decodable>: Decodable {
    let success: Bool
    let message: String
    let data: T?

    enum CodingKeys: String, CodingKey {
        case success = "success"
        case message = "message"
        case data = "data"
    }

    /// Backend may send PascalCase; support both
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decode(Bool.self, forKey: .success)
        message = (try? c.decode(String.self, forKey: .message)) ?? ""
        data = try? c.decodeIfPresent(T.self, forKey: .data)
    }
}
