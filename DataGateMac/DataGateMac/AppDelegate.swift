//
//  AppDelegate.swift
//  DataGateMac
//
//  Confirms application quit when the VPN tunnel is still active, then disconnects.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the last window should end the session (same quit path as Cmd+Q), so VPN confirmation runs.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            let needsConfirm = await VpnQuitCoordinator.needsConfirmationBeforeQuitting()
            if !needsConfirm {
                NSApp.reply(toApplicationShouldTerminate: true)
                return
            }

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.tr("quit_vpn_title", "Quit DataGate?")
            alert.informativeText = L10n.tr(
                "quit_vpn_message",
                "The VPN tunnel is still active. Quitting will disconnect you. Are you sure you want to continue?"
            )
            alert.addButton(withTitle: L10n.tr("quit_vpn_confirm", "Quit and disconnect"))
            alert.addButton(withTitle: L10n.tr("quit_vpn_cancel", "Cancel"))

            if alert.runModal() == .alertFirstButtonReturn {
                await VpnQuitCoordinator.stopDataGateTunnelIfPresent()
                NSApp.reply(toApplicationShouldTerminate: true)
            } else {
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}
