//
//  FileTokenStore.swift
//  DataGateMac
//

import Foundation

final class FileTokenStore {
    private let path: URL

    init(appName: String = "DataGateMac") {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = root.appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        path = dir.appendingPathComponent("auth.json", isDirectory: false)
    }

    func load() throws -> AuthTokensResponse? {
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AuthTokensResponse.self, from: data)
    }

    func save(_ tokens: AuthTokensResponse) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try? c.encode(date.timeIntervalSince1970)
        }
        let data = try encoder.encode(tokens)
        try data.write(to: path)
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }
}
