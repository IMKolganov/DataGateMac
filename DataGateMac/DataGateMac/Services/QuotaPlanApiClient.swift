//
//  QuotaPlanApiClient.swift
//  DataGateMac
//
//  POST /api/quota-plans/get-all, GET /api/user-quota-plans/get-by-user-id/{id}
//

import Foundation
import os

private let log = Logger(subsystem: "imkolganov.DataGateMac", category: "QuotaPlanApi")

final class QuotaPlanApiClient {
    private init() {}

    static let shared = QuotaPlanApiClient()

    private struct IncludeInactiveBody: Encodable {
        let includeInactive: Bool
    }

    func getAllQuotaPlans(token: String, includeInactive: Bool) async throws -> ApiResponse<QuotaPlansGetAllData> {
        let config = try AppConfig.load()
        let baseUrl = config.apiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !baseUrl.isEmpty else { throw ApiClientError.invalidConfig }

        let url = URL(string: "\(baseUrl)/api/quota-plans/get-all")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(IncludeInactiveBody(includeInactive: includeInactive))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ApiClientError.invalidResponse
        }
        log.info("POST quota-plans/get-all → HTTP \(http.statusCode)")

        if http.statusCode == 401 || http.statusCode == 403 {
            throw ApiClientError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw ApiClientError.httpError(statusCode: http.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(ApiResponse<QuotaPlansGetAllData>.self, from: data)
    }

    func getUserQuotaPlansByUserId(token: String, userId: Int) async throws -> ApiResponse<UserQuotaPlansByUserData> {
        let config = try AppConfig.load()
        let baseUrl = config.apiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !baseUrl.isEmpty else { throw ApiClientError.invalidConfig }

        let url = URL(string: "\(baseUrl)/api/user-quota-plans/get-by-user-id/\(userId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ApiClientError.invalidResponse
        }
        log.info("GET user-quota-plans/by-user-id/\(userId) → HTTP \(http.statusCode)")

        if http.statusCode == 401 || http.statusCode == 403 {
            throw ApiClientError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw ApiClientError.httpError(statusCode: http.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(ApiResponse<UserQuotaPlansByUserData>.self, from: data)
    }
}
