//
//  GoogleAuthService.swift
//  DataGateMac
//
//  Google OAuth loopback flow: http://127.0.0.1:PORT — required by Google for desktop apps.
//  Matches DataGateWin behavior. Custom URL schemes are restricted by Google policy.
//

import Foundation
import Network
import AppKit
import CommonCrypto
import os.log

private let oauthLog = Logger(subsystem: "imkolganov.DataGateMac", category: "OAuth")

private func log(_ msg: String) {
    oauthLog.info("\(msg)")
    print("[DataGate OAuth] \(msg)")
}

/// Call cancel() to abort the OAuth redirect wait.
final class OAuthCanceller {
    private var listener: NWListener?
    private var onCancel: (() -> Void)?
    private let lock = NSLock()

    func register(listener: NWListener, onCancel: @escaping () -> Void) {
        lock.lock()
        self.listener = listener
        self.onCancel = onCancel
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let listener = self.listener
        let onCancel = self.onCancel
        self.listener = nil
        self.onCancel = nil
        lock.unlock()
        listener?.cancel()
        onCancel?()
    }
}

final class GoogleAuthService {
    private let config: AppConfig
    private let redirectTimeout: TimeInterval = 180
    private let backendTimeout: TimeInterval = 60

    init(config: AppConfig) {
        self.config = config
    }

    func signInAndLogin(
        canceller: OAuthCanceller? = nil,
        onProgress: ((String) -> Void)? = nil
    ) async throws -> GoogleLoginResponse {
        let redirectUri = "http://127.0.0.1:\(config.redirectPort)/"
        let state = Self.generateState()
        let pkce = PkcePair.createS256()

        onProgress?("Preparing local sign-in server on 127.0.0.1:\(config.redirectPort)…")
        let authUrl = Self.buildAuthorizationUrl(
            clientId: config.googleClientId,
            redirectUri: redirectUri,
            state: state,
            codeChallenge: pkce.codeChallenge
        )

        let query = try await receiveRedirect(
            port: config.redirectPort,
            openUrl: authUrl,
            canceller: canceller,
            onProgress: onProgress
        )

        if let error = query["error"], !error.isEmpty {
            let desc = query["error_description"] ?? ""
            throw AuthError.authorizationFailed("\(error). \(desc)")
        }
        guard query["state"] == state else {
            throw AuthError.stateMismatch
        }
        guard let code = query["code"], !code.isEmpty else {
            throw AuthError.noCodeReturned
        }

        let request = GoogleCodeLoginRequest(
            code: code,
            codeVerifier: pkce.codeVerifier,
            redirectUri: redirectUri
        )

        onProgress?("Authorization code received. Exchanging it with the backend…")
        let apiUrl = "\(config.apiBaseUrl)/api/auth/google-code-login"
        let apiResponse: ApiResponse<GoogleLoginResponse> = try await postJson(apiUrl, body: request)

        guard apiResponse.success, let data = apiResponse.data else {
            throw AuthError.apiLoginFailed(apiResponse.message)
        }
        return data
    }

    private static func buildAuthorizationUrl(
        clientId: String,
        redirectUri: String,
        state: String,
        codeChallenge: String
    ) -> String {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        return components.url!.absoluteString
    }

