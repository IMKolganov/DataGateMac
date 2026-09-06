//
//  ManualVpnProfileStore.swift
//  DataGateMac
//
//  Index + payload files under Application Support (mode 0600).
//

import Foundation

enum ManualVpnProfileStoreError: LocalizedError {
    case profileMissing
    case emptyName

    var errorDescription: String? {
        switch self {
        case .profileMissing:
            return L10n.tr("profiles_err_missing", "That local profile is no longer on disk.")
        case .emptyName:
            return L10n.tr("profiles_err_empty_name", "Enter a profile name.")
        }
    }
}

final class ManualVpnProfileStore {
    static let shared = ManualVpnProfileStore()

    private let directory: URL
    private let payloadsDirectory: URL
    private let indexURL: URL
    private let fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = root
                .appendingPathComponent("DataGateMac", isDirectory: true)
                .appendingPathComponent("ManualProfiles", isDirectory: true)
        }
        payloadsDirectory = self.directory.appendingPathComponent("payloads", isDirectory: true)
        indexURL = self.directory.appendingPathComponent("index.json", isDirectory: false)
        try? ensureDirectories()
    }

    func list() throws -> [ManualVpnProfile] {
        try ensureDirectories()
        let index = try loadIndex()
        var result: [ManualVpnProfile] = []
        result.reserveCapacity(index.profiles.count)
        for record in index.profiles {
            let payload = (try? String(contentsOf: payloadURL(for: record), encoding: .utf8)) ?? ""
            result.append(ManualVpnProfile(
                id: record.id,
                displayName: record.displayName,
                kind: record.kind,
                payload: payload,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            ))
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    func profile(id: UUID) throws -> ManualVpnProfile {
        guard let match = try list().first(where: { $0.id == id }) else {
            throw ManualVpnProfileStoreError.profileMissing
        }
        guard !match.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ManualVpnProfileStoreError.profileMissing
        }
        return match
    }

    @discardableResult
    func add(_ draft: ManualVpnProfileDraft) throws -> ManualVpnProfile {
        try ensureDirectories()
        let now = Date()
        let id = UUID()
        let record = IndexRecord(
            id: id,
            displayName: try sanitizedName(draft.displayName),
            kind: draft.kind,
            createdAt: now,
            updatedAt: now
        )
        try writePayload(draft.payload, for: record)
        var index = try loadIndex()
        index.profiles.append(record)
        do {
            try saveIndex(index)
        } catch {
            try? fileManager.removeItem(at: payloadURL(for: record))
            throw error
        }
        return ManualVpnProfile(
            id: id,
            displayName: record.displayName,
            kind: record.kind,
            payload: draft.payload,
            createdAt: now,
            updatedAt: now
        )
    }

    func rename(id: UUID, displayName: String) throws {
        let name = try {
            let trimmed = ManualVpnProfileImporter.sanitizeDisplayName(displayName)
            guard let trimmed else { throw ManualVpnProfileStoreError.emptyName }
            return trimmed
        }()
        var index = try loadIndex()
        guard let idx = index.profiles.firstIndex(where: { $0.id == id }) else {
            throw ManualVpnProfileStoreError.profileMissing
        }
        index.profiles[idx].displayName = name
        index.profiles[idx].updatedAt = Date()
        try saveIndex(index)
    }

    func delete(id: UUID) throws {
        var index = try loadIndex()
        guard let record = index.profiles.first(where: { $0.id == id }) else {
            throw ManualVpnProfileStoreError.profileMissing
        }
        index.profiles.removeAll { $0.id == id }
        try saveIndex(index)
        let url = payloadURL(for: record)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func sanitizedName(_ raw: String) throws -> String {
        guard let name = ManualVpnProfileImporter.sanitizeDisplayName(raw) else {
            throw ManualVpnProfileStoreError.emptyName
        }
        return name
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: payloadsDirectory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: payloadsDirectory.path)
    }

    private func payloadURL(for record: IndexRecord) -> URL {
        payloadsDirectory.appendingPathComponent(
            "\(record.id.uuidString).\(record.kind.payloadFileExtension)",
            isDirectory: false
        )
    }

    private func writePayload(_ payload: String, for record: IndexRecord) throws {
        let url = payloadURL(for: record)
        guard let data = payload.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func loadIndex() throws -> IndexFile {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return IndexFile(profiles: [])
        }
        let data = try Data(contentsOf: indexURL)
        if data.isEmpty {
            return IndexFile(profiles: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(IndexFile.self, from: data)
    }

    private func saveIndex(_ index: IndexFile) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(index)
        try data.write(to: indexURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
    }

    private struct IndexFile: Codable {
        var profiles: [IndexRecord]
    }

    private struct IndexRecord: Codable {
        var id: UUID
        var displayName: String
        var kind: ManualVpnProfileKind
        var createdAt: Date
        var updatedAt: Date
    }
}
