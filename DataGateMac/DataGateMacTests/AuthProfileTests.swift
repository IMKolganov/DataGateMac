//
//  AuthProfileTests.swift
//  DataGateMacTests
//

import XCTest
@testable import DataGateMac

final class AuthProfileTests: XCTestCase {
    func testGoogleLoginResponseDecodesAvatarUrl() throws {
        let json = """
        {
          "token": "abc",
          "expiration": "2026-01-01T00:00:00Z",
          "userId": 7,
          "displayName": "Ada Lovelace",
          "email": "ada@example.com",
          "isNewUser": false,
          "avatarUrl": "https://lh3.googleusercontent.com/a/test-photo"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(GoogleLoginResponse.self, from: json)
        XCTAssertEqual(decoded.displayName, "Ada Lovelace")
        XCTAssertEqual(decoded.avatarUrl, "https://lh3.googleusercontent.com/a/test-photo")
    }

    func testGoogleLoginResponseDecodesSnakeCaseAvatarUrlLikeAuthClient() throws {
        let json = """
        {
          "token": "abc",
          "expiration": "2026-01-01T00:00:00Z",
          "user_id": 7,
          "display_name": "Ada",
          "email": "ada@example.com",
          "is_new_user": false,
          "avatar_url": "https://lh3.googleusercontent.com/a/snake"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(GoogleLoginResponse.self, from: json)
        XCTAssertEqual(decoded.userId, 7)
        XCTAssertEqual(decoded.displayName, "Ada")
        XCTAssertEqual(decoded.avatarUrl, "https://lh3.googleusercontent.com/a/snake")
    }

    func testGoogleLoginResponseIgnoresMissingAndNonHttpsAvatar() throws {
        let json = """
        {
          "token": "abc",
          "expiration": "2026-01-01T00:00:00Z",
          "userId": 1,
          "displayName": "Ada",
          "isNewUser": false,
          "avatarUrl": "http://insecure.example/photo.png"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(GoogleLoginResponse.self, from: json)
        XCTAssertNil(decoded.avatarUrl)
    }

    func testGoogleLoginResponseDecodesTotpChallengeWithoutToken() throws {
        let json = """
        {
          "userId": 9,
          "displayName": "Admin",
          "email": "admin@example.com",
          "requiresTotp": true,
          "loginChallengeId": "challenge-abc",
          "requiresTotpSetup": false
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(GoogleLoginResponse.self, from: json)
        XCTAssertTrue(decoded.isTotpChallenge)
        XCTAssertFalse(decoded.hasAccessToken)
        XCTAssertEqual(decoded.loginChallengeId, "challenge-abc")
        XCTAssertEqual(decoded.displayName, "Admin")
        XCTAssertTrue(decoded.token.isEmpty)
    }

    func testTotpCodeNormalizesAndExtractsSixDigits() {
        XCTAssertEqual(TotpCode.normalize("12 34-56"), "123456")
        XCTAssertEqual(TotpCode.normalize("123456789"), "123456")
        XCTAssertEqual(TotpCode.extractSixDigits("12 34 56"), "123456")
        XCTAssertEqual(TotpCode.extractSixDigits("code: 123456"), "123456")
        XCTAssertNil(TotpCode.extractSixDigits("12345"))
        XCTAssertNil(TotpCode.extractSixDigits("1234567"))
        XCTAssertTrue(TotpCode.isChallengeExpiredMessage("Login challenge expired. Sign in again."))
        XCTAssertFalse(TotpCode.isChallengeExpiredMessage("Invalid verification code."))
    }

    func testProfileImageURLAcceptsHttpsOnly() {
        XCTAssertEqual(
            ProfileImageURL.normalizedString("  https://lh3.googleusercontent.com/a/x  "),
            "https://lh3.googleusercontent.com/a/x"
        )
        XCTAssertNil(ProfileImageURL.normalizedString("http://lh3.googleusercontent.com/a/x"))
        XCTAssertNil(ProfileImageURL.normalizedString(""))
        XCTAssertNil(ProfileImageURL.parse(nil))
    }

    func testJwtClaimReaderReadsAvatarUrl() throws {
        let jwt = try jwt(payload: [
            "displayName": "Ada",
            "avatarUrl": "https://lh3.googleusercontent.com/a/from-jwt",
        ])
        XCTAssertEqual(
            JwtClaimReader.getAvatarUrl(fromJwt: jwt),
            "https://lh3.googleusercontent.com/a/from-jwt"
        )
    }

    func testJwtClaimReaderReadsPictureFallback() throws {
        let jwt = try jwt(payload: [
            "picture": "https://lh3.googleusercontent.com/a/picture-claim",
        ])
        XCTAssertEqual(
            JwtClaimReader.getAvatarUrl(fromJwt: jwt),
            "https://lh3.googleusercontent.com/a/picture-claim"
        )
    }

    func testJwtClaimReaderRejectsNonHttpsPicture() throws {
        let jwt = try jwt(payload: ["avatarUrl": "javascript:alert(1)"])
        XCTAssertNil(JwtClaimReader.getAvatarUrl(fromJwt: jwt))
    }

    func testAuthJSONDateParsesFractionalAndDotNet() {
        XCTAssertNotNil(AuthJSONDate.parse("2026-09-07T09:36:05Z"))
        XCTAssertNotNil(AuthJSONDate.parse("2026-09-07T09:36:05.123Z"))
        let sevenDigit = AuthJSONDate.parse("2026-09-07T09:36:05.1234567Z")
        XCTAssertNotNil(sevenDigit)
        let threeDigit = AuthJSONDate.parse("2026-09-07T09:36:05.123Z")
        XCTAssertEqual(sevenDigit?.timeIntervalSince1970 ?? -1, threeDigit?.timeIntervalSince1970 ?? -2, accuracy: 0.001)
        XCTAssertNotNil(AuthJSONDate.parse("2026-09-07T09:36:05.1234567+00:00"))
        let unix = AuthJSONDate.parse(1_757_232_965)
        XCTAssertEqual(unix.timeIntervalSince1970, 1_757_232_965, accuracy: 0.5)
        let millis = AuthJSONDate.parse(1_757_232_965_000)
        XCTAssertEqual(millis.timeIntervalSince1970, 1_757_232_965, accuracy: 0.5)
        let dotNet = AuthJSONDate.parse("/Date(1757232965000)/")
        XCTAssertEqual(dotNet?.timeIntervalSince1970 ?? -1, 1_757_232_965, accuracy: 0.5)
        XCTAssertNil(AuthJSONDate.parse(""))
        XCTAssertNil(AuthJSONDate.parse("not-a-date"))
    }

    func testAuthTokensResponseDecodesFractionalExpiration() throws {
        let json = """
        {"token":"abc","expiration":"2026-09-07T09:36:05.1234567Z","refreshToken":"rt","refreshExpiration":"2026-09-08T09:36:05.1234567Z"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AuthTokensResponse.self, from: json)
        XCTAssertEqual(decoded.token, "abc")
        XCTAssertEqual(decoded.refreshToken, "rt")
        XCTAssertGreaterThan(decoded.expiration, Date.distantPast)
        XCTAssertNotNil(decoded.refreshExpiration)
    }

    func testGoogleLoginResponseDecodesFractionalExpiration() throws {
        let json = """
        {
          "token": "abc",
          "expiration": "2026-09-07T09:36:05.1234567Z",
          "refreshToken": "rt",
          "userId": 1,
          "displayName": "Ada",
          "isNewUser": false
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(GoogleLoginResponse.self, from: json)
        XCTAssertGreaterThan(decoded.expiration.timeIntervalSince1970, 1_000_000)
        XCTAssertEqual(decoded.refreshToken, "rt")
    }

    func testDecodeRefreshPayloadAcceptsWrappedAndBareTokens() throws {
        let wrapped = """
        {"success":true,"message":"ok","data":{"token":"new-access","expiration":"2026-09-07T11:00:00Z","refresh_token":"new-rt"}}
        """.data(using: .utf8)!
        let wrappedTokens = AuthSession.decodeRefreshPayload(wrapped)
        XCTAssertEqual(wrappedTokens?.token, "new-access")
        XCTAssertEqual(wrappedTokens?.refreshToken, "new-rt")

        let bare = """
        {"token":"bare-access","expiration":"2026-09-07T11:00:00Z"}
        """.data(using: .utf8)!
        let bareTokens = AuthSession.decodeRefreshPayload(bare)
        XCTAssertEqual(bareTokens?.token, "bare-access")
        XCTAssertNil(bareTokens?.refreshToken)
    }

    func testDecodeRefreshPayloadRejectsGarbageAndEmptyToken() {
        XCTAssertNil(AuthSession.decodeRefreshPayload(Data("{\"success\":true}".utf8)))
        XCTAssertNil(AuthSession.decodeRefreshPayload(Data("not-json".utf8)))
        let emptyToken = """
        {"success":true,"data":{"token":"","expiration":"2026-09-07T11:00:00Z"}}
        """.data(using: .utf8)!
        XCTAssertNil(AuthSession.decodeRefreshPayload(emptyToken))
    }

    func testMergingRefreshTokenKeepsPreviousWhenOmitted() {
        let previous = AuthTokensResponse(
            token: "old",
            expiration: Date(),
            refreshToken: "keep-me",
            refreshExpiration: Date().addingTimeInterval(3600)
        )
        let incoming = AuthTokensResponse(
            token: "new",
            expiration: Date().addingTimeInterval(600),
            refreshToken: nil,
            refreshExpiration: nil
        )
        let merged = AuthSession.mergingRefreshToken(incoming, previous: previous)
        XCTAssertEqual(merged.token, "new")
        XCTAssertEqual(merged.refreshToken, "keep-me")
        XCTAssertEqual(merged.refreshExpiration, previous.refreshExpiration)
    }

    func testMergingRefreshTokenPrefersIncomingRefreshToken() {
        let previous = AuthTokensResponse(
            token: "old",
            expiration: Date(),
            refreshToken: "old-rt",
            refreshExpiration: Date().addingTimeInterval(3600)
        )
        let incoming = AuthTokensResponse(
            token: "new",
            expiration: Date().addingTimeInterval(600),
            refreshToken: "new-rt",
            refreshExpiration: Date().addingTimeInterval(7200)
        )
        let merged = AuthSession.mergingRefreshToken(incoming, previous: previous)
        XCTAssertEqual(merged.refreshToken, "new-rt")
        XCTAssertEqual(merged.refreshExpiration, incoming.refreshExpiration)
    }

    func testJwtClaimReaderReadsExpiration() throws {
        let jwt = try jwt(payload: ["exp": 1_757_232_965])
        let exp = JwtClaimReader.expiration(fromJwt: jwt)
        XCTAssertEqual(exp?.timeIntervalSince1970 ?? -1, 1_757_232_965, accuracy: 0.5)
    }

    func testFileTokenStoreRoundTripsDatesAsUnixSeconds() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileTokenStore(fileURL: dir.appendingPathComponent("auth.json"))
        let expiration = Date(timeIntervalSince1970: 1_757_232_965)
        let refreshExpiration = Date(timeIntervalSince1970: 1_757_319_365)
        try store.save(
            AuthTokensResponse(
                token: "access",
                expiration: expiration,
                refreshToken: "rt",
                refreshExpiration: refreshExpiration
            )
        )
        let loaded = try store.load()
        XCTAssertEqual(loaded?.token, "access")
        XCTAssertEqual(loaded?.refreshToken, "rt")
        XCTAssertEqual(loaded?.expiration.timeIntervalSince1970 ?? -1, expiration.timeIntervalSince1970, accuracy: 0.5)
        XCTAssertEqual(loaded?.refreshExpiration?.timeIntervalSince1970 ?? -1, refreshExpiration.timeIntervalSince1970, accuracy: 0.5)
    }

    func testGetValidAccessTokenReturnsUnexpiredStoredToken() async throws {
        let access = try jwt(payload: ["exp": Date().addingTimeInterval(3600).timeIntervalSince1970])
        let session = try makeSession(
            token: access,
            expiration: Date().addingTimeInterval(3600),
            refreshToken: "rt"
        )
        let token = await session.getValidAccessToken()
        XCTAssertEqual(token, access)
        XCTAssertNil(session.lastFailureDescription)
    }

    func testGetValidAccessTokenUsesJwtExpWhenExpirationFieldIsStale() async throws {
        let access = try jwt(payload: ["exp": Date().addingTimeInterval(3600).timeIntervalSince1970])
        let session = try makeSession(
            token: access,
            expiration: Date().addingTimeInterval(-120),
            refreshToken: "rt"
        )
        let token = await session.getValidAccessToken()
        XCTAssertEqual(token, access)
    }

    func testGetValidAccessTokenDoesNotClearStoreWhenRefreshTokenMissing() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileTokenStore(fileURL: dir.appendingPathComponent("auth.json"))
        let access = try jwt(payload: ["exp": Date().addingTimeInterval(-120).timeIntervalSince1970])
        try store.save(
            AuthTokensResponse(
                token: access,
                expiration: Date().addingTimeInterval(-120),
                refreshToken: nil,
                refreshExpiration: nil
            )
        )
        let session = AuthSession(store: store)
        let token = await session.getValidAccessToken()
        XCTAssertNil(token)
        XCTAssertEqual(session.lastFailureDescription, "no refresh token")
        XCTAssertEqual(try store.load()?.token, access)
    }

    func testGetValidAccessTokenClearsStoreWhenRefreshExpired() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileTokenStore(fileURL: dir.appendingPathComponent("auth.json"))
        let access = try jwt(payload: ["exp": Date().addingTimeInterval(-120).timeIntervalSince1970])
        try store.save(
            AuthTokensResponse(
                token: access,
                expiration: Date().addingTimeInterval(-120),
                refreshToken: "rt",
                refreshExpiration: Date().addingTimeInterval(-10)
            )
        )
        let session = AuthSession(store: store)
        let token = await session.getValidAccessToken()
        XCTAssertNil(token)
        XCTAssertEqual(session.lastFailureDescription, "refresh token expired")
        XCTAssertNil(try store.load())
    }

