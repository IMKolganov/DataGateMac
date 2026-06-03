//
//  VpnProfileMigrationPolicyTests.swift
//  DataGateMacTests
//

import XCTest
@testable import DataGateMac

final class VpnProfileMigrationPolicyTests: XCTestCase {
    private let hostId = "imkolganov.DataGateMac"
    private let sysexId = "imkolganov.DataGateMac.PacketTunnel"
    private let appsPath = "/Applications/DataGateMac.app"
    private let derivedPath = "/Users/me/Library/Developer/Xcode/DerivedData/DataGateMac/Build/Products/Debug/DataGateMac.app"

    private func snapshot(
        savedProviderId: String? = sysexId,
        lastPath: String? = appsPath,
        currentPath: String = appsPath,
        hasProfile: Bool = true
    ) -> VpnProfileMigrationPolicy.ProfileSnapshot {
        VpnProfileMigrationPolicy.ProfileSnapshot(
            savedProviderBundleIdentifier: savedProviderId,
            lastRecordedHostAppPath: lastPath,
            currentHostAppPath: currentPath,
            hostAppBundleIdentifier: hostId,
            expectedProviderBundleIdentifier: sysexId,
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
            for: snapshot(lastPath: derivedPath, currentPath: appsPath)
        )
        XCTAssertEqual(reason, "host app path changed (\(derivedPath) -> \(appsPath))")
    }

    func testRecreateReason_staleHostBundleIdentifier() {
        let reason = VpnProfileMigrationPolicy.recreateReason(for: snapshot(savedProviderId: hostId))
        XCTAssertEqual(reason, "providerBundleIdentifier was host app id \(hostId)")
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
