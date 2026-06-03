//
//  VpnDiagnostics.swift
//  DataGateMac
//
//  Runtime checks to narrow down NEVPN code 14 (plugin not loaded): embedded sysex, plist IDs, App Group.
//

import Foundation

enum TunnelConstants {
    /// Must match the packet tunnel system extension Product Bundle Identifier in Xcode.
    static let packetTunnelBundleIdentifier = "imkolganov.DataGateMac.PacketTunnel"
    /// Filename of the embedded system extension product (bundle ID + .systemextension).
    static let packetTunnelSystemExtensionName = "imkolganov.DataGateMac.PacketTunnel.systemextension"
    /// UserDefaults: last host .app path used for VPN profile (recreate profile when install path changes).
    static let lastHostAppPathDefaultsKey = "imkolganov.DataGateMac.lastVpnHostAppPath"
    /// UserDefaults: SHA-256 of the sysex Mach-O last activated/replaced successfully.
    static let lastActivatedSysexHashDefaultsKey = "imkolganov.DataGateMac.lastActivatedSysexHash"
    /// UserDefaults: CFBundleVersion of the sysex last activated/replaced successfully.
    static let lastActivatedSysexBundleVersionDefaultsKey = "imkolganov.DataGateMac.lastActivatedSysexBundleVersion"
}

/// Host app install path vs DerivedData (Launch Services / system extension activation).
enum AppBundleLocation {
    private static var bundleURL: URL {
        Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
    }

    /// True when the .app lives under any `Applications` folder (system or `~/Applications`), not under Xcode build products.
    static var isStandardApplicationsInstall: Bool {
        let path = bundleURL.path
        if path.contains("/DerivedData/") { return false }
        if path.contains("/Build/Products/") { return false }
        return bundleURL.deletingLastPathComponent().lastPathComponent == "Applications"
    }

