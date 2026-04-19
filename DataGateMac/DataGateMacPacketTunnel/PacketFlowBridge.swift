//
//  PacketFlowBridge.swift
//  DataGateMacPacketTunnel
//
//  Reads packets from NEPacketTunnelFlow and forwards them to the VPN engine; accepts engine output and writes to packetFlow.
//  When the engine is linked: onPacketFromTun is called from the read loop → inject; the engine calls writePacketsToTun → packetFlow.writePackets.
//

import NetworkExtension
import os.log

/// Bridge between NEPacketTunnelFlow and the VPN engine. Runs read loop; provides writePacketsToTun for decrypted outbound packets.
final class PacketFlowBridge {
    private let packetFlow: NEPacketTunnelFlow
    private let log: Logger
    /// Called for each packet read from the TUN (to be passed to the VPN engine). Set by the runner when integrated.
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

    /// Write packets to the TUN. Call from the VPN engine when it has decrypted packets to inject.
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
