//
//  XrayConfigAssembler.swift
//  DataGateMacPacketTunnel
//
//  Merges libXray share-link outbounds with SOCKS + optional TUN inbound for NE.
//

import Darwin
import Foundation

enum XrayConfigAssembler {
    static let socksListenPort = 10808

    static func makeRuntimeConfig(
        shareConfig: [String: Any],
        tunFileDescriptor: Int32?
    ) throws -> String {
        var config = shareConfig
        var outbounds = (config["outbounds"] as? [[String: Any]]) ?? []
        if outbounds.isEmpty {
            throw XrayConfigError.noOutbounds
        }
        outbounds = outbounds.enumerated().map { index, outbound in
            prepareOutbound(outbound, fallbackTag: index == 0 ? "proxy" : "proxy-\(index)")
        }
        let hasFreedom = outbounds.contains { ($0["protocol"] as? String)?.lowercased() == "freedom" }
        if !hasFreedom {
            outbounds.append([
                "protocol": "freedom",
                "tag": "direct",
            ])
        }
        if !outbounds.contains(where: { ($0["tag"] as? String) == "dns-out" }) {
            outbounds.append([
                "protocol": "dns",
                "tag": "dns-out",
            ])
        }
        config["outbounds"] = outbounds

        var inbounds: [[String: Any]] = [
            [
                "tag": "socks-in",
                "listen": "127.0.0.1",
                "port": socksListenPort,
                "protocol": "socks",
                "settings": [
                    "udp": true,
                    "auth": "noauth",
                ],
                "sniffing": [
                    "enabled": true,
                    "destOverride": ["http", "tls", "quic", "fakedns"],
                ] as [String: Any],
            ],
        ]
        if tunFileDescriptor != nil {
            inbounds.append([
                "tag": "tun-in",
                "protocol": "tun",
                "settings": [
                    "mtu": 1500,
                    "autoOutboundsInterface": "auto",
                ] as [String: Any],
                "sniffing": [
                    "enabled": true,
                    "destOverride": ["http", "tls", "quic", "fakedns"],
                    "metadataOnly": false,
                ] as [String: Any],
            ])
        }
        config["inbounds"] = inbounds

        if config["log"] == nil {
            config["log"] = ["loglevel": "warning"]
        }
        // App DNS is UDP/53 into the tunnel. VLESS/xHTTP often cannot carry UDP, so hijack
        // those queries to FakeDNS and restore the name via sniffing instead.
        config["dns"] = [
            "queryStrategy": "UseIPv4",
            "servers": ["fakedns", "1.1.1.1"],
        ]
        config["fakeDns"] = [
            "ipPool": "198.18.0.0/15",
            "poolSize": 65535,
        ]
        config["routing"] = [
            "domainStrategy": "AsIs",
            "rules": [
                [
                    "type": "field",
                    "port": 53,
                    "network": "udp",
                    "outboundTag": "dns-out",
                ],
                [
                    "type": "field",
                    "ip": ["198.18.0.0/15"],
                    "outboundTag": "proxy",
                ],
                [
                    "type": "field",
                    "outboundTag": "direct",
                    "ip": [
                        "10.0.0.0/8",
                        "127.0.0.0/8",
                        "169.254.0.0/16",
                        "172.16.0.0/12",
                        "192.168.0.0/16",
                    ],
                ],
            ],
        ]

        var env = (config["env"] as? [String: Any]) ?? [:]
        if let tunFileDescriptor {
            env["xray.tun.fd"] = String(tunFileDescriptor)
            env["XRAY_TUN_FD"] = String(tunFileDescriptor)
        }
        if !env.isEmpty {
            config["env"] = env
        }

        let data = try JSONSerialization.data(withJSONObject: config, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw XrayConfigError.jsonEncodeFailed
        }
        return json
    }

    /// libXray stores the share-link remark in `sendThrough`. That field is a bind
    /// address at runtime, so a name like "DataGate+🇵🇱+Poland" must be stripped.
    static func prepareOutbound(_ raw: [String: Any], fallbackTag: String) -> [String: Any] {
        var outbound = raw
        if let sendThrough = outbound["sendThrough"] as? String {
            let trimmed = sendThrough.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !isIpBindAddress(trimmed) {
                outbound.removeValue(forKey: "sendThrough")
            }
        }
        if ((outbound["tag"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            outbound["tag"] = fallbackTag
        }
        return outbound
    }

    static func isIpBindAddress(_ value: String) -> Bool {
        let host = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? value
        guard !host.isEmpty else { return false }
        var addr4 = in_addr()
        if inet_pton(AF_INET, host, &addr4) == 1 {
            return true
        }
        var addr6 = in6_addr()
        return inet_pton(AF_INET6, host, &addr6) == 1
    }
}

enum XrayConfigError: LocalizedError {
    case noOutbounds
    case jsonEncodeFailed

    var errorDescription: String? {
        switch self {
        case .noOutbounds:
            return "Converted Xray share link has no outbounds."
        case .jsonEncodeFailed:
            return "Failed to encode Xray JSON configuration."
        }
    }
}
