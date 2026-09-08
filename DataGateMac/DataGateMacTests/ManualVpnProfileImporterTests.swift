//
//  ManualVpnProfileImporterTests.swift
//  DataGateMacTests
//

import XCTest
@testable import DataGateMac

final class ManualVpnProfileImporterTests: XCTestCase {
    func testImportsOpenVpnWithCommentName() throws {
        let ovpn = """
        # Office node
        client
        proto udp
        remote vpn.example.com 1194
        <ca>
        -----BEGIN CERTIFICATE-----
        MIIB
        -----END CERTIFICATE-----
        </ca>
        """
        let draft = try ManualVpnProfileImporter.importPayload(ovpn)
        XCTAssertEqual(draft.kind, .openVpn)
        XCTAssertEqual(draft.displayName, "Office node")
        XCTAssertTrue(draft.payload.contains("remote vpn.example.com 1194"))
        let config = try ManualVpnProfileImporter.makeTunnelConfig(from: profile(from: draft))
        XCTAssertEqual(config.transportMode, .direct)
        XCTAssertEqual(config.host, "vpn.example.com")
        XCTAssertEqual(config.port, 1194)
        XCTAssertEqual(config.linkProtocol, .udp)
        XCTAssertNil(config.serverId)
        XCTAssertNil(config.clientCommonName)
        XCTAssertNil(config.issuedFileName)
        XCTAssertEqual(config.ovpnContent.contains("remote vpn.example.com"), true)
    }

    func testTunnelConfigPicksOvpnFileNameFromComment() throws {
        let ovpn = """
        # backups/cyprus-user.ovpn
        client
        proto udp
        remote vpn.example.com 1194
        """
        let draft = try ManualVpnProfileImporter.importPayload(ovpn)
        let config = try ManualVpnProfileImporter.makeTunnelConfig(from: profile(from: draft))
        XCTAssertEqual(config.issuedFileName, "cyprus-user.ovpn")
    }

    func testRejectsOpenVpnAuthUserPassWithoutEmbeddedCredentials() {
        let ovpn = """
        client
        remote vpn.example.com 443
        auth-user-pass
        """
        XCTAssertThrowsError(try ManualVpnProfileImporter.importPayload(ovpn)) { error in
            XCTAssertEqual(error as? ManualVpnImportError, .ovpnNeedsPassword)
        }
    }

    func testAcceptsOpenVpnWithEmbeddedAuthUserPass() throws {
        let ovpn = """
        client
        remote 10.9.8.7 1194
        <auth-user-pass>
        alice
        secret
        </auth-user-pass>
        """
        let draft = try ManualVpnProfileImporter.importPayload(ovpn)
        XCTAssertEqual(draft.kind, .openVpn)
        XCTAssertEqual(draft.displayName, "10.9.8.7")
    }

    func testImportsVlessUriAndFragmentName() throws {
        let uri = "vless://uuid@10.1.2.3:8443?encryption=none&security=tls&type=tcp#Poland%20node"
        let draft = try ManualVpnProfileImporter.importPayload(uri)
        XCTAssertEqual(draft.kind, .xray)
        XCTAssertEqual(draft.displayName, "Poland node")
        XCTAssertEqual(draft.payload, uri)
        let config = try ManualVpnProfileImporter.makeTunnelConfig(from: profile(from: draft))
        XCTAssertEqual(config.transportMode, .xray)
        XCTAssertEqual(config.host, "10.1.2.3")
        XCTAssertEqual(config.port, 8443)
        XCTAssertEqual(config.xrayShareLink, uri)
        XCTAssertNil(config.serverId)
        XCTAssertNil(config.clientCommonName)
    }

