//
//  OvpnProfileParser.swift
//  DataGateMac
//
//  Reads remotes and proto from an issued .ovpn so direct OpenVPN can use
//  the profile as-is (no WSS / 127.0.0.1 rewrite).
//

import Foundation

struct OvpnRemoteEndpoint: Equatable, Sendable {
    let host: String
    let port: Int
}

enum OvpnProfileParser {
    static func firstRemote(in content: String) -> OvpnRemoteEndpoint? {
        for raw in content.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                continue
            }
            if let comment = line.firstIndex(where: { $0 == "#" || $0 == ";" }) {
                line = String(line[..<comment]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count >= 2, tokens[0].lowercased() == "remote" else { continue }
            let host = tokens[1].trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            guard !host.isEmpty, host.lowercased() != "127.0.0.1", host.lowercased() != "localhost" else {
                continue
            }
            var port = 1194
            if tokens.count >= 3, let parsed = Int(tokens[2]), (1...65535).contains(parsed) {
                port = parsed
            }
            return OvpnRemoteEndpoint(host: host, port: port)
        }
        return nil
    }
}
