//
//  ManualVpnProfileImporter.swift
//  DataGateMac
//
//  Turns pasted text or a file into a local OpenVPN or VLESS profile.
//

import Foundation

enum ManualVpnImportError: LocalizedError, Equatable {
    case empty
    case unrecognized
    case ovpnNeedsPassword
    case ovpnNoRemote
    case xrayNoHost
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .empty:
            return L10n.tr("profiles_err_empty", "Paste an OpenVPN profile or a VLESS link first.")
        case .unrecognized:
            return L10n.tr(
                "profiles_err_unrecognized",
                "Could not recognize this as an OpenVPN profile or a VLESS link."
            )
        case .ovpnNeedsPassword:
            return L10n.tr(
                "profiles_err_ovpn_password",
                "This OpenVPN profile asks for a username and password. Embedded credentials are required; interactive login is not supported yet."
            )
        case .ovpnNoRemote:
            return L10n.tr(
                "profiles_err_ovpn_no_remote",
                "This OpenVPN profile has no usable remote host."
            )
        case .xrayNoHost:
            return L10n.tr(
                "profiles_err_xray_no_host",
                "Could not read host and port from this VLESS link."
            )
        case .tooLarge:
            return L10n.tr(
                "profiles_err_too_large",
                "This profile is too large to import (maximum 512 KB)."
            )
        }
    }
}

enum ManualVpnProfileImporter {
    static let maxPayloadUTF8Bytes = 512 * 1024

    static func importPayload(
        _ raw: String,
        preferredName: String? = nil,
        fileName: String? = nil
    ) throws -> ManualVpnProfileDraft {
        let content = stripBOM(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw ManualVpnImportError.empty }
        guard content.utf8.count <= maxPayloadUTF8Bytes else { throw ManualVpnImportError.tooLarge }

        // OpenVPN first: a comment or cert blob may contain the substring vless://.
        if looksLikeOpenVpn(content) {
            if requiresInteractiveOpenVpnAuth(content) {
                throw ManualVpnImportError.ovpnNeedsPassword
            }
            guard let remote = OvpnProfileParser.firstRemote(in: content) else {
                throw ManualVpnImportError.ovpnNoRemote
            }
            let suggested = openVpnCommentName(content)
                ?? fileStem(fileName)
                ?? remote.host
            return ManualVpnProfileDraft(
                displayName: resolvedDisplayName(
                    preferredName: preferredName,
                    suggested: suggested,
                    fallback: L10n.tr("profiles_default_openvpn", "OpenVPN profile")
                ),
                kind: .openVpn,
                payload: content + (content.hasSuffix("\n") ? "" : "\n")
            )
        }

        if let vless = XrayClientLinkParser.extractVlessUri(fromRawContent: content) {
            guard let remote = XrayClientLinkParser.remote(fromVless: vless) else {
                throw ManualVpnImportError.xrayNoHost
            }
            let suggested = XrayClientLinkParser.displayName(fromVless: vless)
                ?? fileStem(fileName)
                ?? remote.host
            return ManualVpnProfileDraft(
                displayName: resolvedDisplayName(
                    preferredName: preferredName,
                    suggested: suggested,
                    fallback: L10n.tr("profiles_default_xray", "VLESS profile")
                ),
                kind: .xray,
                payload: vless
            )
        }

        throw ManualVpnImportError.unrecognized
    }

