//
//  DataGateMacApp.swift
//  DataGateMac
//
//  Created by Ivan Kolganov on 01/02/2026.
//

import SwiftUI

@main
struct DataGateMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AppLanguageStorage.normalizeIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .defaultSize(width: 920, height: 680)
        .windowResizability(.contentMinSize)
    }
}
