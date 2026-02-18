//
//  StatisticsApiClient.swift
//  DataGateMac
//
//  Fetches overview statistics from overview/series and overview/summary.
//

import Foundation
import os

private let log = Logger(subsystem: "imkolganov.DataGateMac", category: "StatisticsApi")

final class StatisticsApiClient {
    private init() {}
    static let shared = StatisticsApiClient()

    /// GET overview/series?From=&To=&Grouping=&VpnServerId=&ExternalId=
    func getOverviewSeries(
        token: String,
        from: Date,
        to: Date,
        grouping: OverviewGrouping,
        vpnServerId: Int? = nil
    ) async throws -> OverviewSeriesResponse {
        let config = try AppConfig.load()
        let baseUrl = config.apiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var comps = URLComponents(string: "\(baseUrl)/api/open-vpn-clients/overview/series")!
        comps.queryItems = [
            URLQueryItem(name: "From", value: iso8601(from)),
            URLQueryItem(name: "To", value: iso8601(to)),
            URLQueryItem(name: "Grouping", value: "\(grouping.rawValue)"),
        ]
        if let id = vpnServerId {
            comps.queryItems?.append(URLQueryItem(name: "VpnServerId", value: "\(id)"))
        }
        guard let url = comps.url else { throw ApiClientError.invalidConfig }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ApiClientError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw ApiClientError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            throw ApiClientError.httpError(statusCode: http.statusCode)
        }

        let decoder = JSONDecoder()
        let apiResp = try decoder.decode(ApiResponse<OverviewSeriesResponse>.self, from: data)
        guard let payload = apiResp.data else {
            return OverviewSeriesResponse(meta: nil, summary: nil, overviewSeriesRows: [])
        }
        return payload
    }

    /// GET overview/summary?From=&To=&VpnServerId=&ExternalId=
    func getOverviewSummary(
        token: String,
        from: Date,
        to: Date,
        vpnServerId: Int? = nil
    ) async throws -> OverviewTotalsResponse {
        let config = try AppConfig.load()
        let baseUrl = config.apiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var comps = URLComponents(string: "\(baseUrl)/api/open-vpn-clients/overview/summary")!
        comps.queryItems = [
            URLQueryItem(name: "From", value: iso8601(from)),
            URLQueryItem(name: "To", value: iso8601(to)),
        ]
        if let id = vpnServerId {
            comps.queryItems?.append(URLQueryItem(name: "VpnServerId", value: "\(id)"))
        }
        guard let url = comps.url else { throw ApiClientError.invalidConfig }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ApiClientError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw ApiClientError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            throw ApiClientError.httpError(statusCode: http.statusCode)
        }

        let decoder = JSONDecoder()
        let apiResp = try decoder.decode(ApiResponse<OverviewTotalsResponse>.self, from: data)
        guard let payload = apiResp.data else {
            let empty = TotalsPayloadDto(sessionsCount: 0, usersCount: 0, trafficInBytes: 0, trafficOutBytes: 0, trafficTotalBytes: nil)
            return OverviewTotalsResponse(meta: nil, totals: empty)
        }
        return payload
    }

    private func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
