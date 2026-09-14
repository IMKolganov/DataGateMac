//
//  LiveTrafficStatsTests.swift
//  DataGateMacTests
//

import XCTest
import NetworkExtension
@testable import DataGateMac

final class LiveTrafficStatsTests: XCTestCase {
    func testCodecRoundTripsCounters() throws {
        let snap = LiveTrafficSnapshot(bytesIn: 12_345, bytesOut: 67)
        let data = try XCTUnwrap(LiveTrafficStatsCodec.encode(snap))
        XCTAssertEqual(LiveTrafficStatsCodec.decode(data), snap)
    }

    func testCodecDecodesNSNumberJSON() throws {
        let data = Data(#"{"in":100,"out":20}"#.utf8)
        XCTAssertEqual(
            LiveTrafficStatsCodec.decode(data),
            LiveTrafficSnapshot(bytesIn: 100, bytesOut: 20)
        )
    }

    func testCodecRejectsGarbage() {
        XCTAssertNil(LiveTrafficStatsCodec.decode(Data("not-json".utf8)))
        XCTAssertNil(LiveTrafficStatsCodec.decode(Data()))
    }

    func testPreferredSourceUsesPacketFlowOverUtun() {
        let flow = LiveTrafficSnapshot(bytesIn: 80, bytesOut: 40)
        let utun = LiveTrafficSnapshot(bytesIn: 9_000_000, bytesOut: 8_000_000)
        XCTAssertEqual(LiveTrafficCounterSource.preferred(flow: flow, utun: utun), flow)
    }

    func testPreferredSourceDoesNotFallBackToUnrelatedUtunWhenFlowIsIdle() {
        let idle = LiveTrafficSnapshot.zero
        XCTAssertEqual(LiveTrafficCounterSource.preferred(flow: idle, utun: nil), .zero)
        let boundUtun = LiveTrafficSnapshot(bytesIn: 512, bytesOut: 128)
        XCTAssertEqual(LiveTrafficCounterSource.preferred(flow: idle, utun: boundUtun), boundUtun)
    }

    func testPreferredUtunSkipsICloudAndPicksOpenVpnTun() {
        let icloud = LiveTrafficHostInterface(
            name: "utun0",
            ipv4: nil,
            isPointToPoint: true,
            bytesIn: 80_000_000,
            bytesOut: 80_000_000
        )
        let vpn = LiveTrafficHostInterface(
            name: "utun4",
            ipv4: "10.50.29.3",
            isPointToPoint: true,
            bytesIn: 5_343_926,
            bytesOut: 22_947_549
        )
        let wifi = LiveTrafficHostInterface(
            name: "en0",
            ipv4: "192.168.1.73",
            isPointToPoint: false,
            bytesIn: 1,
            bytesOut: 1
        )
        let picked = LiveTrafficHostInterface.preferred(from: [icloud, vpn, wifi])
        XCTAssertEqual(picked?.name, "utun4")
        XCTAssertEqual(picked?.asSnapshot.bytesIn, 5_343_926)
    }

    func testTunnelIPv4AcceptsPrivateRangesOnly() {
        XCTAssertTrue(LiveTrafficHostInterface.isTunnelIPv4("10.51.0.2"))
        XCTAssertTrue(LiveTrafficHostInterface.isTunnelIPv4("172.20.0.2"))
        XCTAssertFalse(LiveTrafficHostInterface.isTunnelIPv4("127.0.0.1"))
        XCTAssertFalse(LiveTrafficHostInterface.isTunnelIPv4(nil))
    }

    func testSamplerNeedsTwoSnapshotsBeforeARateSample() {
        var sampler = LiveTrafficSampler()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sampler.apply(LiveTrafficSnapshot(bytesIn: 1_000, bytesOut: 100), at: t0)
        XCTAssertTrue(sampler.samples.isEmpty)
        XCTAssertEqual(sampler.bytesIn, 1_000)

        sampler.apply(LiveTrafficSnapshot(bytesIn: 3_000, bytesOut: 500), at: t0.addingTimeInterval(2))
        XCTAssertEqual(sampler.samples.count, 1)
        XCTAssertEqual(sampler.downBytesPerSec, 1_000, accuracy: 0.01)
        XCTAssertEqual(sampler.upBytesPerSec, 200, accuracy: 0.01)
        XCTAssertEqual(sampler.samples[0].downBytesPerSec, 1_000, accuracy: 0.01)
        XCTAssertEqual(sampler.samples[0].upBytesPerSec, 200, accuracy: 0.01)
    }

    func testSamplerResetsWhenCountersDropInsteadOfStayingEmpty() {
        var sampler = LiveTrafficSampler()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sampler.apply(LiveTrafficSnapshot(bytesIn: 5_000_000, bytesOut: 4_000_000), at: t0)
        sampler.apply(LiveTrafficSnapshot(bytesIn: 5_000_100, bytesOut: 4_000_050), at: t0.addingTimeInterval(1))
        XCTAssertEqual(sampler.samples.count, 1)

        sampler.apply(LiveTrafficSnapshot(bytesIn: 200, bytesOut: 50), at: t0.addingTimeInterval(2))
        XCTAssertEqual(sampler.samples.count, 1)
        XCTAssertEqual(sampler.downBytesPerSec, 0)
        XCTAssertEqual(sampler.bytesIn, 200)

        sampler.apply(LiveTrafficSnapshot(bytesIn: 1_200, bytesOut: 250), at: t0.addingTimeInterval(3))
        XCTAssertEqual(sampler.samples.count, 2)
        XCTAssertEqual(sampler.downBytesPerSec, 1_000, accuracy: 0.01)
        XCTAssertEqual(sampler.upBytesPerSec, 200, accuracy: 0.01)
    }

    func testSamplerCapsHistoryAtMaxSamples() {
        var sampler = LiveTrafficSampler()
        sampler.maxSamples = 3
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<6 {
            sampler.apply(
                LiveTrafficSnapshot(bytesIn: UInt64(i * 100), bytesOut: UInt64(i * 10)),
                at: t0.addingTimeInterval(TimeInterval(i))
            )
        }
        XCTAssertEqual(sampler.samples.count, 3)
        XCTAssertEqual(sampler.samples.last?.downBytesPerSec ?? 0, 100, accuracy: 0.01)
    }

    func testSamplerResetClearsTotalsAndRates() {
        var sampler = LiveTrafficSampler()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        sampler.apply(LiveTrafficSnapshot(bytesIn: 100, bytesOut: 10), at: t0)
        sampler.apply(LiveTrafficSnapshot(bytesIn: 200, bytesOut: 20), at: t0.addingTimeInterval(1))
        sampler.reset()
        XCTAssertTrue(sampler.samples.isEmpty)
        XCTAssertEqual(sampler.bytesIn, 0)
        XCTAssertEqual(sampler.bytesOut, 0)
        XCTAssertEqual(sampler.downBytesPerSec, 0)
        XCTAssertEqual(sampler.upBytesPerSec, 0)
    }

    func testChartFormatsThroughput() {
        let zero = LiveTrafficChart.formatRate(0)
        XCTAssertTrue(zero.contains("/"), zero)
        XCTAssertFalse(zero.isEmpty)
        let kilo = LiveTrafficChart.formatRate(1024)
        XCTAssertTrue(kilo.contains("/"), kilo)
        XCTAssertFalse(LiveTrafficChart.formatBytes(2048).isEmpty)
    }
}

final class EngineLogDisplayTests: XCTestCase {
    func testCombinedShowsHostAndExtension() {
        let text = EngineLogDisplay.combined(
            hostLog: "[host] start",
            extensionLog: "[ext] bridge up",
            separator: "--- Extension ---",
            emptyExtensionPlaceholder: "(empty)"
        )
        XCTAssertTrue(text.contains("[host] start"))
        XCTAssertTrue(text.contains("--- Extension ---"))
        XCTAssertTrue(text.contains("[ext] bridge up"))
        XCTAssertFalse(text.contains("(empty)"))
    }

