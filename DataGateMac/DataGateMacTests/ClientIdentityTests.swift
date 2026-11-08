//
//  ClientIdentityTests.swift
//  DataGateMacTests
//

import XCTest
@testable import DataGateMac

final class ClientIdentityTests: XCTestCase {
    override func setUp() {
        RecordingURLProtocol.reset()
    }

    override func tearDown() {
        RecordingURLProtocol.reset()
    }

    func testBackendRequestGetsNameAndVersionHeaders() async throws {
        RecordingURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        let request = URLRequest(url: URL(string: "https://api.example.test/api/v3/open-vpn-servers/get-all-with-status")!)

        _ = try await ClientIdentity.data(for: request, session: Self.recordingSession(), version: "1.0.5 (29)")

        let sent = try XCTUnwrap(RecordingURLProtocol.requests.first)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Client-Name"), "mac")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Client-Version"), "1.0.5 (29)")
    }

    func testRefreshThenRetryBothCarryHeaders() async throws {
        // AuthSession refreshes, then the API client retries: both go through ClientIdentity.data.
        RecordingURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        var refresh = URLRequest(url: URL(string: "https://api.example.test/api/auth/refresh")!)
        refresh.httpMethod = "POST"
        var retry = URLRequest(url: URL(string: "https://api.example.test/api/open-vpn-files/download-file-by-cn")!)
        retry.httpMethod = "POST"
        retry.setValue("Bearer new-access", forHTTPHeaderField: "Authorization")

        _ = try await ClientIdentity.data(for: refresh, session: Self.recordingSession(), version: "1.0.5 (29)")
        _ = try await ClientIdentity.data(for: retry, session: Self.recordingSession(), version: "1.0.5 (29)")

        XCTAssertEqual(RecordingURLProtocol.requests.count, 2)
        for sent in RecordingURLProtocol.requests {
            XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Client-Name"), "mac")
            XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Client-Version"), "1.0.5 (29)")
        }
        XCTAssertEqual(RecordingURLProtocol.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
    }

    func testPlainSessionDoesNotAddHeaders() async throws {
        // GitHub update checks and the packet tunnel's WSS keep their own sessions.
        RecordingURLProtocol.handler = { _ in (200, Data()) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        let request = URLRequest(url: URL(string: "https://api.github.com/repos/x/y/releases/latest")!)

        _ = try await URLSession(configuration: config).data(for: request)

        let sent = try XCTUnwrap(RecordingURLProtocol.requests.first)
        XCTAssertNil(sent.value(forHTTPHeaderField: "X-Client-Name"))
        XCTAssertNil(sent.value(forHTTPHeaderField: "X-Client-Version"))
    }

    func testBackendSessionCarriesHeadersForSessionOnlyCallers() {
        let session = ClientIdentity.makeSession(configuration: .ephemeral, version: "1.0.5 (29)")
        let headers = session.configuration.httpAdditionalHeaders as? [String: String]
        XCTAssertEqual(headers?["X-Client-Name"], "mac")
        XCTAssertEqual(headers?["X-Client-Version"], "1.0.5 (29)")
    }

    func testHubURLGetsQueryParametersKeepingExistingOnes() throws {
        let url = ClientIdentity.appendToHubURL(
            URL(string: "https://api.example.test/api/hubs/frontend?access_token=x")!,
            version: "1.0.5 (29)"
        )
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.map(\.name), ["access_token", "clientName", "clientVersion"])
        XCTAssertEqual(items.first { $0.name == "clientName" }?.value, "mac")
        XCTAssertEqual(items.first { $0.name == "clientVersion" }?.value, "1.0.5 (29)")
    }

    func testVersionFromBundleInfoIsBackendSafe() {
        XCTAssertEqual(ClientIdentity.version(from: ["CFBundleShortVersionString": "1.0.5", "CFBundleVersion": "29"]), "1.0.5 (29)")
        XCTAssertEqual(ClientIdentity.version(from: ["CFBundleShortVersionString": "1.0.5"]), "1.0.5")
        XCTAssertEqual(ClientIdentity.version(from: nil), "0")
        XCTAssertEqual(ClientIdentity.sanitizeVersion("1.0-é"), "1.0-")
        XCTAssertEqual(ClientIdentity.sanitizeVersion(String(repeating: "9", count: 100)).count, 64)
    }

    func testRejectionCodeOnlyMatchesClientCodes() {
        XCTAssertEqual(ClientIdentity.rejectionCode(from: Data(#"{"data":{"code":"client_name_missing"}}"#.utf8)), "client_name_missing")
        XCTAssertEqual(ClientIdentity.rejectionCode(from: Data(#"{"Data":{"Code":"client_name_unknown"}}"#.utf8)), "client_name_unknown")
        XCTAssertNil(ClientIdentity.rejectionCode(from: Data(#"{"data":{"code":"invalid_token"}}"#.utf8)))
        XCTAssertNil(ClientIdentity.rejectionCode(from: Data("not json".utf8)))
    }

    func testCrashUploadKeepsReportsWhenBuildIsRefused() {
        let body = Data(#"{"success":false,"data":{"code":"client_version_missing"}}"#.utf8)
        XCTAssertEqual(CrashReportUploader.decision(statusCode: 400, body: body), .retry)
        XCTAssertEqual(CrashReportUploader.decision(statusCode: 400), .delete)
    }

    private static func recordingSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset() {
        handler = nil
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let result = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.invalid")!,
            statusCode: result.0,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
