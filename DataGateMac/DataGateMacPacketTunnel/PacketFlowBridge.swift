//
//  PacketFlowBridge.swift
//  DataGateMacPacketTunnel
//
//  Reads packets from NEPacketTunnelFlow and exposes them for OpenVPN; accepts packets from OpenVPN and writes to packetFlow.
//  When ovpn3 is linked: onPacketFromTun is called from the read loop → feed to OpenVPN; openvpn calls writePacketsToTun → we call packetFlow.writePackets.
//

import NetworkExtension
import os.log

/// Bridge between NEPacketTunnelFlow and OpenVPN (when integrated). Runs read loop; provides writePacketsToTun for OpenVPN output.
final class PacketFlowBridge {
    private let packetFlow: NEPacketTunnelFlow
    private let log: Logger
    /// Called for each packet read from the TUN (to be passed to OpenVPN). Set by OpenVPN runner when step 2 is implemented.
    var onPacketFromTun: ((Data) -> Void)?
    private var isStopped = false
    private let queue = DispatchQueue(label: "PacketFlowBridge.read")

    init(packetFlow: NEPacketTunnelFlow, log: Logger) {
        self.packetFlow = packetFlow
        self.log = log
    }

    /// Start reading packets from the tunnel. Each packet is passed to onPacketFromTun (or dropped if nil).
    func startReadLoop() {
        ExtensionLogWriter.append("[PacketFlowBridge] startReadLoop: reading from NEPacketTunnelFlow (handlerInstalled=\(onPacketFromTun != nil))")
        queue.async { [weak self] in
            self?.readLoop()
        }
    }

    /// Stop the bridge (stops scheduling new reads).
    func stop() {
        isStopped = true
    }

    /// Write packets to the TUN. Call from OpenVPN when it has decrypted packets to inject.
    func writePacketsToTun(_ packets: [Data], protocols: [NSNumber]) {
        guard !packets.isEmpty, !isStopped else { return }
        packetFlow.writePackets(packets, withProtocols: protocols)
    }

    private func readLoop() {
        guard !isStopped else { return }
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self, !self.isStopped else { return }
            if let handler = self.onPacketFromTun {
                for packet in packets { handler(packet) }
            }
            self.queue.async { self.readLoop() }
        }
    }
}
