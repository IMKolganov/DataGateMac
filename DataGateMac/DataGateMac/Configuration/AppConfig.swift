//
//  AppConfig.swift
//  DataGateMac
//
//  Loads API base URL, Google OAuth client ID, redirect port.
//  Set in Info.plist or Config.plist (from Config.example.plist).
//

import Foundation

struct AppConfig {
    let apiBaseUrl: String
    let googleClientId: String
    let redirectPort: Int

    static func load() throws -> AppConfig {
        let dict: [String: Any]
        if let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let data = FileManager.default.contents(atPath: configPath),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            dict = plist
        } else if let info = Bundle.main.infoDictionary {
            dict = info
        } else {
            throw ConfigError.missing
        }

        guard let baseUrl = dict["APIBaseURL"] as? String, !baseUrl.isEmpty else {
            throw ConfigError.missingApiBaseUrl
        }
        guard let clientId = dict["GIDClientID"] as? String, !clientId.isEmpty else {
            throw ConfigError.missingGoogleClientId
        }
        let port = (dict["RedirectPort"] as? Int) ?? 51723
        guard port > 0, port <= 65535 else {
            throw ConfigError.invalidRedirectPort
        }

        return AppConfig(
            apiBaseUrl: baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            googleClientId: clientId,
            redirectPort: port
        )
    }

    enum ConfigError: LocalizedError {
        case missing
        case missingApiBaseUrl
        case missingGoogleClientId
        case invalidRedirectPort

        var errorDescription: String? {
            switch self {
            case .missing: return "Config not found. Add Config.plist (from Config.example.plist) with APIBaseURL and GIDClientID."
            case .missingApiBaseUrl: return "APIBaseURL is missing in config."
            case .missingGoogleClientId: return "GIDClientID (Google OAuth client ID) is missing in config."
            case .invalidRedirectPort: return "RedirectPort must be between 1 and 65535."
            }
        }
    }
}
