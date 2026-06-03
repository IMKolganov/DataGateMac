//
//  SystemExtensionMain.swift
//  DataGateMacPacketTunnel
//
//  Entry point for the Network Extension system extension. Registers NE provider
//  classes with the session manager (required for .systemextension packaging).
//

import Foundation
import NetworkExtension
import os.log

private let bootLog = Logger(subsystem: "imkolganov.DataGateMac.PacketTunnel", category: "Boot")

@main
enum SystemExtensionMain {
    static func main() {
        autoreleasepool {
            bootLog.info("[Ext] first light — startSystemExtensionMode")
            NEProvider.startSystemExtensionMode()
        }
        // Keep the extension process alive for NESM XPC (required; otherwise provider.matching dies immediately).
        dispatchMain()
    }
}
