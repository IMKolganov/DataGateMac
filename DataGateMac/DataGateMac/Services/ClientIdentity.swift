//
//  ClientIdentity.swift
//  DataGateMac
//
//  Who is calling the DataGateMonitor backend: `X-Client-Name: mac` + the app build version.
//  Source of truth: NuGet DataGateMonitor.SharedModels (1.0.89+),
//  `DataGateMonitor.SharedModels.ClientIdentity.ClientIdentityRules` / `ClientNames`.
//  Change these values together with the backend rules.
//
//  Only for backend requests. The packet tunnel's WSS to the VPN node, GitHub update checks
//  and Google OAuth must not use this.
//

import Foundation
import os

nonisolated(unsafe) private let clientIdentityLog = Logger(subsystem: "imkolganov.DataGateMac", category: "ClientIdentity")

nonisolated enum ClientIdentity {
    static let nameHeader = "X-Client-Name"
    static let versionHeader = "X-Client-Version"
    static let nameQuery = "clientName"
    static let versionQuery = "clientVersion"
    static let clientName = "mac"
    static let maxVersionLength = 64

    /// Posted on the main queue, once per run, when the backend refuses this build (`object` is the `client_*` code).
    static let rejectedNotification = Notification.Name("DataGateClientIdentityRejected")

    /// `CFBundleShortVersionString (CFBundleVersion)`, e.g. `1.0.5 (29)`.
    static let clientVersion: String = version(from: Bundle.main.infoDictionary)

    static func version(from info: [String: Any]?) -> String {
        let short = (info?["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let build = (info?["CFBundleVersion"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let raw: String
        switch (short.isEmpty, build.isEmpty) {
        case (false, false): raw = "\(short) (\(build))"
        case (false, true): raw = short
        case (true, false): raw = build
        case (true, true): raw = ""
        }
        return sanitizeVersion(raw)
    }

    /// Printable ASCII only (0x20–0x7E), 1–64 chars; "0" when nothing is left.
    static func sanitizeVersion(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: raw.unicodeScalars.filter { $0.value >= 0x20 && $0.value <= 0x7E })
        let printable = String(scalars)
        let trimmed = String(printable.trimmingCharacters(in: .whitespaces).prefix(maxVersionLength))
            .trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "0" : trimmed
    }

    static func apply(to request: inout URLRequest, version: String = clientVersion) {
        request.setValue(clientName, forHTTPHeaderField: nameHeader)
        request.setValue(version, forHTTPHeaderField: versionHeader)
    }

    /// Adds `clientName` / `clientVersion` to a SignalR / WebSocket `/api/hubs/*` URL, keeping the existing query.
    static func appendToHubURL(_ url: URL, version: String = clientVersion) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (components.queryItems ?? []).filter { $0.name != nameQuery && $0.name != versionQuery }
        items.append(URLQueryItem(name: nameQuery, value: clientName))
        items.append(URLQueryItem(name: versionQuery, value: version))
        components.queryItems = items
        return components.url ?? url
    }

    /// `data.code` of a client-identity 400 (`client_name_missing`, …), or nil for any other body.
    static func rejectionCode(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = value(in: root, key: "data") as? [String: Any],
              let code = (value(in: payload, key: "code") as? String)?.trimmingCharacters(in: .whitespaces),
              code.hasPrefix("client_") else {
            return nil
        }
        return code
    }

    /// Session for backend calls; identity is also in `httpAdditionalHeaders` for callers that take a session.
    static let session: URLSession = makeSession(configuration: .default)

    static func makeSession(configuration: URLSessionConfiguration, version: String = clientVersion) -> URLSession {
        var headers = configuration.httpAdditionalHeaders ?? [:]
        headers[nameHeader] = clientName
        headers[versionHeader] = version
        configuration.httpAdditionalHeaders = headers
        return URLSession(configuration: configuration)
    }

    /// The one entry point for backend requests: sets the headers, runs the request, reports `client_*` 400s.
    static func data(
        for request: URLRequest,
        session: URLSession = ClientIdentity.session,
        version: String = clientVersion
    ) async throws -> (Data, URLResponse) {
        var request = request
        apply(to: &request, version: version)
        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 400, let code = rejectionCode(from: data) {
            clientIdentityLog.error("Backend rejected client identity (\(code, privacy: .public)) for \(request.url?.path ?? "", privacy: .public)")
            notifyRejected(code)
        }
        return (data, response)
    }

    nonisolated(unsafe) private static var didNotify = false
    private static let notifyLock = NSLock()

    static func notifyRejected(_ code: String) {
        notifyLock.lock()
        let first = !didNotify
        didNotify = true
        notifyLock.unlock()
        guard first else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: rejectedNotification, object: code)
        }
    }

    private static func value(in dict: [String: Any], key: String) -> Any? {
        dict.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }
}
