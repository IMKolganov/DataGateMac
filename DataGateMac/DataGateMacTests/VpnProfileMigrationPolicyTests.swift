//
//  VpnProfileMigrationPolicyTests.swift
//  DataGateMacTests
//

import XCTest
@testable import DataGateMac

final class VpnProfileMigrationPolicyTests: XCTestCase {
    private static let hostId = "imkolganov.DataGateMac"
    private static let sysexId = "imkolganov.DataGateMac.PacketTunnel"
    private static let appsPath = "/Applications/DataGateMac.app"
    private let derivedPath = "/Users/me/Library/Developer/Xcode/DerivedData/DataGateMac/Build/Products/Debug/DataGateMac.app"

    private func snapshot(
        savedProviderId: String? = "imkolganov.DataGateMac.PacketTunnel",
        lastPath: String? = "/Applications/DataGateMac.app",
        currentPath: String = "/Applications/DataGateMac.app",
        hasProfile: Bool = true
    ) -> VpnProfileMigrationPolicy.ProfileSnapshot {
        VpnProfileMigrationPolicy.ProfileSnapshot(
            savedProviderBundleIdentifier: savedProviderId,
            lastRecordedHostAppPath: lastPath,
            currentHostAppPath: currentPath,
            hostAppBundleIdentifier: Self.hostId,
            expectedProviderBundleIdentifier: Self.sysexId,
            hasExistingProfile: hasProfile
        )
    }

    func testRecreateReason_nilWhenProfileIsCurrent() {
        XCTAssertNil(VpnProfileMigrationPolicy.recreateReason(for: snapshot()))
    }

    func testRecreateReason_firstRunAfterMigrationHelper() {
        let reason = VpnProfileMigrationPolicy.recreateReason(for: snapshot(lastPath: nil))
        XCTAssertEqual(reason, "migrating saved VPN profile to current app install")
    }

    func testRecreateReason_hostAppPathChanged() {
        let reason = VpnProfileMigrationPolicy.recreateReason(
            for: snapshot(lastPath: derivedPath, currentPath: Self.appsPath)
        )
        XCTAssertEqual(reason, "host app path changed (\(derivedPath) -> \(Self.appsPath))")
    }

    func testRecreateReason_staleHostBundleIdentifier() {
        let reason = VpnProfileMigrationPolicy.recreateReason(for: snapshot(savedProviderId: Self.hostId))
        XCTAssertEqual(reason, "providerBundleIdentifier was host app id \(Self.hostId)")
    }

    func testRecreateReason_unexpectedProviderBundleIdentifier() {
        let reason = VpnProfileMigrationPolicy.recreateReason(for: snapshot(savedProviderId: "com.example.tunnel"))
        XCTAssertEqual(reason, "providerBundleIdentifier mismatch (com.example.tunnel)")
    }

    func testRecreateReason_noExistingProfileAndNoRecordedPath_doesNotForceMigration() {
        XCTAssertNil(
            VpnProfileMigrationPolicy.recreateReason(
                for: snapshot(lastPath: nil, hasProfile: false)
            )
        )
    }

    func testIsPacketTunnelUnavailableDisconnect_code14() {
        XCTAssertTrue(
            VpnProfileMigrationPolicy.isPacketTunnelUnavailableDisconnect(
                domain: "NEVPNErrorDomain",
                code: 14
            )
        )
        XCTAssertTrue(
            VpnProfileMigrationPolicy.isPacketTunnelUnavailableDisconnect(
                domain: "NEVPNConnectionErrorDomain",
                code: 14
            )
        )
        XCTAssertFalse(
            VpnProfileMigrationPolicy.isPacketTunnelUnavailableDisconnect(
                domain: "NEVPNErrorDomain",
                code: 5
            )
        )
    }

    func testShouldRetryConnectAfterCode14() {
        XCTAssertTrue(
            VpnProfileMigrationPolicy.shouldRetryConnectAfterCode14(
                tunnelDisconnected: true,
                disconnectDomain: "NEVPNErrorDomain",
                disconnectCode: 14,
                allowRetry: true
            )
        )
        XCTAssertFalse(
            VpnProfileMigrationPolicy.shouldRetryConnectAfterCode14(
                tunnelDisconnected: true,
                disconnectDomain: "NEVPNErrorDomain",
                disconnectCode: 14,
                allowRetry: false
            )
        )
        XCTAssertFalse(
            VpnProfileMigrationPolicy.shouldRetryConnectAfterCode14(
                tunnelDisconnected: false,
                disconnectDomain: "NEVPNErrorDomain",
                disconnectCode: 14,
                allowRetry: true
            )
        )
    }
}

