//
//  ExtensionLogWriter.swift
//  DataGateMacPacketTunnel
//
//  Packet-tunnel logs for Console.app (os_log) and for the host UI via
//  NETunnelProviderSession.sendProviderMessage("logs").
//  A system extension runs as root, so an App Group file is not shared with the user app.
//

import Foundation
import os.log

enum ExtensionLogWriter {
    static let ipcCommandLogs = "logs"

    private static let log = Logger(subsystem: "imkolganov.DataGateMac.PacketTunnel", category: "ExtensionLog")
    private static let lock = NSLock()
    private static var buffer = ExtensionLogBuffer()
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func beginNewSession() {
        lock.lock()
        buffer.reset()
        lock.unlock()
        append("[Ext] --- new session ---")
    }

    static func append(_ message: String) {
        log.info("\(message, privacy: .public)")
        lock.lock()
        let timestamp = isoFormatter.string(from: Date())
        buffer.appendLine("[\(timestamp)] \(message)")
        lock.unlock()
    }

    static func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return buffer.text
    }
}