    func testPrefersJsonVlessOverXhttp() throws {
        let payload = """
        {"vless":"vless://uuid@xs1-hel2.datagateapp.com:443?encryption=none&security=tls&type=tcp#hel","vlessXhttp":"vless://uuid@xs1-hel2.datagateapp.com:2053?encryption=none&security=tls&type=xhttp#hel-xhttp"}
        """
        let draft = try ManualVpnProfileImporter.importPayload(payload)
        XCTAssertEqual(draft.kind, .xray)
        XCTAssertEqual(draft.displayName, "hel")
        XCTAssertTrue(draft.payload.contains(":443?"))
        XCTAssertFalse(draft.payload.contains("xhttp"))
    }

    func testFallsBackToJsonVlessXhttp() throws {
        let payload = """
        {"vlessXhttp":"vless://uuid@xs1-hel2.datagateapp.com:2053?encryption=none&security=tls&type=xhttp#hel-xhttp"}
        """
        let draft = try ManualVpnProfileImporter.importPayload(payload)
        XCTAssertEqual(draft.kind, .xray)
        XCTAssertEqual(draft.displayName, "hel-xhttp")
        XCTAssertTrue(draft.payload.contains("type=xhttp"))
    }

    func testPreferredNameOverridesDetectedName() throws {
        let draft = try ManualVpnProfileImporter.importPayload(
            "vless://abc@10.1.2.3:443?type=tcp#from-link",
            preferredName: "  My node  "
        )
        XCTAssertEqual(draft.displayName, "My node")
    }

    func testUsesFileStemWhenNoComment() throws {
        let ovpn = """
        client
        remote edge.example.net 1194
        proto tcp
        """
        let draft = try ManualVpnProfileImporter.importPayload(ovpn, fileName: "Travel-VPN.ovpn")
        XCTAssertEqual(draft.displayName, "Travel-VPN")
    }

    func testRejectsEmptyAndGarbage() {
        XCTAssertThrowsError(try ManualVpnProfileImporter.importPayload("   ")) { error in
            XCTAssertEqual(error as? ManualVpnImportError, .empty)
        }
        XCTAssertThrowsError(try ManualVpnProfileImporter.importPayload("hello world")) { error in
            XCTAssertEqual(error as? ManualVpnImportError, .unrecognized)
        }
        XCTAssertThrowsError(try ManualVpnProfileImporter.importPayload("{\"foo\":\"bar\"}")) { error in
            XCTAssertEqual(error as? ManualVpnImportError, .unrecognized)
        }
    }

    func testPrefersOpenVpnWhenCommentMentionsVless() throws {
        let ovpn = """
        # Office node
        # ignore vless://uuid@10.1.2.3:443?type=tcp#bait
        client
        proto udp
        remote vpn.example.com 1194
        """
        let draft = try ManualVpnProfileImporter.importPayload(ovpn)
        XCTAssertEqual(draft.kind, .openVpn)
        XCTAssertEqual(draft.displayName, "Office node")
        XCTAssertTrue(draft.payload.contains("remote vpn.example.com 1194"))
    }

    func testRejectsPayloadOverSizeLimit() {
        let oversized = String(repeating: "a", count: ManualVpnProfileImporter.maxPayloadUTF8Bytes + 1)
        XCTAssertThrowsError(try ManualVpnProfileImporter.importPayload(oversized)) { error in
            XCTAssertEqual(error as? ManualVpnImportError, .tooLarge)
        }
    }

    func testExpectedKindRejectsMismatch() {
        let ovpn = """
        client
        remote vpn.example.com 1194
        proto udp
        """
        let vless = "vless://abc@10.1.2.3:443?type=tcp#node"
        XCTAssertThrowsError(try ManualVpnProfileImporter.importPayload(vless, expectedKind: .openVpn)) { error in
            XCTAssertEqual(error as? ManualVpnImportError, .expectedOpenVpn)
        }
        XCTAssertThrowsError(try ManualVpnProfileImporter.importPayload(ovpn, expectedKind: .xray)) { error in
            XCTAssertEqual(error as? ManualVpnImportError, .expectedXray)
        }
    }