    static func makeTunnelConfig(from profile: ManualVpnProfile) throws -> TunnelConfig {
        switch profile.kind {
        case .openVpn:
            if requiresInteractiveOpenVpnAuth(profile.payload) {
                throw ManualVpnImportError.ovpnNeedsPassword
            }
            guard let remote = OvpnProfileParser.firstRemote(in: profile.payload) else {
                throw ManualVpnImportError.ovpnNoRemote
            }
            let linkProtocol = TunnelLinkProtocol.fromOvpnConfigContent(profile.payload)
            return TunnelConfig(
                host: remote.host,
                port: remote.port,
                path: "/",
                ovpnContent: profile.payload,
                xrayShareLink: "",
                listenPort: 18080,
                verifyServerCert: false,
                linkProtocol: linkProtocol,
                transportMode: .direct,
                serverDisplayName: profile.displayName,
                serverId: nil,
                manualProfileId: profile.id.uuidString
            )
        case .xray:
            guard let vless = XrayClientLinkParser.extractVlessUri(fromRawContent: profile.payload) else {
                throw ManualVpnImportError.unrecognized
            }
            guard let remote = XrayClientLinkParser.remote(fromVless: vless) else {
                throw ManualVpnImportError.xrayNoHost
            }
            return TunnelConfig(
                host: remote.host,
                port: remote.port,
                path: "/",
                ovpnContent: "",
                xrayShareLink: vless,
                listenPort: 18080,
                verifyServerCert: false,
                linkProtocol: .tcp,
                transportMode: .xray,
                serverDisplayName: profile.displayName,
                serverId: nil,
                manualProfileId: profile.id.uuidString
            )
        }
    }

    static func looksLikeOpenVpn(_ content: String) -> Bool {
        var hasMarker = false
        for raw in content.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
            var line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                continue
            }
            if let comment = line.firstIndex(where: { $0 == "#" || $0 == ";" }) {
                line = String(line[..<comment]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let lowered = line.lowercased()
            if lowered == "client" || lowered.hasPrefix("client ") {
                hasMarker = true
            } else if lowered.hasPrefix("dev ") || lowered == "dev" {
                hasMarker = true
            } else if lowered.hasPrefix("proto ") {
                hasMarker = true
            } else if lowered.hasPrefix("<ca")
                || lowered.hasPrefix("<cert")
                || lowered.hasPrefix("<key")
                || lowered.hasPrefix("<tls-")
            {
                hasMarker = true
            }
        }
        return hasMarker && OvpnProfileParser.firstRemote(in: content) != nil
    }

    static func requiresInteractiveOpenVpnAuth(_ content: String) -> Bool {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        if let embedded = embeddedAuthUserPass(in: normalized) {
            let parts = embedded.split(whereSeparator: \.isNewline).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            return parts.count < 2
        }
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                continue
            }
            if let comment = line.firstIndex(where: { $0 == "#" || $0 == ";" }) {
                line = String(line[..<comment]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let lowered = line.lowercased()
            guard lowered.hasPrefix("auth-user-pass") else { continue }
            return true
        }
        return false
    }

    static func openVpnCommentName(_ content: String) -> String? {
        for raw in content.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
            let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("#") || line.hasPrefix(";") else { continue }
            let comment = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !comment.isEmpty else { continue }
            if comment.hasPrefix("-----") { continue }
            return sanitizeDisplayName(comment)
        }
        return nil
    }

    static func sanitizeDisplayName(_ raw: String) -> String? {
        let collapsed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= 120 { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 120)
        return String(collapsed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolvedDisplayName(
        preferredName: String?,
        suggested: String?,
        fallback: String
    ) -> String {
        sanitizeDisplayName(preferredName ?? "")
            ?? sanitizeDisplayName(suggested ?? "")
            ?? fallback
    }

    private static func fileStem(_ fileName: String?) -> String? {
        guard let fileName, !fileName.isEmpty else { return nil }
        let url = URL(fileURLWithPath: fileName)
        let stem = url.deletingPathExtension().lastPathComponent
        return sanitizeDisplayName(stem)
    }

    private static func stripBOM(_ raw: String) -> String {
        if raw.first == "\u{FEFF}" {
            return String(raw.dropFirst())
        }
        return raw
    }

    private static func embeddedAuthUserPass(in content: String) -> String? {
        guard let start = content.range(of: "<auth-user-pass>", options: .caseInsensitive),
              let end = content.range(of: "</auth-user-pass>", options: .caseInsensitive, range: start.upperBound..<content.endIndex) else {
            return nil
        }
        return String(content[start.upperBound..<end.lowerBound])
    }

    static func readTextFile(at url: URL) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? NSNumber, size.intValue > maxPayloadUTF8Bytes {
            throw ManualVpnImportError.tooLarge
        }
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            return latin1
        }
        throw ManualVpnImportError.unrecognized
    }
}
