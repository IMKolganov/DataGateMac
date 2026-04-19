//
//  VpnDiagnostics.swift
//  DataGateMac
//
//  Runtime checks to narrow down NEVPN code 14 (plugin not loaded): embedded appex, plist IDs, App Group.
//

import Foundation

enum TunnelConstants {
    /// Must match the packet tunnel target Product Bundle Identifier in Xcode.
    static let packetTunnelBundleIdentifier = "imkolganov.DataGateMac.PacketTunnel"
}

/// Host app install path vs DerivedData (Launch Services / plugin registration).
enum AppBundleLocation {
    /// Running from `/Applications` or `~/Applications`, not from Xcode DerivedData.
    static var isStandardApplicationsInstall: Bool {
        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let parentURL = bundleURL.deletingLastPathComponent()
        let systemAppsURL = URL(fileURLWithPath: "/Applications", isDirectory: true).standardizedFileURL
        let userAppsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return parentURL == systemAppsURL || parentURL == userAppsURL
    }
}

enum VpnDiagnostics {
    private static let expectedExtensionPoint = "com.apple.networkextension.packet-tunnel"

    /// Multi-line English report for the in-app log (helps diagnose code 14 without Console).
    static func buildReport() -> String {
        var lines: [String] = []
        lines.append("[Diagnostics] --- Host app ---")
        let main = Bundle.main
        lines.append("[Diagnostics] Bundle path: \(main.bundlePath)")
        lines.append("[Diagnostics] Main bundle ID: \(main.bundleIdentifier ?? "(nil)")")
        lines.append("[Diagnostics] Executable: \(main.executablePath ?? "(nil)")")
        let fromApps = AppBundleLocation.isStandardApplicationsInstall
        lines.append("[Diagnostics] Installed under Applications (system or ~/Applications): \(fromApps ? "yes" : "no (DerivedData/Xcode — common cause of code 14)")")

        let pluginsURL = main.bundleURL.appendingPathComponent("Contents/PlugIns", isDirectory: true)
        lines.append("[Diagnostics] --- PlugIns ---")
        lines.append("[Diagnostics] Path: \(pluginsURL.path)")
        let fm = FileManager.default
        guard fm.fileExists(atPath: pluginsURL.path) else {
            lines.append("[Diagnostics] ERROR: PlugIns folder missing — extension was not embedded in this .app")
            lines.append(contentsOf: appGroupLines())
            return lines.joined(separator: "\n")
        }
        guard let entries = try? fm.contentsOfDirectory(at: pluginsURL, includingPropertiesForKeys: nil) else {
            lines.append("[Diagnostics] ERROR: Cannot list PlugIns")
            lines.append(contentsOf: appGroupLines())
            return lines.joined(separator: "\n")
        }
        let names = entries.map(\.lastPathComponent).sorted()
        if names.isEmpty {
            lines.append("[Diagnostics] ERROR: PlugIns is empty — embed DataGateMacPacketTunnel.appex in the app target")
        } else {
            lines.append("[Diagnostics] Contents: \(names.joined(separator: ", "))")
        }

        let appexName = "DataGateMacPacketTunnel.appex"
        let appexURL = pluginsURL.appendingPathComponent(appexName, isDirectory: true)
        lines.append("[Diagnostics] --- Packet tunnel appex ---")
        if !fm.fileExists(atPath: appexURL.path) {
            lines.append("[Diagnostics] ERROR: \(appexName) not found under PlugIns")
            lines.append(contentsOf: appGroupLines())
            return lines.joined(separator: "\n")
        }

        let infoURL = appexURL.appendingPathComponent("Contents/Info.plist")
        if let dict = NSDictionary(contentsOf: infoURL) as? [String: Any] {
            let bid = dict["CFBundleIdentifier"] as? String ?? "(missing)"
            lines.append("[Diagnostics] CFBundleIdentifier: \(bid)")
            if bid == TunnelConstants.packetTunnelBundleIdentifier {
                lines.append("[Diagnostics] Matches NETunnelProviderProtocol.providerBundleIdentifier: OK")
            } else {
                lines.append("[Diagnostics] MISMATCH: set providerBundleIdentifier to \(bid) or fix Xcode bundle ID")
            }
            let exe = dict["CFBundleExecutable"] as? String ?? "(missing)"
            lines.append("[Diagnostics] CFBundleExecutable: \(exe)")
            let exeURL = appexURL.appendingPathComponent("Contents/MacOS/\(exe)", isDirectory: false)
            lines.append("[Diagnostics] Executable exists on disk: \(fm.fileExists(atPath: exeURL.path))")

            if let ext = dict["NSExtension"] as? [String: Any],
               let point = ext["NSExtensionPointIdentifier"] as? String {
                lines.append("[Diagnostics] NSExtensionPointIdentifier: \(point)")
                if point != expectedExtensionPoint {
                    lines.append("[Diagnostics] WARNING: expected \(expectedExtensionPoint)")
                }
            } else {
                lines.append("[Diagnostics] ERROR: NSExtension / NSExtensionPointIdentifier missing in plist")
            }
        } else {
            lines.append("[Diagnostics] ERROR: Cannot read \(infoURL.path)")
        }

        lines.append(contentsOf: appGroupLines())
        lines.append("[Diagnostics] If code 14 persists with OK above, check Console (neagent) at Connect time.")
        return lines.joined(separator: "\n")
    }

    private static func appGroupLines() -> [String] {
        var lines: [String] = []
        lines.append("[Diagnostics] --- App Group (host) ---")
        let id = ExtensionLogReader.appGroupId
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            lines.append("[Diagnostics] group \(id): container OK — \(url.path)")
        } else {
            lines.append("[Diagnostics] group \(id): no container (entitlements missing or not matching extension)")
        }
        return lines
    }
}
