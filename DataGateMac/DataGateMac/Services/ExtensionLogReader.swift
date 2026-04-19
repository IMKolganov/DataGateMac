//
//  ExtensionLogReader.swift
//  DataGateMac
//
//  Reads (and optionally clears) the extension log file from the App Group container so the app can show it in UI.
//

import Foundation

enum ExtensionLogReader {
    static let appGroupId = "group.imkolganov.DataGateMac"
    private static let logFileName = "extension.log"

    static func read() -> String {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return "" }
        let fileURL = container.appendingPathComponent(logFileName)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    static func clear() {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return }
        let fileURL = container.appendingPathComponent(logFileName)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
