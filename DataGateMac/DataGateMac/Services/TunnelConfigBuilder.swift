//
//  TunnelConfigBuilder.swift
//  DataGateMac
//
//  Builds TunnelConfig from backend (server list + OVPN file), same flow as DataGateWin StartSessionPayloadBuilder.
//

import Foundation
import os

private let log = Logger(subsystem: "imkolganov.DataGateMac", category: "TunnelConfigBuilder")

enum TunnelConfigBuilder {
    /// Builds TunnelConfig using token: servers list → best WSS server → ensure OVPN file → host/port from server.
    /// Returns nil if not authorized, no server, or API errors.
    /// - Parameter onLog: optional callback for step messages (e.g. to show in UI). Called on same context as build().
    static func build(
        token: String,
        installationIdService: InstallationIdService = InstallationIdService(),
        serversClient: OpenVpnServersApiClient = .shared,
        filesClient: OpenVpnFilesApiClient = .shared,
        onLog: ((String) -> Void)? = nil
    ) async -> TunnelConfig? {
        func step(_ msg: String) {
            onLog?(msg)
            log.info("\(msg)")
        }
        step("[Backend] Step 1: get installationId and externalId from JWT...")
        let installationId = installationIdService.getOrCreate()
        guard let externalId = JwtClaimReader.getExternalId(fromJwt: token) else {
            step("[Backend] FAIL: No externalId in JWT")
            log.warning("No externalId in JWT")
            return nil
        }
        step("[Backend] Step 2: fetch server list (get-all-with-status)...")
        let servers: [OpenVpnServerWithStatusDto]
        do {
            servers = try await serversClient.getAllWithStatus(token: token)
            step("[Backend] Step 2: got \(servers.count) server(s)")
        } catch {
            step("[Backend] FAIL: getAllWithStatus - \(error.localizedDescription)")
            log.error("getAllWithStatus failed: \(String(describing: error))")
            return nil
        }

        step("[Backend] Step 3: pick best WSS server...")
        guard let server = pickBestWssServer(servers) else {
            step("[Backend] FAIL: No suitable WSS server (online + isEnableWss)")
            log.warning("No suitable WSS server")
            return nil
        }
        let serverId = server.openVpnServerResponses.openVpnServer.id
        step("[Backend] Step 3: picked server id=\(serverId) \(server.openVpnServerResponses.openVpnServer.serverName)")
        let commonName = "wdg-\(serverId)-\(externalId)-\(installationId)"
        let issuedTo = externalId

        step("[Backend] Step 4: ensure and download OVPN file (download-by-cn / add-with-token)...")
        let fileResponse: DownloadFileResponse
        do {
            fileResponse = try await filesClient.ensureAndDownloadDeviceFile(
                vpnServerId: serverId,
                commonName: commonName,
                externalId: externalId,
                issuedTo: issuedTo,
                token: token
            )
            step("[Backend] Step 4: OVPN file received (\(fileResponse.content?.count ?? 0) bytes)")
        } catch {
            step("[Backend] FAIL: ensureAndDownloadDeviceFile - \(error.localizedDescription)")
            log.error("ensureAndDownloadDeviceFile failed: \(String(describing: error))")
            return nil
        }

        guard let content = fileResponse.content, !content.isEmpty else {
            step("[Backend] FAIL: OVPN content empty")
            log.error("OVPN content empty")
            return nil
        }
        let originalOvpnContent = String(data: content, encoding: .utf8) ?? ""
        guard !originalOvpnContent.isEmpty else {
            step("[Backend] FAIL: OVPN content decode empty")
            return nil
        }
        let listenPort = 18080
        let linkProtocol = TunnelLinkProtocol.fromOvpnConfigContent(originalOvpnContent)
        let ovpnContent = patchOvpnConfigForLocalBridge(originalOvpnContent, listenPort: listenPort, linkProtocol: linkProtocol)
        step("[Backend] Step 4: parsed transport -> \(linkProtocol.rawValue.uppercased()); patched OVPN for 127.0.0.1:\(listenPort)")

        step("[Backend] Step 5: build TunnelConfig from server apiUrl...")
        let apiUrl = server.openVpnServerResponses.openVpnServer.apiUrl
        guard let url = URL(string: apiUrl),
              let host = url.host else {
            step("[Backend] FAIL: Invalid apiUrl: \(apiUrl)")
            log.error("Invalid apiUrl: \(apiUrl)")
            return nil
        }
        let port = url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
        let proxyPath = "/api/proxy?mode=\(linkProtocol.proxyMode)"
        step("[Backend] Step 5: done -> \(host):\(port)\(proxyPath)")

        let displayName = server.openVpnServerResponses.openVpnServer.serverName.trimmingCharacters(in: .whitespacesAndNewlines)

        return TunnelConfig(
            host: host,
            port: port,
            path: proxyPath,
            ovpnContent: ovpnContent,
            listenPort: listenPort,
            verifyServerCert: false,
            linkProtocol: linkProtocol,
            serverDisplayName: displayName.isEmpty ? "Server \(serverId)" : displayName,
            serverId: serverId
        )
    }

    /// Picks best server: online, WSS enabled, then by fewer connected clients.
    private static func pickBestWssServer(_ servers: [OpenVpnServerWithStatusDto]) -> OpenVpnServerWithStatusDto? {
        let candidate = servers.filter { dto in
            let s = dto.openVpnServerResponses.openVpnServer
            return (s.isOnline ?? false) && (s.isEnableWss ?? false)
        }
        return candidate.min(by: { $0.countConnectedClients < $1.countConnectedClients })
    }
}