    func testCombinedKeepsPlaceholderUntilExtensionLogsArrive() {
        let text = EngineLogDisplay.combined(
            hostLog: "[host] start",
            extensionLog: "",
            separator: "--- Extension ---",
            emptyExtensionPlaceholder: "(waiting)"
        )
        XCTAssertTrue(text.contains("--- Extension ---"))
        XCTAssertTrue(text.contains("(waiting)"))
    }

    func testCombinedUsesExtensionOnlyWhenHostLogIsEmpty() {
        let text = EngineLogDisplay.combined(
            hostLog: "  \n",
            extensionLog: "[ext] only",
            separator: "--- Extension ---",
            emptyExtensionPlaceholder: "(waiting)"
        )
        XCTAssertEqual(text, "[ext] only")
    }
}

final class ExtensionLogBufferTests: XCTestCase {
    func testAppendSnapshotAndReset() {
        var buffer = ExtensionLogBuffer()
        buffer.appendLine("[t] one")
        buffer.appendLine("[t] two")
        XCTAssertEqual(buffer.text, "[t] one\n[t] two")
        buffer.reset()
        XCTAssertEqual(buffer.text, "")
    }

    func testDropOldestCompleteLinesKeepsTrailingLines() {
        let stored = "aaaa\nbbbb\ncccc"
        let clipped = ExtensionLogBuffer.dropOldestCompleteLines(stored, keepingLast: 9)
        XCTAssertFalse(clipped.hasPrefix("aa"))
        XCTAssertTrue(clipped.contains("cccc"))
        XCTAssertFalse(clipped.hasPrefix("\n"))
    }

    func testBufferTruncatesAtLineBoundary() {
        var buffer = ExtensionLogBuffer()
        buffer.maxCharacters = 20
        buffer.appendLine("1111111111")
        buffer.appendLine("2222222222")
        buffer.appendLine("3333333333")
        XCTAssertLessThanOrEqual(buffer.text.count, 20)
        XCTAssertTrue(buffer.text.contains("3333333333"))
        XCTAssertFalse(buffer.text.contains("1111111111"))
    }
}

final class ExtensionLogConnectFailureTests: XCTestCase {
    func testWarnsWhenConnectingDropsWithEmptyEngineLog() {
        XCTAssertTrue(
            ExtensionLogConnectFailure.shouldWarnMissingEngineLog(
                previousStatus: .connecting,
                currentStatus: .disconnected,
                extensionLog: ""
            )
        )
    }

    func testDoesNotWarnWhenExtensionLogsArrived() {
        XCTAssertFalse(
            ExtensionLogConnectFailure.shouldWarnMissingEngineLog(
                previousStatus: .connecting,
                currentStatus: .disconnected,
                extensionLog: "[Ext] startTunnel entered"
            )
        )
    }

    func testDoesNotWarnOnUserDisconnectFromConnected() {
        XCTAssertFalse(
            ExtensionLogConnectFailure.shouldWarnMissingEngineLog(
                previousStatus: .connected,
                currentStatus: .disconnected,
                extensionLog: ""
            )
        )
    }
}
