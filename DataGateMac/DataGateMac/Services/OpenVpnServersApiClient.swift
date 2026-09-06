//
//  OpenVpnServersApiClient.swift
//  DataGateMac
//
//  Fetches server list from GET /api/v3/open-vpn-servers/get-all-with-status.
//  Legacy v1 GET /api/open-vpn-servers/get-all-with-status hides UDP and Xray (TCP OpenVPN only).
//

import Foundation
import os

private let log = Logger(subsystem: "imkolganov.DataGateMac", category: "OpenVpnServersApi")

final class OpenVpnServersApiClient {
    private init() {}

    static let shared = OpenVpnServersApiClient()

    /// GET /api/v3/open-vpn-servers/get-all-with-status. Requires Bearer token.
    func getAllWithStatus(token: String, withoutCache: Bool = false) async throws -> [OpenVpnServerWithStatusDto] {
        let config = try AppConfig.load()
        let baseUrl = config.apiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !baseUrl.isEmpty else {
            throw ApiClientError.invalidConfig
        }
        var urlString = "\(baseUrl)/api/v3/open-vpn-servers/get-all-with-status"
        if withoutCache {
            urlString += "?withoutCache=true"
        }
        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ApiClientError.invalidResponse
        }

        let bodyPreview = String(data: data, encoding: .utf8).map { $0.prefix(2000) } ?? "<invalid utf8>"
        log.info("GET api/v3/open-vpn-servers/get-all-with-status withoutCache=\(withoutCache) → HTTP \(http.statusCode), body: \(String(describing: bodyPreview))")

        if http.statusCode == 401 || http.statusCode == 403 {
            throw ApiClientError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw ApiClientError.httpError(statusCode: http.statusCode)
        }

        let decoder = JSONDecoder()
        let apiResp = try decoder.decode(ApiResponse<OpenVpnServerWithStatusesResponse>.self, from: data)
        let servers = apiResp.data?.openVpnServerWithStatuses ?? []
        log.info("Decoded \(servers.count) server(s)")
        return servers
    }
}

enum ApiClientError: LocalizedError {
    case invalidConfig
    case invalidResponse
    case unauthorized
    case httpError(statusCode: Int)
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfig: return "Invalid API configuration"
        case .invalidResponse: return "Invalid response"
        case .unauthorized: return "Unauthorized"
        case .httpError(let code): return "HTTP error: \(code)"
        case .custom(let msg): return msg
        }
    }
}
