//
//  WSSBridge.swift
//  DataGateMacPacketTunnel
//
//  Listens on TCP 127.0.0.1:listenPort; for each connection opens WebSocket to wss://host:port/path and relays bytes.
//

import Foundation
import Network
import os.log

/// Human-readable endpoint for extension logs (English).
private func wssLogEndpoint(_ endpoint: NWEndpoint) -> String {
    switch endpoint {
    case let .hostPort(host, port):
        return "\(host):\(port)"
    case let .service(name, type, domain, interface):
        return "\(name).\(type)\(domain) if=\(String(describing: interface))"
    case let .unix(path):
        return "unix:\(path)"
    case let .url(url):
        return url.absoluteString
    @unknown default:
        return String(describing: endpoint)
    }
}

final class WSSBridge {
    private let host: String
    private let port: Int
    private let path: String
    private let listenPort: UInt16
    private let verifyServerCert: Bool
    private let log: Logger

    private var listener: NWListener?
    private var currentConnection: NWConnection?
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let queue = DispatchQueue(label: "WSSBridge.relay")
    private var isStopped = false
    /// Fired once when the first TCP client hits the listener (handshake complete from NWListener’s perspective). Used to defer `setTunnelNetworkSettings` until loopback TCP works.
    var onFirstLocalTcpAccepted: (() -> Void)?
    private var didReportFirstLocalClient = false

    init(host: String, port: Int, path: String, listenPort: Int, verifyServerCert: Bool, log: Logger) {
        self.host = host
        self.port = port
        self.path = path.hasPrefix("/") ? path : "/" + path
        self.listenPort = UInt16(listenPort)
        self.verifyServerCert = verifyServerCert
        self.log = log
    }

    private var upstreamWssURL: String {
        "wss://\(host):\(self.port)\(path)"
    }

    private var localListenLabel: String {
        "127.0.0.1:\(listenPort) (TCP)"
    }