    private func makeSession(
        token: String,
        expiration: Date,
        refreshToken: String?
    ) throws -> AuthSession {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FileTokenStore(fileURL: dir.appendingPathComponent("auth.json"))
        try store.save(
            AuthTokensResponse(
                token: token,
                expiration: expiration,
                refreshToken: refreshToken,
                refreshExpiration: Date().addingTimeInterval(86_400)
            )
        )
        return AuthSession(store: store)
    }

    private func jwt(payload: [String: Any]) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let body = try JSONSerialization.data(withJSONObject: payload)
        return "\(base64URL(header)).\(base64URL(body)).sig"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

final class IssuedClientIdentityTests: XCTestCase {
    func testOpenVpnFallsBackToCnDotOvpn() {
        let identity = IssuedClientIdentity.resolve(
            response: DownloadFileResponse(commonName: "mdg-1-user-inst"),
            fallbackCommonName: "mdg-fallback",
            ovpnContent: "client\nremote vpn.example.com 1194\n",
            isXray: false
        )
        XCTAssertEqual(identity.commonName, "mdg-1-user-inst")
        XCTAssertEqual(identity.fileName, "mdg-1-user-inst.ovpn")
    }

    func testXrayKeepsFallbackCnAndDoesNotInventOvpnName() {
        let identity = IssuedClientIdentity.resolve(
            response: DownloadFileResponse(),
            fallbackCommonName: "mdg-xray-2-user-inst",
            ovpnContent: "vless://uuid@host:443?encryption=none#node",
            isXray: true
        )
        XCTAssertEqual(identity.commonName, "mdg-xray-2-user-inst")
        XCTAssertNil(identity.fileName)
    }

