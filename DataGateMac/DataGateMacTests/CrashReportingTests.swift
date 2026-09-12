//
//  CrashReportingTests.swift
//  DataGateMacTests
//

import XCTest
@testable import DataGateMac

final class CrashReportingTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrashReportingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        CrashIngestURLProtocol.handler = nil
        CrashIngestURLProtocol.lastRequest = nil
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
        CrashIngestURLProtocol.handler = nil
        CrashIngestURLProtocol.lastRequest = nil
    }

    func testFileNameMatchesWindowsPatternInUTC() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 1, minute: 2, second: 3))!
        XCTAssertEqual(
            CrashReportText.fileName(at: date, timeZone: TimeZone(secondsFromGMT: 0)!),
            "DataGateMac_crash_20260913_010203.txt"
        )
    }

    func testBodyIncludesExceptionAndStack() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 12, minute: 0, second: 0))!
        let text = CrashReportText.body(
            timestamp: date,
            appVersion: "1.0.3 (27)",
            osVersion: "macOS 26.2",
            arch: "arm64",
            kind: "fatal",
            exceptionName: "NSInternalInconsistencyException",
            message: "unexpected nil",
            stack: ["0 DataGateMac 0x1", "1 DataGateMac 0x2"]
        )
        XCTAssertTrue(text.contains("timestamp_utc=2026-05-05T12:00:00Z"))
        XCTAssertTrue(text.contains("process=imkolganov.DataGateMac"))
        XCTAssertTrue(text.contains("app_version=1.0.3 (27)"))
        XCTAssertTrue(text.contains("exception=NSInternalInconsistencyException"))
        XCTAssertTrue(text.contains("message=unexpected nil"))
        XCTAssertTrue(text.contains("stack:"))
        XCTAssertTrue(text.contains("0 DataGateMac 0x1"))
    }

    func testPromotePendingSignalWritesDatedReport() throws {
        let pending = scratch.appendingPathComponent(CrashReportStore.pendingSignalFileName)
        try "kind=fatal\nsignal_name=SIGABRT\n".write(to: pending, atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 3, minute: 4, second: 5))!

        CrashReportStore.promotePendingSignalIfNeeded(
            directory: scratch,
            now: now,
            appVersion: "1.0.3 (27)",
            osVersion: "macOS 26.2",
            arch: "arm64",
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
        let report = scratch.appendingPathComponent("DataGateMac_crash_20260102_030405.txt")
        let text = try String(contentsOf: report, encoding: .utf8)
        XCTAssertTrue(text.contains("app_version=1.0.3 (27)"))
        XCTAssertTrue(text.contains("signal_name=SIGABRT"))
    }

    func testUploadDecisionDeletesSuccessAndClientErrors() {
        XCTAssertEqual(CrashReportUploader.decision(statusCode: 204), .delete)
        XCTAssertEqual(CrashReportUploader.decision(statusCode: 200), .delete)
        XCTAssertEqual(CrashReportUploader.decision(statusCode: 400), .delete)
        XCTAssertEqual(CrashReportUploader.decision(statusCode: 413), .delete)
        XCTAssertEqual(CrashReportUploader.decision(statusCode: 429), .retry)
        XCTAssertEqual(CrashReportUploader.decision(statusCode: 500), .retry)
        XCTAssertEqual(CrashReportUploader.decision(statusCode: 0), .retry)
    }

    func testIngestURL() {
        XCTAssertEqual(
            CrashReportUploader.ingestURL(apiBaseUrl: "https://api.example.com")?.absoluteString,
            "https://api.example.com/api/v1/mobile/crash-ingest"
        )
    }

    func testParseOptionalCrashReportToken() throws {
        let required: [String: Any] = [
            "APIBaseURL": "https://api.example.com/",
            "GIDClientID": "id.apps.googleusercontent.com",
            "RedirectPort": 51723,
        ]
        let without = try AppConfig.parse(required)
        XCTAssertNil(without.crashReportToken)
        XCTAssertEqual(without.apiBaseUrl, "https://api.example.com")

        var withToken = required
        withToken["CrashReportToken"] = "  secret-token  "
        XCTAssertEqual(try AppConfig.parse(withToken).crashReportToken, "secret-token")

        withToken["CrashReportToken"] = "   "
        XCTAssertNil(try AppConfig.parse(withToken).crashReportToken)
    }

    func testUploadDeletesFileOn204() async throws {
        let file = scratch.appendingPathComponent("DataGateMac_crash_20260101_000000.txt")
        try "kind=fatal\n".write(to: file, atomically: true, encoding: .utf8)

        CrashIngestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/plain; charset=utf-8")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Crash-Filename"), file.lastPathComponent)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Crash-Process"), CrashReportText.processId)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Crash-Token"), "tok")
            return (204, Data())
        }

        await CrashReportUploader.uploadPending(
            directory: scratch,
            session: Self.mockSession(),
            config: CrashReportUploadConfig(
                ingestURL: URL(string: "https://api.example.com/api/v1/mobile/crash-ingest")!,
                process: CrashReportText.processId,
                token: "tok"
            )
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNotNil(CrashIngestURLProtocol.lastRequest)
    }

    func testUploadKeepsFileOn500() async throws {
        let file = scratch.appendingPathComponent("DataGateMac_crash_20260101_000001.txt")
        try "kind=fatal\n".write(to: file, atomically: true, encoding: .utf8)

        CrashIngestURLProtocol.handler = { _ in (500, Data()) }

        await CrashReportUploader.uploadPending(
            directory: scratch,
            session: Self.mockSession(),
            config: CrashReportUploadConfig(
                ingestURL: URL(string: "https://api.example.com/api/v1/mobile/crash-ingest")!,
                process: CrashReportText.processId,
                token: nil
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testUploadDeletesFileOn413() async throws {
        let file = scratch.appendingPathComponent("DataGateMac_crash_20260101_000002.txt")
        try "kind=fatal\n".write(to: file, atomically: true, encoding: .utf8)

        CrashIngestURLProtocol.handler = { _ in (413, Data()) }

        await CrashReportUploader.uploadPending(
            directory: scratch,
            session: Self.mockSession(),
            config: CrashReportUploadConfig(
                ingestURL: URL(string: "https://api.example.com/api/v1/mobile/crash-ingest")!,
                process: CrashReportText.processId,
                token: nil
            )
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testUploaderIgnoresPendingSignalFile() async throws {
        let pending = scratch.appendingPathComponent(CrashReportStore.pendingSignalFileName)
        try "kind=fatal\n".write(to: pending, atomically: true, encoding: .utf8)
        CrashIngestURLProtocol.handler = { _ in
            XCTFail("should not upload pending_signal.txt")
            return (204, Data())
        }

        await CrashReportUploader.uploadPending(
            directory: scratch,
            session: Self.mockSession(),
            config: CrashReportUploadConfig(
                ingestURL: URL(string: "https://api.example.com/api/v1/mobile/crash-ingest")!,
                process: CrashReportText.processId,
                token: nil
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: pending.path))
        XCTAssertNil(CrashIngestURLProtocol.lastRequest)
    }

    private static func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CrashIngestURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class CrashIngestURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let result = Self.handler?(request) ?? (500, Data())
        let url = request.url ?? URL(string: "https://example.invalid")!
        let response = HTTPURLResponse(
            url: url,
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
