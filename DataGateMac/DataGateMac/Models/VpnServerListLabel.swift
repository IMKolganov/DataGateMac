//
//  VpnServerListLabel.swift
//  DataGateMac
//
//  UDP/TCP shown in server lists. Protocol comes from backend tags (same as Android).
//

import Foundation

enum VpnServerListLabel {
    static func linkProtocol(tags: [String], serverName: String) -> String? {
        for raw in tags {
            let n = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if n.hasPrefix("udp") { return "UDP" }
            if n.hasPrefix("tcp") { return "TCP" }
        }
        let name = serverName.lowercased()
        if name.contains("udp") { return "UDP" }
        if name.contains("tcp") { return "TCP" }
        return nil
    }
}
