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
