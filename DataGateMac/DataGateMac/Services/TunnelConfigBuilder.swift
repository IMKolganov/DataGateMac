//
//  TunnelConfigBuilder.swift
//  DataGateMac
//
//  Builds TunnelConfig from backend (server list + OVPN file), aligned with DataGate Linux / Win:
//  automatic = best quota-allowed server, online-first, least loaded, round-robin vs last pick;
//  WSS servers use the local TCP↔WebSocket bridge; others use the issued OpenVPN remotes (UDP/TCP).
//

import Foundation
import os

private let log = Logger(subsystem: "imkolganov.DataGateMac", category: "TunnelConfigBuilder")

enum TunnelServerPick: Equatable, Sendable {
    case automatic
    case manual(serverId: Int)
}

enum TunnelConfigBuildError: LocalizedError {
    case noExternalIdInJwt
    case fetchServersFailed(String)
    case noWssServersInPlan
    case noServersInPlan
    case manualServerNotFound(Int)
    case manualServerNotWss(Int)
    case manualServerNotInQuotaPlan(Int)
    case ovpnDownloadFailed(String)
    case ovpnEmpty
    case invalidApiUrl(String)

    var errorDescription: String? {
        switch self {
        case .noExternalIdInJwt:
            return L10n.tr("vpn_build_err_no_external_id", "Could not read your account id from the session token.")
        case .fetchServersFailed(let detail):
            return L10n.trFormat("vpn_build_err_fetch_servers_fmt", "Could not load the server list: %@", detail)
        case .noWssServersInPlan:
            return L10n.tr("vpn_build_err_no_wss", "No WSS-enabled servers are available for your plan.")
        case .noServersInPlan:
            return L10n.tr("vpn_build_err_no_servers", "No servers are available for your plan.")
        case .manualServerNotFound(let id):
            return L10n.trFormat("vpn_build_err_server_not_found_fmt", "Server #%d was not found or is not available.", id)
        case .manualServerNotWss(let id):
            return L10n.trFormat("vpn_build_err_server_no_wss_fmt", "Server #%d does not support WSS transport.", id)
        case .manualServerNotInQuotaPlan(let id):
            return L10n.trFormat("vpn_build_err_server_not_in_plan_fmt", "Server #%d is not included in your quota plan.", id)
        case .ovpnDownloadFailed(let detail):
            return L10n.trFormat("vpn_build_err_ovpn_fmt", "Could not download the VPN profile: %@", detail)
        case .ovpnEmpty:
            return L10n.tr("vpn_build_err_ovpn_empty", "The VPN profile from the server was empty.")
        case .invalidApiUrl(let url):
            return L10n.trFormat("vpn_build_err_bad_api_url_fmt", "Invalid server API URL: %@", url)
        }
    }
}

private enum TunnelServerRotationPrefs {
    static let lastAutoPickedServerId = "imkolganov.DataGateMac.vpnLastAutoPickedServerId"
}

