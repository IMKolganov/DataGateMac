//
//  JwtClaimReader.swift
//  DataGateMac
//
//  Reads claims from JWT (e.g. externalId, sub) for OVPN add-with-token / issuedTo.
//

import Foundation

enum JwtClaimReader {
    /// Decodes JWT payload (middle part) into a dictionary, if valid.
    static func jwtPayload(from jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        let payloadBase64 = String(parts[1])
        let normalized = payloadBase64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - normalized.count % 4
        let padded = padding < 4 ? normalized + String(repeating: "=", count: padding) : normalized
        guard let data = Data(base64Encoded: padded) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Decodes JWT payload (middle part) and returns string value for the given claim.
    /// Tries "externalId", then "sub", then "nameid" for compatibility with backend.
    static func getExternalId(fromJwt jwt: String) -> String? {
        guard let json = jwtPayload(from: jwt) else { return nil }
        return (json["externalId"] as? String)
            ?? (json["sub"] as? String)
            ?? (json["nameid"] as? String)
    }

    /// Numeric user id for quota APIs when not persisted (e.g. session from older builds).
    static func getUserId(fromJwt jwt: String) -> Int? {
        guard let json = jwtPayload(from: jwt) else { return nil }
        let keys = ["userId", "UserId", "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"]
        for key in keys {
            if let n = json[key] as? Int { return n }
            if let s = json[key] as? String, let n = Int(s) { return n }
        }
        if let s = json["sub"] as? String, let n = Int(s) { return n }
        return nil
    }

    /// HTTPS avatar URL from backend JWT (`avatarUrl`) or Google-style `picture`.
    static func getAvatarUrl(fromJwt jwt: String) -> String? {
        guard let json = jwtPayload(from: jwt) else { return nil }
        let raw = (json["avatarUrl"] as? String)
            ?? (json["AvatarUrl"] as? String)
            ?? (json["picture"] as? String)
        return ProfileImageURL.normalizedString(raw)
    }
}

/// Google / backend profile photos must be HTTPS (same rule as the backend normalizer).
enum ProfileImageURL {
    static func normalizedString(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.count > 2048 {
            value = String(value.prefix(2048))
        }
        guard value.lowercased().hasPrefix("https://") else { return nil }
        return value
    }

    static func parse(_ raw: String?) -> URL? {
        guard let value = normalizedString(raw) else { return nil }
        return URL(string: value)
    }
}
