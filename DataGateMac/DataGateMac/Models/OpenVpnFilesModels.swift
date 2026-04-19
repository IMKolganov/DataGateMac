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

    enum CodingKeys: String, CodingKey {
        case content
        case issuedOvpn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var decodedContent: Data?
        if let data = try? c.decodeIfPresent(Data.self, forKey: .content) {
            decodedContent = data
        } else if let base64 = try? c.decodeIfPresent(String.self, forKey: .content) {
            decodedContent = Data(base64Encoded: base64)
        }
        content = decodedContent
        issuedOvpn = try? c.decodeIfPresent(IssuedOvpnDto.self, forKey: .issuedOvpn)
    }
}

struct IssuedOvpnDto: Decodable {
    let fileName: String?

    enum CodingKeys: String, CodingKey {
        case fileName
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