final class OvpnProfileParserTests: XCTestCase {
    func testFirstRemoteUdp() {
        let profile = """
        client
        proto udp
        remote 164.215.15.224 1194
        nobind
        """
        XCTAssertEqual(OvpnProfileParser.firstRemote(in: profile), OvpnRemoteEndpoint(host: "164.215.15.224", port: 1194))
        XCTAssertEqual(TunnelLinkProtocol.fromOvpnConfigContent(profile), .udp)
    }

    func testSkipsLoopbackRemote() {
        let profile = """
        proto tcp-client
        remote 127.0.0.1 18080
        remote vpn.example.com 443
        """
        XCTAssertEqual(OvpnProfileParser.firstRemote(in: profile), OvpnRemoteEndpoint(host: "vpn.example.com", port: 443))
    }

    func testDefaultPortWhenMissing() {
        let profile = "remote 10.1.2.3\n"
        XCTAssertEqual(OvpnProfileParser.firstRemote(in: profile), OvpnRemoteEndpoint(host: "10.1.2.3", port: 1194))
    }
}

final class VpnServerListLabelTests: XCTestCase {
    func testProtocolFromUdpTag() {
        XCTAssertEqual(VpnServerListLabel.linkProtocol(tags: ["udp"], serverName: "Cyprus"), "UDP")
    }

    func testProtocolFromTcpTag() {
        XCTAssertEqual(VpnServerListLabel.linkProtocol(tags: ["tcp"], serverName: "Germany"), "TCP")
    }

    func testProtocolFromServerNameWhenTagsEmpty() {
        XCTAssertEqual(VpnServerListLabel.linkProtocol(tags: [], serverName: "OpenVPN Server (udp)"), "UDP")
        XCTAssertEqual(VpnServerListLabel.linkProtocol(tags: [], serverName: "OpenVPN Server (tcp)"), "TCP")
    }

    func testTagWinsOverName() {
        XCTAssertEqual(VpnServerListLabel.linkProtocol(tags: ["udp"], serverName: "Node (tcp)"), "UDP")
    }
}

final class OpenVpnServerV3DecodeTests: XCTestCase {
    func testDecodesV3VpnServerWithStatusesIncludingUdp() throws {
        let json = """
        {
          "success": true,
          "message": "",
          "data": {
            "vpnServerWithStatuses": [
              {
                "vpnServerResponses": {
                  "vpnServer": {
                    "id": 2,
                    "serverType": 0,
                    "serverName": "Cyprus",
                    "isOnline": true,
                    "isDefault": false,
                    "apiUrl": "https://example.com",
                    "isEnableWss": false,
                    "createDate": "2024-01-01T00:00:00Z",
                    "lastUpdate": "2024-01-01T00:00:00Z",
                    "tags": ["udp"],
                    "isAccessibleForUserQuotaPlan": true
                  }
                },
                "countConnectedClients": 3
              }
            ]
          }
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ApiResponse<OpenVpnServerWithStatusesResponse>.self, from: json)
        let rows = decoded.data?.openVpnServerWithStatuses ?? []
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].openVpnServerResponses.openVpnServer.serverName, "Cyprus")
        XCTAssertEqual(rows[0].openVpnServerResponses.openVpnServer.listedLinkProtocol, "UDP")
        XCTAssertTrue(rows[0].isOpenVpnConnectable)
        XCTAssertEqual(TunnelConfigBuilder.homeRows(from: rows).map(\.displayName), ["Cyprus"])
    }

    func testDecodesLegacyOpenVpnServerWithStatusesKey() throws {
        let json = """
        {
          "success": true,
          "message": "",
          "data": {
            "openVpnServerWithStatuses": [
              {
                "openVpnServerResponses": {
                  "openVpnServer": {
                    "id": 1,
                    "serverName": "Norway 2 tcp",
                    "isOnline": true,
                    "isEnableWss": true,
                    "tags": ["tcp"]
                  }
                },
                "countConnectedClients": 6
              }
            ]
          }
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ApiResponse<OpenVpnServerWithStatusesResponse>.self, from: json)
        let rows = decoded.data?.openVpnServerWithStatuses ?? []
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].openVpnServerResponses.openVpnServer.listedLinkProtocol, "TCP")
    }

    func testHomeRowsSkipXray() throws {
        let json = """
        {
          "success": true,
          "message": "",
          "data": {
            "vpnServerWithStatuses": [
              {
                "vpnServerResponses": {
                  "vpnServer": {
                    "id": 9,
                    "serverType": 1,
                    "serverName": "Xray node",
                    "isOnline": true,
                    "isAccessibleForUserQuotaPlan": true
                  }
                }
              }
            ]
          }
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ApiResponse<OpenVpnServerWithStatusesResponse>.self, from: json)
        let rows = decoded.data?.openVpnServerWithStatuses ?? []
        XCTAssertEqual(rows[0].openVpnServerResponses.openVpnServer.serverType, .xray)
        XCTAssertTrue(TunnelConfigBuilder.homeRows(from: rows).isEmpty)
    }
}
