//
//  LiveTrafficStats.swift
//  DataGateMac
//
//  Shared live-traffic snapshot codec and rate sampler for the Home chart.
//

import Foundation

nonisolated struct LiveTrafficSnapshot: Equatable, Sendable {
    var bytesIn: UInt64
    var bytesOut: UInt64

    static let zero = LiveTrafficSnapshot(bytesIn: 0, bytesOut: 0)

    var hasBytes: Bool { bytesIn > 0 || bytesOut > 0 }
}

/// OpenVPN packet-flow counters beat utun if_data. Never pick "the utun with the most
/// historical bytes" — that is usually iCloud/Control Center, not the VPN.
nonisolated enum LiveTrafficCounterSource {
    static func preferred(flow: LiveTrafficSnapshot, utun: LiveTrafficSnapshot?) -> LiveTrafficSnapshot {
        if flow.hasBytes { return flow }
        return utun ?? .zero
    }
}

nonisolated enum LiveTrafficStatsCodec {
    static func encode(_ snap: LiveTrafficSnapshot) -> Data? {
        let payload: [String: Any] = [
            "in": NSNumber(value: snap.bytesIn),
            "out": NSNumber(value: snap.bytesOut),
        ]
        guard JSONSerialization.isValidJSONObject(payload) else { return nil }
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    static func decode(_ data: Data) -> LiveTrafficSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return LiveTrafficSnapshot(bytesIn: uint64(object["in"]), bytesOut: uint64(object["out"]))
    }

    static func uint64(_ raw: Any?) -> UInt64 {
        if let n = raw as? NSNumber { return n.uint64Value }
        if let i = raw as? Int, i >= 0 { return UInt64(i) }
        if let u = raw as? UInt64 { return u }
        if let d = raw as? Double, d >= 0, d <= Double(UInt64.max) { return UInt64(d) }
        return 0
    }
}

nonisolated struct LiveTrafficHostInterface: Equatable, Sendable {
    var name: String
    var ipv4: String?
    var isPointToPoint: Bool
    var bytesIn: UInt64
    var bytesOut: UInt64

    var isUtun: Bool { name.hasPrefix("utun") }

    var asSnapshot: LiveTrafficSnapshot {
        LiveTrafficSnapshot(bytesIn: bytesIn, bytesOut: bytesOut)
    }

    /// VPN tun has a unicast IPv4 (OpenVPN 10.x, Xray 10.51.x). Skip iCloud utun (IPv6-only).
    static func preferred(from ifaces: [LiveTrafficHostInterface]) -> LiveTrafficHostInterface? {
        let candidates = ifaces.filter { $0.isUtun && $0.isPointToPoint && isTunnelIPv4($0.ipv4) }
        return candidates.max { ($0.bytesIn &+ $0.bytesOut) < ($1.bytesIn &+ $1.bytesOut) }
    }

    static func isTunnelIPv4(_ ip: String?) -> Bool {
        guard let ip, !ip.isEmpty, ip != "127.0.0.1" else { return false }
        if ip.hasPrefix("10.") || ip.hasPrefix("192.168.") || ip.hasPrefix("100.") {
            return true
        }
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 172 && (16...31).contains(parts[1])
    }
}

nonisolated struct LiveTrafficSample: Identifiable, Equatable, Sendable {
    let at: Date
    let downBytesPerSec: Double
    let upBytesPerSec: Double
    var id: Date { at }
}

nonisolated struct LiveTrafficSampler: Equatable, Sendable {
    private(set) var samples: [LiveTrafficSample] = []
    private(set) var bytesIn: UInt64 = 0
    private(set) var bytesOut: UInt64 = 0
    private(set) var downBytesPerSec: Double = 0
    private(set) var upBytesPerSec: Double = 0

    private var lastIn: UInt64?
    private var lastOut: UInt64?
    private var lastAt: Date?
    var maxSamples: Int = 60

    mutating func reset() {
        samples = []
        bytesIn = 0
        bytesOut = 0
        downBytesPerSec = 0
        upBytesPerSec = 0
        lastIn = nil
        lastOut = nil
        lastAt = nil
    }

    mutating func apply(_ snap: LiveTrafficSnapshot, at: Date) {
        bytesIn = snap.bytesIn
        bytesOut = snap.bytesOut
        if let lastIn, let lastOut, let lastAt {
            if snap.bytesIn < lastIn || snap.bytesOut < lastOut {
                downBytesPerSec = 0
                upBytesPerSec = 0
                self.lastIn = snap.bytesIn
                self.lastOut = snap.bytesOut
                self.lastAt = at
                return
            }
            let dt = at.timeIntervalSince(lastAt)
            if dt > 0 {
                downBytesPerSec = Double(snap.bytesIn - lastIn) / dt
                upBytesPerSec = Double(snap.bytesOut - lastOut) / dt
                samples.append(
                    LiveTrafficSample(at: at, downBytesPerSec: downBytesPerSec, upBytesPerSec: upBytesPerSec)
                )
                if samples.count > maxSamples {
                    samples.removeFirst(samples.count - maxSamples)
                }
            }
        }
        lastIn = snap.bytesIn
        lastOut = snap.bytesOut
        lastAt = at
    }
}
