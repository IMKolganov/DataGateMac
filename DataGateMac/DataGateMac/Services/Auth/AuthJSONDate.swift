//
//  AuthJSONDate.swift
//  DataGateMac
//
//  Parses backend auth timestamps (ISO-8601 with/without fractional seconds, unix).
//

import Foundation

enum AuthJSONDate: Sendable {
    static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let date = fractionalFormatter.date(from: trimmed) ?? basicFormatter.date(from: trimmed) {
            return date
        }
        if let clipped = clipFractionalSeconds(trimmed),
           let date = fractionalFormatter.date(from: clipped) ?? basicFormatter.date(from: clipped) {
            return date
        }
        if let date = parseDotNet(trimmed) {
            return date
        }
        return nil
    }

    static func parse(_ value: Double) -> Date {
        if value > 10_000_000_000 {
            return Date(timeIntervalSince1970: value / 1000)
        }
        return Date(timeIntervalSince1970: value)
    }

    static func decode<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Date {
        if let text = try? container.decode(String.self, forKey: key) {
            if let date = parse(text) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Invalid auth date string"
            )
        }
        if let value = try? container.decode(Double.self, forKey: key) {
            return parse(value)
        }
        if let value = try? container.decode(Int64.self, forKey: key) {
            return parse(Double(value))
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Missing auth date"
        )
    }

    static func decodeIfPresent<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Date? {
        guard container.contains(key), !(try container.decodeNil(forKey: key)) else {
            return nil
        }
        return try decode(container, forKey: key)
    }

    private static let basicFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// .NET often emits 7 fractional digits; Foundation ISO8601 accepts up to 3.
    private static func clipFractionalSeconds(_ raw: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\.(\d{4,})(Z|[+-]\d{2}:?\d{2})$"#) else {
            return nil
        }
        let range = NSRange(raw.startIndex..., in: raw)
        guard let match = regex.firstMatch(in: raw, range: range),
              let fracRange = Range(match.range(at: 1), in: raw) else {
            return nil
        }
        let digits = String(raw[fracRange])
        let clipped = String(digits.prefix(3))
        return raw.replacingCharacters(in: fracRange, with: clipped)
    }

    private static func parseDotNet(_ raw: String) -> Date? {
        guard raw.hasPrefix("/Date("), raw.hasSuffix(")/") else { return nil }
        let inner = raw.dropFirst(6).dropLast(2)
        let digits = inner.prefix { $0 == "-" || $0.isNumber }
        guard let value = Double(digits), !digits.isEmpty else { return nil }
        return parse(value)
    }
}
