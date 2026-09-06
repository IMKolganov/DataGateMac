//
//  XrayConfigAssembler.swift
//  DataGateMacPacketTunnel
//
//  Merges libXray share-link outbounds with SOCKS + optional TUN inbound for NE.
//

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
        if ((outbounds[0]["tag"] as? String)?.isEmpty ?? true) {
            var tagged = outbounds[0]
            tagged["tag"] = "proxy"
            outbounds[0] = tagged
        }
        let hasFreedom = outbounds.contains { ($0["protocol"] as? String)?.lowercased() == "freedom" }
        if !hasFreedom {
            outbounds.append([
                "protocol": "freedom",
                "tag": "direct",
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
            ],
        ]
        if tunFileDescriptor != nil {
            inbounds.append([
                "tag": "tun-in",
                "protocol": "tun",
                "settings": [
                    "mtu": 1500,
                ] as [String: Any],
                "sniffing": [
                    "enabled": true,
                    "destOverride": ["http", "tls", "quic"],
                ] as [String: Any],
            ])
        }
        config["inbounds"] = inbounds

        if config["log"] == nil {
            config["log"] = ["loglevel": "warning"]
        }
        if config["dns"] == nil {
            config["dns"] = ["servers": ["1.1.1.1", "8.8.8.8"]]
        }
        if config["routing"] == nil {
            config["routing"] = [
                "domainStrategy": "AsIs",
                "rules": [
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
        }

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
