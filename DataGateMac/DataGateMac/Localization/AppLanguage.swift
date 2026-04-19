//
//  AppLanguage.swift
//  DataGateMac
//
//  Pinned UI language: storage values match Android `AppLocale` enum names (`SYSTEM`, `EN`, `ZH_CN`, …).
//

import Foundation

extension Notification.Name {
    /// Posted when the user changes `AppLanguageStorage.key` so view models refresh visible strings.
    static let appLanguageChanged = Notification.Name("imkolganov.DataGateMac.appLanguageChanged")
}

enum AppLanguageStorage {
    static let key = "appPreferredLanguage"

    /// Migrates legacy Mac values (`system`, `en`, `zh-Hans`, …) to Android-style names so pickers and bundles resolve consistently.
    static func normalizeIfNeeded() {
        let raw = UserDefaults.standard.string(forKey: key)
        let normalized = AppStoredLocale.normalizeStorageValue(raw)
        if normalized != raw {
            UserDefaults.standard.set(normalized, forKey: key)
        }
    }
}

/// Mirrors `com.imkolganov.datagate.ui.theme.AppLocale` (Kotlin): same `rawValue` strings for cross-platform prefs.
enum AppStoredLocale: String, Identifiable {
    case SYSTEM
    case EN, BG, HR, CS, DA, NL, ET, FI, FR, DE, EL, HU, GA, IT, LV, LT, MT, PL, PT, RO, SK, SL, ES, SV
    case RU, UK
    case FA_IR, TR, HI_IN, ZH_CN, ZH_TW, ES_MX, AR, JA, KO, PT_BR, VI, TH, ID, FIL

    var id: String { rawValue }

    /// Same order as `AppLocale.pickerOrder` on Android.
    static var pickerOrder: [AppStoredLocale] {
        let european: [AppStoredLocale] = [
            .BG, .HR, .CS, .DA, .NL, .ET, .FI, .FR, .DE, .EL, .HU, .GA, .IT, .LV, .LT, .MT, .PL, .PT, .RO, .SK, .SL, .ES, .SV,
        ]
        let nonEuropean: [AppStoredLocale] = [
            .FA_IR, .TR, .HI_IN, .ZH_CN, .ZH_TW, .ES_MX, .AR, .JA, .KO, .PT_BR, .VI, .TH, .ID, .FIL,
        ]
        return [.SYSTEM, .EN, .RU, .UK] + european + nonEuropean
    }

    /// BCP-47 tag for formatters; `nil` for system default.
    var bcp47Identifier: String? {
        switch self {
        case .SYSTEM: return nil
        case .EN: return "en"
        case .BG: return "bg"
        case .HR: return "hr"
        case .CS: return "cs"
        case .DA: return "da"
        case .NL: return "nl"
        case .ET: return "et"
        case .FI: return "fi"
        case .FR: return "fr"
        case .DE: return "de"
        case .EL: return "el"
        case .HU: return "hu"
        case .GA: return "ga"
        case .IT: return "it"
        case .LV: return "lv"
        case .LT: return "lt"
        case .MT: return "mt"
        case .PL: return "pl"
        case .PT: return "pt"
        case .RO: return "ro"
        case .SK: return "sk"
        case .SL: return "sl"
        case .ES: return "es"
        case .SV: return "sv"
        case .RU: return "ru"
        case .UK: return "uk"
        case .FA_IR: return "fa-IR"
        case .TR: return "tr"
        case .HI_IN: return "hi-IN"
        case .ZH_CN: return "zh-CN"
        case .ZH_TW: return "zh-TW"
        case .ES_MX: return "es-MX"
        case .AR: return "ar"
        case .JA: return "ja"
        case .KO: return "ko"
        case .PT_BR: return "pt-BR"
        case .VI: return "vi"
        case .TH: return "th"
        case .ID: return "id"
        case .FIL: return "fil"
        }
    }

    /// `*.lproj` folder name inside the app bundle (differs from BCP-47 only for Chinese).
    var resourceBundleFolder: String? {
        switch self {
        case .SYSTEM: return nil
        case .ZH_CN: return "zh-Hans"
        case .ZH_TW: return "zh-Hant"
        default:
            return bcp47Identifier
        }
    }

    /// Label in the language picker (native name of the locale, in `preferredLocale`, usually SwiftUI `\.locale`).
    func pickerDisplayLabel(preferredLocale: Locale) -> String {
        if self == .SYSTEM {
            return L10n.tr("lang_system", "Follow system language")
        }
        guard let tag = bcp47Identifier else { return rawValue }
        return preferredLocale.localizedString(forIdentifier: tag) ?? rawValue
    }

    /// Normalizes a stored string to a valid `AppStoredLocale.rawValue`, or `SYSTEM`.
    static func normalizeStorageValue(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return AppStoredLocale.SYSTEM.rawValue }
        if AppStoredLocale(rawValue: trimmed) != nil { return trimmed }
        let upper = trimmed.uppercased()
        if AppStoredLocale(rawValue: upper) != nil { return upper }
        let lower = trimmed.lowercased()
        if let mapped = Self.legacyLowercasedMac[lower] { return mapped }
        return AppStoredLocale.SYSTEM.rawValue
    }

    /// Legacy Mac app used lowercase ISO codes and `system` / `zh-Hans` folder-style ids.
    private static let legacyLowercasedMac: [String: String] = [
        "system": "SYSTEM",
        "en": "EN",
        "ru": "RU",
        "de": "DE",
        "fr": "FR",
        "es": "ES",
        "fa_ir": "FA_IR",
        "hi_in": "HI_IN",
        "es_mx": "ES_MX",
        "pt_br": "PT_BR",
        "uk": "UK",
        "pl": "PL",
        "bg": "BG",
        "hr": "HR",
        "cs": "CS",
        "da": "DA",
        "nl": "NL",
        "et": "ET",
        "fi": "FI",
        "el": "EL",
        "hu": "HU",
        "ga": "GA",
        "it": "IT",
        "lv": "LV",
        "lt": "LT",
        "mt": "MT",
        "pt": "PT",
        "ro": "RO",
        "sk": "SK",
        "sl": "SL",
        "sv": "SV",
        "fa-ir": "FA_IR",
        "tr": "TR",
        "hi-in": "HI_IN",
        "zh-hans": "ZH_CN",
        "zh-hant": "ZH_TW",
        "zh-cn": "ZH_CN",
        "zh-tw": "ZH_TW",
        "es-mx": "ES_MX",
        "ar": "AR",
        "ja": "JA",
        "ko": "KO",
        "pt-br": "PT_BR",
        "vi": "VI",
        "th": "TH",
        "id": "ID",
        "fil": "FIL",
    ]
}
