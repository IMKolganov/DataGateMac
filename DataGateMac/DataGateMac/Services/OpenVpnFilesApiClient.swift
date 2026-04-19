//
//  OpenVpnFilesApiClient.swift
//  DataGateMac
//
//  Same as DataGateWin: download-file-by-cn, add-with-token; used to get OVPN content for Connect.
//

import Foundation
import os

private let log = Logger(subsystem: "imkolganov.DataGateMac", category: "OpenVpnFilesApi")

final class OpenVpnFilesApiClient {
    private init() {}
    static let shared = OpenVpnFilesApiClient()

    /// Ensures device file exists (add-with-token if needed) and downloads it. Same flow as Windows.
    func ensureAndDownloadDeviceFile(
        vpnServerId: Int,
        commonName: String,
        externalId: String,
        issuedTo: String,
        token: String
    ) async throws -> DownloadFileResponse {
        if let first = try await tryDownload(vpnServerId: vpnServerId, commonName: commonName, token: token) {
            return first
        }
        try await addWithToken(
            vpnServerId: vpnServerId,
            commonName: commonName,
            externalId: externalId,
            issuedTo: issuedTo,
            token: token
        )
        guard let second = try await tryDownload(vpnServerId: vpnServerId, commonName: commonName, token: token) else {
            throw ApiClientError.custom("OVPN file not found after create")
        }
        return second
    }

    private func tryDownload(vpnServerId: Int, commonName: String, token: String) async throws -> DownloadFileResponse? {
        let config = try AppConfig.load()
        let baseUrl = config.apiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: "\(baseUrl)/api/open-vpn-files/download-file-by-cn")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body = DownloadFileByCnRequest(vpnServerId: vpnServerId, commonName: commonName)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ApiClientError.invalidResponse }

        if http.statusCode == 404 {
            return nil
        }
        if (200...299).contains(http.statusCode) == false {
            if let raw = String(data: data, encoding: .utf8), raw.lowercased().contains("not found") {
                return nil
            }
            throw ApiClientError.httpError(statusCode: http.statusCode)
        }

        let apiResp = try JSONDecoder().decode(ApiResponse<DownloadFileResponse>.self, from: data)
        guard apiResp.success, let fileResp = apiResp.data else { return nil }
        return fileResp
    }

    private func addWithToken(
        vpnServerId: Int,
        commonName: String,
        externalId: String,
        issuedTo: String,
        token: String
    ) async throws {
        let config = try AppConfig.load()
        let baseUrl = config.apiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: "\(baseUrl)/api/open-vpn-files/add-with-token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body = AddFileWithTokenRequest(
            vpnServerId: vpnServerId,
            commonName: commonName,
            externalId: externalId,
            issuedTo: issuedTo
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ApiClientError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            log.error("add-with-token failed: \(http.statusCode) \(raw)")
            throw ApiClientError.httpError(statusCode: http.statusCode)
        }
    }
}

