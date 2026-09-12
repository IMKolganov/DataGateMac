//
//  LiveTrafficHostInterfaceStats.swift
//  DataGateMac
//
//  Host-side utun counters so Home traffic works even when the packet-tunnel
//  IPC stats message never arrives (stale system extension, sendProviderMessage nil).
//

import Darwin
import Foundation

enum LiveTrafficHostInterfaceStats {
    static func snapshot() -> LiveTrafficSnapshot? {
        LiveTrafficHostInterface.preferred(from: collect())?.asSnapshot
    }

    static func collect() -> [LiveTrafficHostInterface] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var byName: [String: LiveTrafficHostInterface] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            var row = byName[name] ?? LiveTrafficHostInterface(
                name: name,
                ipv4: nil,
                isPointToPoint: (current.pointee.ifa_flags & UInt32(IFF_POINTOPOINT)) != 0,
                bytesIn: 0,
                bytesOut: 0
            )
            if (current.pointee.ifa_flags & UInt32(IFF_POINTOPOINT)) != 0 {
                row.isPointToPoint = true
            }
            if let addr = current.pointee.ifa_addr {
                if addr.pointee.sa_family == UInt8(AF_LINK), let data = current.pointee.ifa_data {
                    let stats = data.assumingMemoryBound(to: if_data.self).pointee
                    row.bytesIn = UInt64(stats.ifi_ibytes)
                    row.bytesOut = UInt64(stats.ifi_obytes)
                } else if addr.pointee.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        addr,
                        socklen_t(addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        let ip = String(cString: hostname)
                        if row.ipv4 == nil || row.ipv4 == "127.0.0.1" {
                            row.ipv4 = ip
                        }
                    }
                }
            }
            byName[name] = row
            ptr = current.pointee.ifa_next
        }
        return Array(byName.values)
    }
}