    func start(completion: @escaping (Error?) -> Void) {
        ExtensionLogWriter.append("[WSSBridge] plan: OpenVPN -> TCP client \(localListenLabel) -> relay -> WebSocket upstream \(upstreamWssURL) verifyServerCert=\(verifyServerCert)")
        guard let nwPort = NWEndpoint.Port(rawValue: listenPort) else {
            completion(NSError(domain: "WSSBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid listen port"]))
            return
        }
        // Bind explicitly to IPv4 loopback. NWListener(using:.tcp, on: port) can listen on a stack OpenVPN/Asio does not reach from 127.0.0.1.
        var parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("127.0.0.1"), port: nwPort)
        guard let listener = try? NWListener(using: parameters) else {
            completion(NSError(domain: "WSSBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create NWListener(using: parameters) for 127.0.0.1:\(listenPort)"]))
            return
        }
        ExtensionLogWriter.append("[WSSBridge] listener bind requiredLocalEndpoint=127.0.0.1:\(listenPort) allowLocalEndpointReuse=true")
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log.info("[WSSBridge] listener ready \(self.localListenLabel) -> upstream \(self.upstreamWssURL)")
                ExtensionLogWriter.append("[WSSBridge] listener READY local=\(self.localListenLabel) upstream=\(self.upstreamWssURL)")
                completion(nil)
            case .failed(let err):
                self.log.error("[WSSBridge] listener failed: \(err.localizedDescription)")
                ExtensionLogWriter.append("[WSSBridge] listener FAILED local=\(self.localListenLabel) error=\(err.localizedDescription) [\(String(describing: (err as NSError).domain)) code \((err as NSError).code)]")
                if !self.isStopped { completion(err) }
            case .cancelled:
                ExtensionLogWriter.append("[WSSBridge] listener CANCELLED local=\(self.localListenLabel)")
            case .setup:
                ExtensionLogWriter.append("[WSSBridge] listener state=setup local=\(self.localListenLabel)")
            case .waiting(let err):
                ExtensionLogWriter.append("[WSSBridge] listener state=waiting local=\(self.localListenLabel) error=\(err.localizedDescription)")
            @unknown default:
                ExtensionLogWriter.append("[WSSBridge] listener state=unknown local=\(self.localListenLabel) raw=\(String(describing: state))")
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(connection: conn)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        isStopped = true
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        currentConnection?.cancel()
        listener?.cancel()
        listener = nil
        urlSession?.invalidateAndCancel()
    }

    private func accept(connection: NWConnection) {
        queue.async { [weak self] in
            self?.handleNewConnection(connection)
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        if currentConnection != nil {
            log.warning("Already have a client; closing new connection")
            ExtensionLogWriter.append("[WSSBridge] Already have a client; closing new connection")
            connection.cancel()
            return
        }
        let peerLabel = wssLogEndpoint(connection.endpoint)
        ExtensionLogWriter.append("[WSSBridge] inbound TCP peer endpoint=\(peerLabel) local_listen=\(localListenLabel) -> will open upstream \(upstreamWssURL)")
        if !didReportFirstLocalClient {
            didReportFirstLocalClient = true
            let notify = onFirstLocalTcpAccepted
            onFirstLocalTcpAccepted = nil
            if let notify {
                ExtensionLogWriter.append("[WSSBridge] first local TCP accepted peer=\(peerLabel) (apply tunnel routes after this)")
                notify()
            }
        }
        currentConnection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .preparing:
                ExtensionLogWriter.append("[WSSBridge] inbound TCP state=preparing peer=\(peerLabel)")
            case .setup:
                ExtensionLogWriter.append("[WSSBridge] inbound TCP state=setup peer=\(peerLabel)")
            case .waiting(let err):
                ExtensionLogWriter.append("[WSSBridge] inbound TCP state=waiting peer=\(peerLabel) error=\(err.localizedDescription)")
            case .ready:
                ExtensionLogWriter.append("[WSSBridge] inbound TCP state=READY peer=\(peerLabel) path=\(connection.currentPath.debugDescription)")
            case .failed(let err):
                ExtensionLogWriter.append("[WSSBridge] inbound TCP state=FAILED peer=\(peerLabel) error=\(err.localizedDescription)")
                self?.currentConnection = nil
                self?.webSocketTask?.cancel(with: .goingAway, reason: nil)
            case .cancelled:
                ExtensionLogWriter.append("[WSSBridge] inbound TCP state=cancelled peer=\(peerLabel)")
                self?.currentConnection = nil
                self?.webSocketTask?.cancel(with: .goingAway, reason: nil)
            @unknown default:
                ExtensionLogWriter.append("[WSSBridge] inbound TCP state=unknown peer=\(peerLabel)")
            }
        }
        connection.start(queue: queue)

        let scheme = "wss"
        let urlString = "\(scheme)://\(host):\(port)\(path)"
        guard let url = URL(string: urlString) else {
            log.error("Invalid WSS URL: \(urlString)")
            ExtensionLogWriter.append("[WSSBridge] Invalid WSS URL: \(urlString)")
            connection.cancel()
            currentConnection = nil
            return
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 86400
        ExtensionLogWriter.append("[WSSBridge] URLSession WebSocket: url=\(urlString) requestTimeoutSec=\(config.timeoutIntervalForRequest) resourceTimeoutSec=\(config.timeoutIntervalForResource) tlsPinning=\(verifyServerCert ? "strict" : "delegate_accepts_server_trust")")
        let sessionDelegate: URLSessionDelegate? = verifyServerCert ? nil : InsecureWSDelegate()
        let session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
        urlSession = session
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        log.info("[WSSBridge] relay start peer=\(peerLabel) -> \(urlString)")
        ExtensionLogWriter.append("[WSSBridge] relay START peer=\(peerLabel) tcp_local=\(localListenLabel) ws_upstream=\(urlString)")

        relayTCPToWebSocket(connection: connection, task: task)
        relayWebSocketToTCP(connection: connection, task: task)
    }

    private func relayTCPToWebSocket(connection: NWConnection, task: URLSessionWebSocketTask) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, !self.isStopped else { return }
            if let error {
                self.log.error("TCP receive error: \(error.localizedDescription)")
                ExtensionLogWriter.append("[WSSBridge] TCP recv error local=\(self.localListenLabel) upstream=\(self.upstreamWssURL) err=\(error.localizedDescription)")
                task.cancel(with: .goingAway, reason: nil)
                connection.cancel()
                return
            }
            guard let data, !data.isEmpty else {
                ExtensionLogWriter.append("[WSSBridge] TCP recv empty EOF local=\(self.localListenLabel) upstream=\(self.upstreamWssURL)")
                task.cancel(with: .goingAway, reason: nil)
                connection.cancel()
                return
            }
            task.send(.data(data)) { [weak self] err in
                if let err {
                    self?.log.error("WS send error: \(err.localizedDescription)")
                    ExtensionLogWriter.append("[WSSBridge] WS send error upstream=\(self?.upstreamWssURL ?? "") bytes=\(data.count) err=\(err.localizedDescription)")
                }
            }
            self.relayTCPToWebSocket(connection: connection, task: task)
        }
    }

    private func relayWebSocketToTCP(connection: NWConnection, task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, !self.isStopped else { return }
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    connection.send(content: data, contentContext: .defaultStream, isComplete: false, completion: .contentProcessed({ _ in }))
                case .string(let s):
                    if let d = s.data(using: .utf8) {
                        connection.send(content: d, contentContext: .defaultStream, isComplete: false, completion: .contentProcessed({ _ in }))
                    }
                @unknown default:
                    break
                }
            case .failure(let err):
                self.log.error("WS receive error: \(err.localizedDescription)")
                ExtensionLogWriter.append("[WSSBridge] WS recv error upstream=\(self.upstreamWssURL) err=\(err.localizedDescription)")
                connection.cancel()
                return
            }
            self.relayWebSocketToTCP(connection: connection, task: task)
        }
    }
}

private final class InsecureWSDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
