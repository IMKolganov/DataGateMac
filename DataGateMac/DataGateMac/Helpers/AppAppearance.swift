//
//  AppAppearance.swift
//  DataGateMac
//
//  Theme: system, light, dark. Persisted in UserDefaults.
//

import SwiftUI
import AppKit

enum AppAppearance: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return Self.resolvedSystemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// When "system", resolve to current system theme so the window redraws correctly (avoid nil).
    private static var resolvedSystemScheme: ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum AppAppearanceStorage {
    static let key = "appAppearance"
}
