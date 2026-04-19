//
//  L10n.swift
//  DataGateMac
//
//  Loads strings from `Localizable.strings` in language bundles; respects Settings / Login language.
//

import Foundation

enum L10n {
    /// Resolved bundle for the active app language (not used when `SYSTEM` — then `Bundle.main` + OS rules apply).
    static func activeBundle() -> Bundle {
        let key = AppStoredLocale.normalizeStorageValue(UserDefaults.standard.string(forKey: AppLanguageStorage.key))
        guard let loc = AppStoredLocale(rawValue: key), loc != .SYSTEM,
              let folder = loc.resourceBundleFolder,
              let path = Bundle.main.path(forResource: folder, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    static func tr(_ key: String, _ fallback: String) -> String {
        let bundle = activeBundle()
        let value = bundle.localizedString(forKey: key, value: "\u{FFFC}", table: nil)
        if value == "\u{FFFC}" || value == key {
            return Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
        }
        return value
    }

    static func trFormat(_ key: String, _ fallback: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key, fallback), locale: activeLocaleForFormatting(), arguments: arguments)
    }

    /// Public so formatters (`DateFormatter`, `ByteCountFormatter`) follow the selected app language.
    static func activeLocaleForFormatting() -> Locale {
        let key = AppStoredLocale.normalizeStorageValue(UserDefaults.standard.string(forKey: AppLanguageStorage.key))
        guard let loc = AppStoredLocale(rawValue: key), loc != .SYSTEM,
              let tag = loc.bcp47Identifier else {
            return .current
        }
        return Locale(identifier: tag)
    }
}
