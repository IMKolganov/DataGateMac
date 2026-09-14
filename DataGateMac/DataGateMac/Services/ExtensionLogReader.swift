//
//  ExtensionLogReader.swift
//  DataGateMac
//
//  Host-side engine log helpers. Packet-tunnel lines come from IPC
//  (`sendProviderMessage("logs")`), not from an App Group file (sysex runs as root).
//

import Foundation
import NetworkExtension

enum ExtensionLogReader {
    static let appGroupId = "group.imkolganov.DataGateMac"
    static let ipcCommandLogs = "logs"
}

enum EngineLogDisplay {
    static func combined(hostLog: String, extensionLog: String, separator: String, emptyExtensionPlaceholder: String) -> String {
        let extensionSection = extensionLog.isEmpty ? emptyExtensionPlaceholder : extensionLog
        let host = hostLog.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty {
            return extensionSection
        }
        return host + "\n\n" + separator + "\n" + extensionSection
    }
}

enum ExtensionLogConnectFailure {
    /// Warn only after a failed Connecting transition, and only if the packet-tunnel log is still empty.
    static func shouldWarnMissingEngineLog(
        previousStatus: NEVPNStatus,
        currentStatus: NEVPNStatus,
        extensionLog: String
    ) -> Bool {
        previousStatus == .connecting
            && (currentStatus == .disconnected || currentStatus == .invalid)
            && extensionLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
