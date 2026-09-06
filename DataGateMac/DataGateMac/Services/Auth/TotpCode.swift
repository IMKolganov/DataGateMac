//
//  TotpCode.swift
//  DataGateMac
//
//  6-digit authenticator codes (same rules as the dashboard TotpChallengeForm).
//

import Foundation

enum TotpCode {
    static func normalize(_ raw: String) -> String {
        String(raw.filter { $0 >= "0" && $0 <= "9" }.prefix(6))
    }

    static func extractSixDigits(_ raw: String) -> String? {
        let digits = raw.filter { $0 >= "0" && $0 <= "9" }
        return digits.count == 6 ? digits : nil
    }

    static func isChallengeExpiredMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("challenge expired")
            || lower.contains("too many invalid attempts")
            || lower.contains("sign in again")
    }
}