    func testExpectedKindImportsMatchingPayload() throws {
        let ovpn = """
        client
        remote vpn.example.com 1194
        proto udp
        """
        let ovpnDraft = try ManualVpnProfileImporter.importPayload(ovpn, expectedKind: .openVpn)
        XCTAssertEqual(ovpnDraft.kind, .openVpn)
        let vlessDraft = try ManualVpnProfileImporter.importPayload(
            "vless://abc@10.1.2.3:443?type=tcp#node",
            expectedKind: .xray
        )
        XCTAssertEqual(vlessDraft.kind, .xray)
        XCTAssertEqual(vlessDraft.displayName, "node")
    }
}

final class ManualVpnProfileStoreTests: XCTestCase {
    func testAddListRenameDelete() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ManualVpnProfileStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let draft = try ManualVpnProfileImporter.importPayload(
            "vless://abc@10.1.2.3:443?type=tcp#stored"
        )
        let added = try store.add(draft)
        XCTAssertEqual(try store.list().map(\.id), [added.id])
        XCTAssertEqual(try store.profile(id: added.id).payload.hasPrefix("vless://"), true)

        try store.rename(id: added.id, displayName: "Renamed")
        XCTAssertEqual(try store.profile(id: added.id).displayName, "Renamed")

        let reloaded = ManualVpnProfileStore(directory: dir)
        XCTAssertEqual(try reloaded.profile(id: added.id).displayName, "Renamed")

        try store.delete(id: added.id)
        XCTAssertTrue(try store.list().isEmpty)
        XCTAssertThrowsError(try store.profile(id: added.id))
    }

    func testLoadsIndexWithFractionalAndUnixDates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let payloads = dir.appendingPathComponent("payloads", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: payloads, withIntermediateDirectories: true)

        let id = UUID()
        try "vless://abc@10.1.2.3:443?type=tcp#stored\n"
            .write(to: payloads.appendingPathComponent("\(id.uuidString).vless"), atomically: true, encoding: .utf8)
        let index = """
        {"profiles":[{"createdAt":"2026-09-07T01:02:03.456Z","displayName":"Frac","id":"\(id.uuidString)","kind":"xray","updatedAt":1750000000}]}
        """
        try index.write(to: dir.appendingPathComponent("index.json"), atomically: true, encoding: .utf8)

        let store = ManualVpnProfileStore(directory: dir)
        let listed = try store.list()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].displayName, "Frac")
        XCTAssertEqual(listed[0].kind, .xray)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(listed[0].createdAt, fractional.date(from: "2026-09-07T01:02:03.456Z"))
        XCTAssertEqual(listed[0].updatedAt.timeIntervalSince1970, 1_750_000_000, accuracy: 0.001)
    }

    func testRejectsDuplicatePayload() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ManualVpnProfileStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let draft = try ManualVpnProfileImporter.importPayload(
            "vless://abc@10.1.2.3:443?type=tcp#stored"
        )
        _ = try store.add(draft)
        XCTAssertThrowsError(try store.add(draft)) { error in
            XCTAssertEqual(error as? ManualVpnProfileStoreError, .duplicate)
        }
    }

    func testReplaceCanChangeKind() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ManualVpnProfileStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let vless = try ManualVpnProfileImporter.importPayload(
            "vless://abc@10.1.2.3:443?type=tcp#stored"
        )
        let added = try store.add(vless)
        let ovpn = try ManualVpnProfileImporter.importPayload("""
        client
        remote vpn.example.com 1194
        proto udp
        """)
        let updated = try store.replace(id: added.id, draft: ovpn)
        XCTAssertEqual(updated.id, added.id)
        XCTAssertEqual(updated.kind, .openVpn)
        XCTAssertEqual(try store.profile(id: added.id).kind, .openVpn)
    }
}

private func profile(from draft: ManualVpnProfileDraft) -> ManualVpnProfile {
    ManualVpnProfile(
        id: UUID(),
        displayName: draft.displayName,
        kind: draft.kind,
        payload: draft.payload,
        createdAt: Date(),
        updatedAt: Date()
    )
}
