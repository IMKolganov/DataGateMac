//
//  ExtensionLogWriter.swift
//  DataGateMacPacketTunnel
//
//  Writes log lines to a shared file in the App Group container so the main app can show them in UI.
//

import Foundation

enum ExtensionLogWriter {
    static let appGroupId = "group.imkolganov.DataGateMac"
    private static let logFileName = "extension.log"
    private static let queue = DispatchQueue(label: "ExtensionLogWriter")
    private static let maxLogSizeBytes = 256 * 1024

    static func append(_ message: String) {
        queue.sync {
            let line = "[\(iso8601())] \(message)"
            guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return }
            let fileURL = container.appendingPathComponent(logFileName)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            trimIfNeeded(fileURL: fileURL)
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = (line + "\n").data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        }
    }

    private static func trimIfNeeded(fileURL: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > maxLogSizeBytes,
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        let suffix = String(text.suffix(maxLogSizeBytes / 2))
        try? suffix.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }

    private static func iso8601() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
