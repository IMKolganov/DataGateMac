//
//  InstallationIdService.swift
//  DataGateMac
//
//  Persists installation ID (same role as DataGateWin). Used for CN: wdg-{serverId}-{externalId}-{installationId}.
//

import Foundation

final class InstallationIdService {
    private static let key = "installationId"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns existing installation ID or generates and saves a new random base64url string.
    func getOrCreate() -> String {
        if let existing = defaults.string(forKey: Self.key), !existing.isEmpty {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let base64 = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        defaults.set(base64, forKey: Self.key)
        return base64
    }
}
