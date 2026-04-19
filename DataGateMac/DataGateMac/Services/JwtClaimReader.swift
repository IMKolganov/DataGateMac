//
//  JwtClaimReader.swift
//  DataGateMac
//
//  Reads claims from JWT (e.g. externalId, sub) for OVPN add-with-token / issuedTo.
//

import Foundation

enum JwtClaimReader {
    /// Decodes JWT payload (middle part) and returns string value for the given claim.
    /// Tries "externalId", then "sub", then "nameid" for compatibility with backend.
    static func getExternalId(fromJwt jwt: String) -> String? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        let payloadBase64 = String(parts[1])
        let normalized = payloadBase64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - normalized.count % 4
        let padded = padding < 4 ? normalized + String(repeating: "=", count: padding) : normalized
        guard let data = Data(base64Encoded: padded) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["externalId"] as? String)
            ?? (json["sub"] as? String)
            ?? (json["nameid"] as? String)
    }
}
