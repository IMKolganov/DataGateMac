//
//  WSSBridge.swift
//  DataGateMacPacketTunnel
//
//  Listens on TCP 127.0.0.1:listenPort; for each connection opens WebSocket to wss://host:port/path and relays bytes.
//

import Foundation
import Network
import os.log

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

    init(host: String, port: Int, path: String, listenPort: Int, verifyServerCert: Bool, log: Logger) {
        self.host = host
        self.port = port
        self.path = path.hasPrefix("/") ? path : "/" + path
        self.listenPort = UInt16(listenPort)
        self.verifyServerCert = verifyServerCert
        self.log = log
    }

    func start(completion: @escaping (Error?) -> Void) {
        guard let port = NWEndpoint.Port(rawValue: listenPort) else {
            completion(NSError(domain: "WSSBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid listen port"]))
            return
        }
        guard let listener = try? NWListener(using: .tcp, on: port) else {
            completion(NSError(domain: "WSSBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create listener"]))
            return
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log.info("[WSSBridge] listening on 127.0.0.1:\(self.listenPort)")
                ExtensionLogWriter.append("[WSSBridge] listening on 127.0.0.1:\(self.listenPort)")
                completion(nil)
            case .failed(let err):
                self.log.error("[WSSBridge] listener failed: \(err.localizedDescription)")
                ExtensionLogWriter.append("[WSSBridge] listener failed: \(err.localizedDescription)")
                if !self.isStopped { completion(err) }
            case .cancelled:
                break
            default:
                break
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
        currentConnection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.currentConnection = nil
                self?.webSocketTask?.cancel(with: .goingAway, reason: nil)
            default:
                break
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
        let sessionDelegate: URLSessionDelegate? = verifyServerCert ? nil : InsecureWSDelegate()
        let session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
        urlSession = session
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        log.info("[WSSBridge] client connected; WebSocket to \(urlString)")
        ExtensionLogWriter.append("[WSSBridge] client connected; WebSocket to \(urlString)")

        relayTCPToWebSocket(connection: connection, task: task)
        relayWebSocketToTCP(connection: connection, task: task)
    }

    private func relayTCPToWebSocket(connection: NWConnection, task: URLSessionWebSocketTask) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, !self.isStopped else { return }
            if let error {
                self.log.error("TCP receive error: \(error.localizedDescription)")
                ExtensionLogWriter.append("[WSSBridge] TCP receive error: \(error.localizedDescription)")
                task.cancel(with: .goingAway, reason: nil)
                connection.cancel()
                return
            }
            guard let data, !data.isEmpty else {
                task.cancel(with: .goingAway, reason: nil)
                connection.cancel()
                return
            }
            task.send(.data(data)) { [weak self] err in
                if let err {
                    self?.log.error("WS send error: \(err.localizedDescription)")
                    ExtensionLogWriter.append("[WSSBridge] WS send error: \(err.localizedDescription)")
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
                ExtensionLogWriter.append("[WSSBridge] WS receive error: \(err.localizedDescription)")
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