    private func receiveRedirect(
        port: Int,
        openUrl: String,
        canceller: OAuthCanceller?,
        onProgress: ((String) -> Void)?
    ) async throws -> [String: String] {
        log("Starting OAuth redirect listener on port \(port)")
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: String], Error>) in
            let queue = DispatchQueue(label: "com.datagate.oauth.redirect")
            var didResume = false
            var listener: NWListener?
            var timeoutWorkItem: DispatchWorkItem?

            func resumeOnce(_ f: @escaping @Sendable () -> Void) {
                queue.async {
                    guard !didResume else { return }
                    didResume = true
                    timeoutWorkItem?.cancel()
                    f()
                }
            }

            timeoutWorkItem = DispatchWorkItem {
                resumeOnce {
                    log("OAuth redirect timed out after \(Int(self.redirectTimeout))s")
                    listener?.cancel()
                    continuation.resume(throwing: AuthError.redirectTimedOut(seconds: Int(self.redirectTimeout)))
                }
            }

            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: UInt16(port))!)
                log("Listener created")
            } catch {
                log("Listener failed: \(error.localizedDescription)")
                let msg = (error as NSError).domain == NSPOSIXErrorDomain && (error as NSError).code == 1
                    ? "Cannot start OAuth redirect server (Operation not permitted). Add \"Incoming Network Connections\" entitlement."
                    : error.localizedDescription
                continuation.resume(throwing: AuthError.listenerFailed(msg))
                return
            }
            if let timeoutWorkItem {
                queue.asyncAfter(deadline: .now() + redirectTimeout, execute: timeoutWorkItem)
            }

            guard let listener else {
                continuation.resume(throwing: AuthError.listenerFailed("Failed to initialize OAuth listener."))
                return
            }

            canceller?.register(listener: listener) {
                log("User cancelled")
                resumeOnce { continuation.resume(throwing: AuthError.cancelled) }
            }

            listener.stateUpdateHandler = { state in
                log("Listener state: \(String(describing: state))")
                if state == .ready {
                    onProgress?("Browser opened. Waiting for Google to call back to 127.0.0.1:\(port)…")
                    log("Listener ready, opening browser on main thread")
                    Self.runLoopbackHealthCheck(port: port, onProgress: onProgress)
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open(URL(string: openUrl)!)
                        log("Browser opened, waiting for redirect to http://127.0.0.1:\(port)/")
                    }
                } else if case .failed(let err) = state {
                    log("Listener failed: \(err.debugDescription)")
                    resumeOnce { continuation.resume(throwing: AuthError.listenerFailed(err.localizedDescription)) }
                }
            }

            listener.newConnectionHandler = { connection in
                log("Incoming connection received")
                connection.start(queue: queue)

                var received = Data()
                func receiveMore() {
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                        if let data = data { received.append(data) }
                        let hasCompleteRequest = received.contains(Data("\r\n\r\n".utf8)) || (String(data: received, encoding: .utf8) ?? "").contains("?code=")
                        if isComplete || error != nil || hasCompleteRequest {
                            let requestLine = Self.requestLine(from: received) ?? "<unknown request>"
                            log("Request received, isComplete=\(isComplete), hasComplete=\(hasCompleteRequest), line=\(requestLine)")
                            let query = Self.parseQueryFromRequest(received)
                            let isAuthCallback = query["code"]?.isEmpty == false || query["error"]?.isEmpty == false
                            if isAuthCallback {
                                onProgress?("Google callback received from localhost. Finishing sign-in…")
                            }
                            let html: String
                            if isAuthCallback {
                                html = "<html><body><h2>Success!</h2><p>You can close this window now.</p></body></html>"
                            } else {
                                html = "<html><body><h2>DataGate sign-in server is running.</h2><p>Return to the browser tab that asked you to sign in.</p></body></html>"
                            }
                            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                            guard let responseData = response.data(using: .utf8) else {
                                connection.cancel()
                                if isAuthCallback {
                                    listener.cancel()
                                    resumeOnce { continuation.resume(returning: query) }
                                }
                                return
                            }
                            connection.send(content: responseData, completion: .contentProcessed { _ in
                                log("Response sent, authCallback=\(isAuthCallback)")
                                connection.cancel()
                                if isAuthCallback {
                                    listener.cancel()
                                    resumeOnce { continuation.resume(returning: query) }
                                }
                            })
                        } else {
                            receiveMore()
                        }
                    }
                }
                receiveMore()
            }

            log("Starting listener")
            listener.start(queue: queue)
        }
    }

    private static func parseQueryFromRequest(_ data: Data) -> [String: String] {
        guard let request = String(data: data, encoding: .utf8) else { return [:] }
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        guard firstLine.hasPrefix("GET "),
              let pathStart = firstLine.index(firstLine.startIndex, offsetBy: 4, limitedBy: firstLine.endIndex),
              pathStart < firstLine.endIndex else { return [:] }
        let rest = String(firstLine[pathStart...])
        let pathAndQuery = rest.components(separatedBy: " ").first ?? rest
        guard let qmark = pathAndQuery.firstIndex(of: "?") else { return [:] }
        let queryString = String(pathAndQuery[pathAndQuery.index(after: qmark)...])
        var result: [String: String] = [:]
        for pair in queryString.components(separatedBy: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                let val = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                result[key] = val
            }
        }
        return result
    }

    private static func requestLine(from data: Data) -> String? {
        String(data: data, encoding: .utf8)?
            .components(separatedBy: "\r\n")
            .first
    }

    private static func runLoopbackHealthCheck(port: Int, onProgress: ((String) -> Void)?) {
        guard let url = URL(string: "http://127.0.0.1:\(port)/__healthcheck__") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let task = URLSession(configuration: .ephemeral).dataTask(with: request) { _, response, error in
            if let error {
                log("Loopback health check failed: \(error.localizedDescription)")
                onProgress?("Local callback server did not answer its own localhost probe.")
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            log("Loopback health check passed with HTTP \(code)")
            onProgress?("Local callback server is listening on 127.0.0.1:\(port). Waiting for Google redirect…")
        }
        task.resume()
    }

    private static func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64UrlEncode(Data(bytes))
    }

    private static func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    private func postJson<T: Encodable, R: Decodable>(_ urlString: String, body: T) async throws -> R {
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = backendTimeout

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.httpError("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.apiLoginFailed("\(http.statusCode): \(bodyStr)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(R.self, from: data)
    }

    private struct PkcePair {
        let codeVerifier: String
        let codeChallenge: String

        static func createS256() -> PkcePair {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            let verifier = base64UrlEncode(Data(bytes))
            let challenge = sha256Base64Url(verifier)
            return PkcePair(codeVerifier: verifier, codeChallenge: challenge)
        }
    }

    private static func sha256Base64Url(_ input: String) -> String {
        guard let data = input.data(using: .ascii) else { return "" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_SHA256(buf.baseAddress, CC_LONG(buf.count), &hash)
        }
        return base64UrlEncode(Data(hash))
    }

    enum AuthError: LocalizedError {
        case authorizationFailed(String)
        case stateMismatch
        case noCodeReturned
        case listenerFailed(String)
        case redirectTimedOut(seconds: Int)
        case httpError(String)
        case apiLoginFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .authorizationFailed(let msg): return msg
            case .stateMismatch: return "State validation failed."
            case .noCodeReturned: return "Authorization code was not returned."
            case .listenerFailed(let msg): return msg
            case .redirectTimedOut(let seconds): return "Timed out waiting for the Google redirect after \(seconds) seconds."
            case .httpError(let msg): return msg
            case .apiLoginFailed(let msg): return "API login failed: \(msg)"
            case .cancelled: return "Sign-in cancelled."
            }
        }
    }
}
