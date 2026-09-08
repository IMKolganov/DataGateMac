//
//  OpenVpnFilesModels.swift
//  DataGateMac
//
//  Matches backend OpenVpnFiles API: download-file-by-cn, add-with-token, DownloadFileResponse.
//

import Foundation

// MARK: - Download (response)

struct DownloadFileResponse: Decodable {
    let content: Data?
    let issuedOvpn: IssuedOvpnDto?
    /// Top-level filename when the backend does not wrap it in `issuedOvpn`.
    let fileName: String?
    let commonName: String?

    enum CodingKeys: String, CodingKey {
        case content
        case issuedOvpn
        case fileName
        case commonName
    }

    init(content: Data? = nil, issuedOvpn: IssuedOvpnDto? = nil, fileName: String? = nil, commonName: String? = nil) {
        self.content = content
        self.fileName = IssuedClientIdentity.cleaned(fileName)
        self.commonName = IssuedClientIdentity.cleaned(commonName)
        self.issuedOvpn = issuedOvpn ?? IssuedOvpnDto(fileName: self.fileName, commonName: self.commonName)
    }

    init(from decoder: Decoder) throws {
        let object = try decoder.singleValueContainer().decode([String: JSONValue].self)
        content = Self.decodeContent(object["content"] ?? object["Content"])
        let issuedObject = Self.firstObject(
            object,
            keys: [
                "issuedOvpn", "IssuedOvpn", "issued_ovpn",
                "issuedXray", "IssuedXray", "issued_xray",
                "issuedClientLink", "IssuedClientLink",
            ]
        )
        let issued = IssuedOvpnDto(fromJSON: issuedObject)
        let topFile = Self.firstString(object, keys: ["fileName", "FileName", "file_name", "filename"])
        let topCN = Self.firstString(object, keys: ["commonName", "CommonName", "common_name", "cn", "CN"])
        fileName = IssuedClientIdentity.cleaned(topFile) ?? issued?.fileName
        commonName = IssuedClientIdentity.cleaned(topCN) ?? issued?.commonName
        issuedOvpn = issued ?? IssuedOvpnDto(fileName: fileName, commonName: commonName)
    }

    private static func decodeContent(_ value: JSONValue?) -> Data? {
        switch value {
        case .string(let text):
            return Data(base64Encoded: text) ?? text.data(using: .utf8)
        case .object:
            return nil
        case .array, .number, .bool, .null, .none:
            return nil
        }
    }

    private static func firstString(_ object: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if case .string(let text)? = object[key] {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func firstObject(_ object: [String: JSONValue], keys: [String]) -> [String: JSONValue]? {
        for key in keys {
            if case .object(let nested)? = object[key] {
                return nested
            }
        }
        return nil
    }
}

struct IssuedOvpnDto: Equatable, Sendable {
    let fileName: String?
    let commonName: String?

    init(fileName: String?, commonName: String?) {
        self.fileName = IssuedClientIdentity.cleaned(fileName)
        self.commonName = IssuedClientIdentity.cleaned(commonName)
    }

    init?(fromJSON object: [String: JSONValue]?) {
        guard let object else { return nil }
        let fileName = IssuedClientIdentity.cleaned(
            JSONValue.firstString(object, keys: ["fileName", "FileName", "file_name", "filename"])
        )
        let commonName = IssuedClientIdentity.cleaned(
            JSONValue.firstString(object, keys: ["commonName", "CommonName", "common_name", "cn", "CN"])
        )
        if fileName == nil && commonName == nil { return nil }
        self.init(fileName: fileName, commonName: commonName)
    }
}

/// CN + issued file name shown in Home / Profiles after Connect.
struct IssuedClientIdentity: Equatable, Sendable {
    var commonName: String
    var fileName: String?

    static func resolve(
        response: DownloadFileResponse,
        fallbackCommonName: String,
        ovpnContent: String?,
        isXray: Bool
    ) -> IssuedClientIdentity {
        let payloadFields = fieldsFromPayloadJSON(ovpnContent)
        let cn = cleaned(response.commonName)
            ?? cleaned(response.issuedOvpn?.commonName)
            ?? payloadFields.commonName
            ?? cleaned(fallbackCommonName)
            ?? ""
        var file = cleaned(response.fileName)
            ?? cleaned(response.issuedOvpn?.fileName)
            ?? payloadFields.fileName
            ?? fileName(fromOvpnComments: ovpnContent)
        if file == nil, !isXray, !cn.isEmpty {
            file = "\(cn).ovpn"
        }
        return IssuedClientIdentity(commonName: cn, fileName: file)
    }

    /// CN / file name nested in the downloaded payload JSON (Xray client-link body).
    static func fieldsFromPayloadJSON(_ text: String?) -> (commonName: String?, fileName: String?) {
        guard let text else { return (nil, nil) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        let nested = firstJSONObject(object, keys: [
            "issuedOvpn", "IssuedOvpn", "issued_ovpn",
            "issuedXray", "IssuedXray", "issued_xray",
            "issuedClientLink", "IssuedClientLink",
        ])
        let cn = firstJSONString(object, keys: ["commonName", "CommonName", "common_name", "cn", "CN"])
            ?? firstJSONString(nested, keys: ["commonName", "CommonName", "common_name", "cn", "CN"])
        let file = firstJSONString(object, keys: ["fileName", "FileName", "file_name", "filename"])
            ?? firstJSONString(nested, keys: ["fileName", "FileName", "file_name", "filename"])
        return (cleaned(cn), cleaned(file))
    }

    private static func firstJSONString(_ object: [String: Any]?, keys: [String]) -> String? {
        guard let object else { return nil }
        for key in keys {
            if let text = object[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func firstJSONObject(_ object: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let nested = object[key] as? [String: Any] {
                return nested
            }
        }
        return nil
    }

    static func cleaned(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func fileName(fromOvpnComments content: String?) -> String? {
        guard let content else { return nil }
        for raw in content.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
            var line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("#") || line.hasPrefix(";") else { continue }
            line = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let range = line.range(of: ".ovpn", options: .caseInsensitive) else { continue }
            let prefix = line[..<range.upperBound]
            let token = prefix.split(whereSeparator: { $0 == "/" || $0 == "\\" || $0.isWhitespace }).last.map(String.init)
            if let token, token.lowercased().hasSuffix(".ovpn"), token.count > 5 {
                return token
            }
        }
        return nil
    }
}

enum JSONValue: Decodable {
    case string(String)
    case number
    case bool
    case object([String: JSONValue])
    case array
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let text = try? container.decode(String.self) {
            self = .string(text)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if (try? container.decode([JSONValue].self)) != nil {
            self = .array
        } else if (try? container.decode(Bool.self)) != nil {
            self = .bool
        } else if (try? container.decode(Double.self)) != nil {
            self = .number
        } else {
            self = .null
        }
    }

    static func firstString(_ object: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if case .string(let text)? = object[key] {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}

// MARK: - Download by CN (request)

struct DownloadFileByCnRequest: Encodable {
    let vpnServerId: Int
    let commonName: String

    enum CodingKeys: String, CodingKey {
        case vpnServerId
        case commonName
    }
}

// MARK: - Add with token (request)

struct AddFileWithTokenRequest: Encodable {
    let vpnServerId: Int
    let commonName: String
    let externalId: String
    let issuedTo: String

    enum CodingKeys: String, CodingKey {
        case vpnServerId
        case commonName
        case externalId
        case issuedTo
    }
}
