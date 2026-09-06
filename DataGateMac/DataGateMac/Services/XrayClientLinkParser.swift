//
//  XrayClientLinkParser.swift
//  DataGateMac
//
//  Extracts a VLESS URI and remote host/port from DataGate Xray client-link payloads
//  (plain vless://, or JSON { vless, vlessXhttp } — same as the dashboard).
//

import Foundation

enum XrayClientLinkParser {
    static func extractVlessUri(fromRawContent content: String) -> String? {
        let decoded = decodeMaybeBase64(content)
        if decoded.isEmpty { return nil }

        for line in decoded.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("vless://") {
                return trimmed
            }
        }

        if let data = decoded.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let primary = firstVlessField(object, keys: ["vless", "Vless"]) {
                return primary
            }
            if let xhttp = firstVlessField(object, keys: ["vlessXhttp", "VlessXhttp"]) {
                return xhttp
            }
        }

        if let match = decoded.range(of: #"vless://[^\s"'`]+"#, options: .regularExpression) {
            return String(decoded[match])
        }
        return nil
    }

    static func remote(fromVless uri: String) -> (host: String, port: Int)? {
        guard let url = URL(string: uri.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty else {
            return nil
        }
        let port = url.port ?? 443
        return (host, port)
    }

    /// Share-link remark (`#fragment`), used as a local profile display name.
    static func displayName(fromVless uri: String) -> String? {
        guard let url = URL(string: uri.trimmingCharacters(in: .whitespacesAndNewlines)),
              let rawFragment = url.fragment, !rawFragment.isEmpty else {
            return nil
        }
        let fragment = (rawFragment.removingPercentEncoding ?? rawFragment)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fragment.isEmpty ? nil : fragment
    }

    private static func firstVlessField(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.lowercased().hasPrefix("vless://") {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func decodeMaybeBase64(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.lowercased().hasPrefix("vless://") || trimmed.hasPrefix("{") {
            return trimmed
        }
        if let data = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]),
           let text = String(data: data, encoding: .utf8) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}