enum TunnelConfigBuilder {
    /// Rows for the Home server picker: quota-allowed servers, sorted by display name.
    static func homeRows(from servers: [OpenVpnServerWithStatusDto]) -> [HomeVpnServerRow] {
        let rows: [HomeVpnServerRow] = servers.compactMap { dto in
            let s = dto.openVpnServerResponses.openVpnServer
            guard dto.isOpenVpnConnectable else { return nil }
            let name = s.serverName.trimmingCharacters(in: .whitespacesAndNewlines)
            let display = name.isEmpty ? L10n.trFormat("vpn_server_numbered_fmt", "Server #%d", s.id) : name
            let clients = max(0, dto.countConnectedClients)
            return HomeVpnServerRow(
                id: s.id,
                displayName: display,
                isOnline: s.isOnline ?? false,
                clientCount: clients,
                usesWss: s.isEnableWss == true,
                protocolLabel: s.listedLinkProtocol
            )
        }
        return rows.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func build(
        token: String,
        serverPick: TunnelServerPick,
        installationIdService: InstallationIdService = InstallationIdService(),
        serversClient: OpenVpnServersApiClient = .shared,
        filesClient: OpenVpnFilesApiClient = .shared,
        onLog: ((String) -> Void)? = nil
    ) async throws -> TunnelConfig {
        func step(_ msg: String) {
            onLog?(msg)
            log.info("\(msg)")
        }

        step("[Backend] Step 1: get installationId and externalId from JWT...")
        let installationId = installationIdService.getOrCreate()
        guard let externalId = JwtClaimReader.getExternalId(fromJwt: token) else {
            step("[Backend] FAIL: No externalId in JWT")
            log.warning("No externalId in JWT")
            throw TunnelConfigBuildError.noExternalIdInJwt
        }

        step("[Backend] Step 2: fetch server list (api/v3/open-vpn-servers/get-all-with-status)...")
        let servers: [OpenVpnServerWithStatusDto]
        do {
            servers = try await serversClient.getAllWithStatus(token: token)
            step("[Backend] Step 2: got \(servers.count) server(s)")
        } catch {
            step("[Backend] FAIL: getAllWithStatus - \(error.localizedDescription)")
            log.error("getAllWithStatus failed: \(String(describing: error))")
            throw TunnelConfigBuildError.fetchServersFailed(error.localizedDescription)
        }

        step("[Backend] Step 3: pick server (\(serverPickDescription(serverPick)))...")
        let server = try pickServer(servers, pick: serverPick, onLog: step)
        let serverId = server.openVpnServerResponses.openVpnServer.id
        step("[Backend] Step 3: using server id=\(serverId) \(server.openVpnServerResponses.openVpnServer.serverName)")

        let commonName = "mdg-\(serverId)-\(externalId)-\(installationId)"
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
            throw TunnelConfigBuildError.ovpnDownloadFailed(error.localizedDescription)
        }

        guard let content = fileResponse.content, !content.isEmpty else {
            step("[Backend] FAIL: OVPN content empty")
            log.error("OVPN content empty")
            throw TunnelConfigBuildError.ovpnEmpty
        }
        let originalOvpnContent = String(data: content, encoding: .utf8) ?? ""
        guard !originalOvpnContent.isEmpty else {
            step("[Backend] FAIL: OVPN content decode empty")
            throw TunnelConfigBuildError.ovpnEmpty
        }
        let usesWss = server.openVpnServerResponses.openVpnServer.isEnableWss == true
        let linkProtocol = TunnelLinkProtocol.fromOvpnConfigContent(originalOvpnContent)
        let listenPort = 18080
        let displayName = server.openVpnServerResponses.openVpnServer.serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverLabel = displayName.isEmpty ? L10n.trFormat("vpn_server_numbered_fmt", "Server #%d", serverId) : displayName

        if usesWss {
            let ovpnContent = patchOvpnConfigForLocalBridge(originalOvpnContent, listenPort: listenPort, linkProtocol: .tcp)
            step("[Backend] Step 5: server isEnableWss=true; WSS bridge + local TCP 127.0.0.1:\(listenPort) (upstream proxy mode=\(linkProtocol.proxyMode))")
            let apiUrl = server.openVpnServerResponses.openVpnServer.apiUrl
            guard let url = URL(string: apiUrl),
                  let host = url.host else {
                step("[Backend] FAIL: Invalid apiUrl: \(apiUrl)")
                log.error("Invalid apiUrl: \(apiUrl)")
                throw TunnelConfigBuildError.invalidApiUrl(apiUrl)
            }
            let port = url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
            let proxyPath = "/api/proxy?mode=\(linkProtocol.proxyMode)"
            step("[Backend] Step 5: WSS -> \(host):\(port)\(proxyPath)")
            return TunnelConfig(
                host: host,
                port: port,
                path: proxyPath,
                ovpnContent: ovpnContent,
                listenPort: listenPort,
                verifyServerCert: false,
                linkProtocol: linkProtocol,
                transportMode: .wss,
                serverDisplayName: serverLabel,
                serverId: serverId
            )
        }

        guard let remote = OvpnProfileParser.firstRemote(in: originalOvpnContent) else {
            step("[Backend] FAIL: issued OVPN has no usable remote (direct OpenVPN)")
            throw TunnelConfigBuildError.ovpnEmpty
        }
        step("[Backend] Step 5: server isEnableWss=false; direct OpenVPN \(remote.host):\(remote.port) proto=\(linkProtocol.rawValue)")
        for line in originalOvpnContent.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let head = trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased() ?? ""
            if ["remote", "proto", "dev", "redirect-gateway"].contains(head) {
                step("[Backend] OVPN \(trimmed)")
            }
        }
        return TunnelConfig(
            host: remote.host,
            port: remote.port,
            path: "/",
            ovpnContent: originalOvpnContent,
            listenPort: listenPort,
            verifyServerCert: false,
            linkProtocol: linkProtocol,
            transportMode: .direct,
            serverDisplayName: serverLabel,
            serverId: serverId
        )
    }

    private static func serverPickDescription(_ pick: TunnelServerPick) -> String {
        switch pick {
        case .automatic: return "automatic"
        case .manual(let id): return "manual id=\(id)"
        }
    }

    private static func pickServer(
        _ servers: [OpenVpnServerWithStatusDto],
        pick: TunnelServerPick,
        onLog: (String) -> Void
    ) throws -> OpenVpnServerWithStatusDto {
        switch pick {
        case .automatic:
            guard let s = pickBestServerWinStyle(servers) else {
                onLog("[Backend] FAIL: No suitable server (online preferred + quota plan)")
                log.warning("No suitable server")
                throw TunnelConfigBuildError.noServersInPlan
            }
            return s
        case .manual(let serverId):
            guard let dto = servers.first(where: { $0.openVpnServerResponses.openVpnServer.id == serverId }) else {
                onLog("[Backend] FAIL: manual server id=\(serverId) not in list")
                throw TunnelConfigBuildError.manualServerNotFound(serverId)
            }
            guard dto.isOpenVpnConnectable else {
                onLog("[Backend] FAIL: manual server id=\(serverId) not connectable (quota, Xray, or disabled)")
                throw TunnelConfigBuildError.manualServerNotInQuotaPlan(serverId)
            }
            return dto
        }
    }

    /// Quota-filtered servers, online first, then fewer connected clients, then round-robin vs last auto pick.
    private static func pickBestServerWinStyle(_ servers: [OpenVpnServerWithStatusDto]) -> OpenVpnServerWithStatusDto? {
        var ranked: [OpenVpnServerWithStatusDto] = servers.filter { dto in
            dto.isOpenVpnConnectable
        }
        guard !ranked.isEmpty else { return nil }

        ranked.sort { a, b in
            let ao = a.openVpnServerResponses.openVpnServer.isOnline ?? false
            let bo = b.openVpnServerResponses.openVpnServer.isOnline ?? false
            if ao != bo { return ao && !bo }
            return a.countConnectedClients < b.countConnectedClients
        }

        var index = 0
        if ranked.count > 1, UserDefaults.standard.object(forKey: TunnelServerRotationPrefs.lastAutoPickedServerId) != nil {
            let lastId = UserDefaults.standard.integer(forKey: TunnelServerRotationPrefs.lastAutoPickedServerId)
            if lastId > 0, let i = ranked.firstIndex(where: { $0.openVpnServerResponses.openVpnServer.id == lastId }) {
                index = (i + 1) % ranked.count
            }
        }
        let chosen = ranked[index]
        let sid = chosen.openVpnServerResponses.openVpnServer.id
        UserDefaults.standard.set(sid, forKey: TunnelServerRotationPrefs.lastAutoPickedServerId)
        return chosen
    }
}
