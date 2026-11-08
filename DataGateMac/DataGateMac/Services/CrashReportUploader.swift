//
//  CrashReportUploader.swift
//  DataGateMac
//
//  Same ingest contract as Android CrashReportUploader:
//  POST text/plain to `{APIBaseURL}/api/v1/mobile/crash-ingest`.
//

import Foundation
import os

nonisolated(unsafe) private let crashReportLog = Logger(subsystem: "imkolganov.DataGateMac", category: "CrashReport")

nonisolated struct CrashReportUploadConfig: Sendable {
    var ingestURL: URL
    var process: String
    var token: String?
}

nonisolated enum CrashReportUploadDecision: Equatable, Sendable {
    case delete
    case retry
}

nonisolated enum CrashReportUploader {
    static let maxFilesPerLaunch = 30

    static func ingestURL(apiBaseUrl: String) -> URL? {
        URL(string: "\(apiBaseUrl)/api/v1/mobile/crash-ingest")
    }

    static func decision(statusCode: Int, body: Data = Data()) -> CrashReportUploadDecision {
        if (200...299).contains(statusCode) { return .delete }
        // This build's client identity is refused: keep the report for an updated app.
        if statusCode == 400, ClientIdentity.rejectionCode(from: body) != nil { return .retry }
        if statusCode == 400 || statusCode == 413 { return .delete }
        return .retry
    }

    static func makeRequest(
        fileURL: URL,
        body: Data,
        config: CrashReportUploadConfig
    ) -> URLRequest {
        var request = URLRequest(url: config.ingestURL)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(fileURL.lastPathComponent, forHTTPHeaderField: "X-Crash-Filename")
        request.setValue(config.process, forHTTPHeaderField: "X-Crash-Process")
        if let token = config.token, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Crash-Token")
        }
        request.httpBody = body
        request.timeoutInterval = 30
        return request
    }

    static func uploadPending(
        directory: URL,
        session: URLSession,
        config: CrashReportUploadConfig,
        fileManager: FileManager = .default,
        maxFiles: Int = maxFilesPerLaunch
    ) async {
        let files = Array(CrashReportStore.pendingReports(in: directory, fileManager: fileManager).prefix(maxFiles))
        for fileURL in files {
            do {
                let body = try Data(contentsOf: fileURL)
                if body.isEmpty {
                    try fileManager.removeItem(at: fileURL)
                    continue
                }
                let request = makeRequest(fileURL: fileURL, body: body, config: config)
                let (responseBody, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 400, let code = ClientIdentity.rejectionCode(from: responseBody) {
                    // Every other report would be refused too: keep them all for an updated build.
                    crashReportLog.error("Crash ingest refused this build (\(code, privacy: .public)); keeping reports")
                    ClientIdentity.notifyRejected(code)
                    return
                }
                switch decision(statusCode: status, body: responseBody) {
                case .delete:
                    try fileManager.removeItem(at: fileURL)
                    crashReportLog.info("Uploaded crash report \(fileURL.lastPathComponent, privacy: .public) status=\(status)")
                case .retry:
                    crashReportLog.error("Crash ingest retry for \(fileURL.lastPathComponent, privacy: .public) status=\(status)")
                }
            } catch {
                crashReportLog.error("Crash ingest failed for \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
