//
//  CrashReportStore.swift
//  DataGateMac
//
//  Sandbox cannot write next to /Applications/DataGateMac.app (Windows writes
//  `{exe}_crash_*.dmp` beside the engine). Reports live in Application Support.
//

import Foundation

nonisolated enum CrashReportStore {
    static let pendingSignalFileName = "pending_signal.txt"

    static func directory(fileManager: FileManager = .default) throws -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = root
            .appendingPathComponent("DataGateMac", isDirectory: true)
            .appendingPathComponent("crash", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func pendingSignalURL(fileManager: FileManager = .default) throws -> URL {
        try directory(fileManager: fileManager).appendingPathComponent(pendingSignalFileName)
    }

    @discardableResult
    static func write(
        _ text: String,
        named name: String,
        in directory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let dir = try directory ?? self.directory(fileManager: fileManager)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        let tmp = url.appendingPathExtension("tmp")
        try Data(text.utf8).write(to: tmp, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: tmp, to: url)
        return url
    }

    static func pendingReports(in directory: URL, fileManager: FileManager = .default) -> [URL] {
        let files = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix(CrashReportText.fileNamePrefix)
                    && name.hasSuffix(".txt")
                    && !name.hasSuffix(".tmp")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func promotePendingSignalIfNeeded(
        directory: URL? = nil,
        now: Date = Date(),
        appVersion: String,
        osVersion: String,
        arch: String,
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) {
        guard let dir = try? (directory ?? self.directory(fileManager: fileManager)) else { return }
        let pending = dir.appendingPathComponent(pendingSignalFileName)
        guard fileManager.fileExists(atPath: pending.path) else { return }
        let raw = (try? String(contentsOf: pending, encoding: .utf8)) ?? ""
        defer { try? fileManager.removeItem(at: pending) }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let text = CrashReportText.wrapPendingSignal(
            raw: raw,
            timestamp: now,
            appVersion: appVersion,
            osVersion: osVersion,
            arch: arch
        )
        let name = CrashReportText.fileName(at: now, timeZone: timeZone)
        _ = try? write(text, named: name, in: dir, fileManager: fileManager)
    }
}