    func testDecodesPascalCaseTopLevelIdentity() throws {
        let json = Data(#"{"FileName":"cyprus-xray.json","CommonName":"mdg-xray-9-abc","Content":""}"#.utf8)
        let response = try JSONDecoder().decode(DownloadFileResponse.self, from: json)
        let identity = IssuedClientIdentity.resolve(
            response: response,
            fallbackCommonName: "fallback",
            ovpnContent: nil,
            isXray: true
        )
        XCTAssertEqual(identity.commonName, "mdg-xray-9-abc")
        XCTAssertEqual(identity.fileName, "cyprus-xray.json")
    }

    func testDecodesNestedIssuedOvpn() throws {
        let json = Data(#"{"issuedOvpn":{"fileName":"issued-from-api.ovpn","commonName":"cn-from-api"}}"#.utf8)
        let response = try JSONDecoder().decode(DownloadFileResponse.self, from: json)
        XCTAssertEqual(response.fileName, "issued-from-api.ovpn")
        XCTAssertEqual(response.commonName, "cn-from-api")
    }

    func testDecodesSnakeCaseIssuedXray() throws {
        let json = Data(#"{"issued_xray":{"file_name":"xray-client.json","common_name":"mdg-xray-cn"}}"#.utf8)
        let response = try JSONDecoder().decode(DownloadFileResponse.self, from: json)
        XCTAssertEqual(response.fileName, "xray-client.json")
        XCTAssertEqual(response.commonName, "mdg-xray-cn")
    }

    func testOvpnCommentFileNameWhenApiOmitsIt() {
        let ovpn = """
        # /tmp/clients/mdg-1-user-inst.ovpn
        client
        remote vpn.example.com 1194
        """
        let identity = IssuedClientIdentity.resolve(
            response: DownloadFileResponse(),
            fallbackCommonName: "mdg-1-user-inst",
            ovpnContent: ovpn,
            isXray: false
        )
        XCTAssertEqual(identity.fileName, "mdg-1-user-inst.ovpn")
        XCTAssertEqual(identity.commonName, "mdg-1-user-inst")
    }

    func testXrayPayloadJsonIdentity() {
        let payload = """
        {"vless":"vless://uuid@host:443?encryption=none#n","commonName":"mdg-xray-payload","fileName":"payload-link.json"}
        """
        let identity = IssuedClientIdentity.resolve(
            response: DownloadFileResponse(),
            fallbackCommonName: "fallback",
            ovpnContent: payload,
            isXray: true
        )
        XCTAssertEqual(identity.commonName, "mdg-xray-payload")
        XCTAssertEqual(identity.fileName, "payload-link.json")
    }
}