    /// System extension activation requires `/Applications`, not `~/Applications`.
    static var isSystemApplicationsInstall: Bool {
        bundleURL.deletingLastPathComponent().path == "/Applications"
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
        let fromSystemApps = AppBundleLocation.isSystemApplicationsInstall
        lines.append("[Diagnostics] Installed under an Applications folder (not DerivedData/build products): \(fromApps ? "yes" : "no (Xcode build path — common cause of code 14)")")
        if fromApps && !fromSystemApps {
            lines.append("[Diagnostics] WARNING: app is in ~/Applications — system extension activation requires /Applications (system folder)")
        } else if fromSystemApps {
            lines.append("[Diagnostics] System /Applications install: yes (required for system extension activation)")
        }

        let sysexDirURL = main.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions", isDirectory: true)
        lines.append("[Diagnostics] --- System Extensions ---")
        lines.append("[Diagnostics] Path: \(sysexDirURL.path)")
        let fm = FileManager.default
        guard fm.fileExists(atPath: sysexDirURL.path) else {
            lines.append("[Diagnostics] ERROR: Library/SystemExtensions missing — system extension was not embedded in this .app")
            lines.append(contentsOf: legacyPluginsLines(fm: fm, main: main))
            lines.append(contentsOf: appGroupLines())
            return lines.joined(separator: "\n")
        }
        guard let entries = try? fm.contentsOfDirectory(at: sysexDirURL, includingPropertiesForKeys: nil) else {
            lines.append("[Diagnostics] ERROR: Cannot list SystemExtensions")
            lines.append(contentsOf: appGroupLines())
            return lines.joined(separator: "\n")
        }
        let names = entries.map(\.lastPathComponent).sorted()
        if names.isEmpty {
            lines.append("[Diagnostics] ERROR: SystemExtensions folder is empty — embed \(TunnelConstants.packetTunnelSystemExtensionName) in the app target")
        } else {
            lines.append("[Diagnostics] Contents: \(names.joined(separator: ", "))")
        }

        let sysexName = TunnelConstants.packetTunnelSystemExtensionName
        let sysexURL = sysexDirURL.appendingPathComponent(sysexName, isDirectory: true)
        lines.append("[Diagnostics] --- Packet tunnel system extension ---")
        if !fm.fileExists(atPath: sysexURL.path) {
            lines.append("[Diagnostics] ERROR: \(sysexName) not found under Library/SystemExtensions")
            lines.append(contentsOf: legacyPluginsLines(fm: fm, main: main))
            lines.append(contentsOf: appGroupLines())
            return lines.joined(separator: "\n")
        }

        let infoURL = sysexURL.appendingPathComponent("Contents/Info.plist")
        if let dict = NSDictionary(contentsOf: infoURL) as? [String: Any] {
            let bid = dict["CFBundleIdentifier"] as? String ?? "(missing)"
            lines.append("[Diagnostics] CFBundleIdentifier: \(bid)")
            if bid == TunnelConstants.packetTunnelBundleIdentifier {
                lines.append("[Diagnostics] Embedded sysex bundle ID matches TunnelConstants: OK")
            } else {
                lines.append("[Diagnostics] MISMATCH: embedded sysex CFBundleIdentifier must be \(TunnelConstants.packetTunnelBundleIdentifier)")
            }
            let exe = dict["CFBundleExecutable"] as? String ?? "(missing)"
            lines.append("[Diagnostics] CFBundleExecutable: \(exe)")
            let exeURL = sysexURL.appendingPathComponent("Contents/MacOS/\(exe)", isDirectory: false)
            lines.append("[Diagnostics] Executable exists on disk: \(fm.fileExists(atPath: exeURL.path))")
            let embeddedVersion = dict["CFBundleVersion"] as? String ?? "(missing)"
            let lastActivatedVersion = UserDefaults.standard.string(forKey: TunnelConstants.lastActivatedSysexBundleVersionDefaultsKey)
            lines.append("[Diagnostics] Embedded sysex CFBundleVersion: \(embeddedVersion)")
            if let lastActivatedVersion {
                if lastActivatedVersion == embeddedVersion {
                    lines.append("[Diagnostics] Last activated sysex build: \(lastActivatedVersion) (matches embedded)")
                } else {
                    lines.append("[Diagnostics] WARNING: Last activated sysex build \(lastActivatedVersion) != embedded \(embeddedVersion). Connect will deactivate/replace — approve in System Settings if prompted.")
                }
            } else {
                lines.append("[Diagnostics] Last activated sysex build: (none recorded yet)")
            }

            if let ne = dict["NetworkExtension"] as? [String: Any],
               let classes = ne["NEProviderClasses"] as? [String: Any],
               let provider = classes[expectedExtensionPoint] as? String {
                lines.append("[Diagnostics] NEProviderClasses[\(expectedExtensionPoint)]: \(provider)")
            } else if let ext = dict["NSExtension"] as? [String: Any],
                      let point = ext["NSExtensionPointIdentifier"] as? String {
                lines.append("[Diagnostics] NSExtensionPointIdentifier (legacy): \(point)")
            } else {
                lines.append("[Diagnostics] ERROR: NetworkExtension/NEProviderClasses missing in plist")
            }
        } else {
            lines.append("[Diagnostics] ERROR: Cannot read \(infoURL.path)")
        }

        lines.append(contentsOf: appGroupLines())
        lines.append("[Diagnostics] Saved VPN profile must use providerBundleIdentifier \(TunnelConstants.packetTunnelBundleIdentifier) (not the host app ID). Connect auto-fixes stale profiles; use Reset VPN profile if code 14 persists.")
        lines.append("[Diagnostics] Extension logs: Console.app → subsystem imkolganov.DataGateMac.PacketTunnel (no shared file without App Group on extension).")
        return lines.joined(separator: "\n")
    }

    private static func legacyPluginsLines(fm: FileManager, main: Bundle) -> [String] {
        let pluginsURL = main.bundleURL.appendingPathComponent("Contents/PlugIns", isDirectory: true)
        guard fm.fileExists(atPath: pluginsURL.path),
              let entries = try? fm.contentsOfDirectory(at: pluginsURL, includingPropertiesForKeys: nil),
              !entries.isEmpty else {
            return []
        }
        let names = entries.map(\.lastPathComponent).sorted()
        return ["[Diagnostics] WARNING: Legacy PlugIns still present: \(names.joined(separator: ", ")) — remove appex embed for Developer ID builds"]
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
