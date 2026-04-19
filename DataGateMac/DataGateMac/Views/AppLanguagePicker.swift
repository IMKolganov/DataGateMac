//
//  AppLanguagePicker.swift
//  DataGateMac
//
//  Shared language menu (Settings + Login). Persists `AppLanguageStorage.key`.
//

import SwiftUI

struct AppLanguagePicker: View {
    @AppStorage(AppLanguageStorage.key) private var stored: String = AppStoredLocale.SYSTEM.rawValue
    @Environment(\.locale) private var locale

    var body: some View {
        Picker("", selection: $stored) {
            ForEach(AppStoredLocale.pickerOrder) { lang in
                Text(lang.pickerDisplayLabel(preferredLocale: locale)).tag(lang.rawValue)
            }
        }
        .labelsHidden()
        .fixedSize()
        .onChange(of: stored) { _, _ in
            NotificationCenter.default.post(name: .appLanguageChanged, object: nil)
        }
    }
}
