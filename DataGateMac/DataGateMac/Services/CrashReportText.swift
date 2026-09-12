//
//  CrashReportText.swift
//  DataGateMac
//
//  Windows-style crash file names (`{app}_crash_YYYYMMDD_HHMMSS`) and a text body
//  the backend already accepts from Android (`/api/v1/mobile/crash-ingest`).
//

import Foundation

nonisolated enum CrashReportText {
    static let processId = "imkolganov.DataGateMac"
    static let fileNamePrefix = "DataGateMac_crash_"

    static func fileName(
        processBaseName: String = "DataGateMac",
        at date: Date,
        timeZone: TimeZone
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(
            format: "%04d%02d%02d_%02d%02d%02d",
            c.year ?? 0,
            c.month ?? 0,
            c.day ?? 0,
            c.hour ?? 0,
            c.minute ?? 0,
            c.second ?? 0
        )
        return "\(processBaseName)_crash_\(stamp).txt"
    }

    static func body(
        timestamp: Date,
        process: String = processId,
        appVersion: String,
        osVersion: String,
        arch: String,
        kind: String,
        exceptionName: String? = nil,
        message: String? = nil,
        signalName: String? = nil,
        stack: [String] = []
    ) -> String {
        var lines: [String] = [
            "timestamp_utc=\(iso8601UTC(timestamp))",
            "process=\(process)",
            "app_version=\(appVersion)",
            "os=\(osVersion)",
            "arch=\(arch)",
            "kind=\(kind)",
        ]
        if let exceptionName, !exceptionName.isEmpty {
            lines.append("exception=\(exceptionName)")
        }
        if let signalName, !signalName.isEmpty {
            lines.append("signal=\(signalName)")
        }
        if let message, !message.isEmpty {
            lines.append("message=\(message)")
        }
        if !stack.isEmpty {
            lines.append("stack:")
            lines.append(contentsOf: stack)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Prefix runtime metadata onto a signal-safe stub written by CrashSignalHook.c.
    static func wrapPendingSignal(
        raw: String,
        timestamp: Date,
        appVersion: String,
        osVersion: String,
        arch: String
    ) -> String {
        let header = body(
            timestamp: timestamp,
            appVersion: appVersion,
            osVersion: osVersion,
            arch: arch,
            kind: "fatal",
            message: "uncaught signal (see body)"
        )
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return header
        }
        return header + "\n" + trimmed + "\n"
    }

    static func iso8601UTC(_ date: Date) -> String {
        ISO8601DateFormatter.string(from: date, timeZone: TimeZone(secondsFromGMT: 0)!)
    }
}

private extension ISO8601DateFormatter {
    static func string(from date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
