//
//  ExtensionLogWriter.swift
//  DataGateMacPacketTunnel
//
//  Logs from the system extension via os_log (Console.app). The extension profile does not
//  authorize App Groups, so we do not write to a shared file in the host app container.
//

import os.log

enum ExtensionLogWriter {
    private static let log = Logger(subsystem: "imkolganov.DataGateMac.PacketTunnel", category: "ExtensionLog")

    static func beginNewSession() {
        log.info("[Ext] --- new session ---")
    }

    static func append(_ message: String) {
        log.info("\(message, privacy: .public)")
    }
}
