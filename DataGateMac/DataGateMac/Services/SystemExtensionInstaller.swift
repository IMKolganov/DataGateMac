//
//  SystemExtensionInstaller.swift
//  DataGateMac
//
//  Activates the embedded packet tunnel system extension before startVPNTunnel().
//

import CryptoKit
import Foundation
import os.log
import SystemExtensions

enum SystemExtensionInstaller {
    private static let log = Logger(subsystem: "imkolganov.DataGateMac", category: "SystemExtension")
    /// Keeps the activation delegate alive until OSSystemExtensionManager calls back (`request.delegate` is weak).
    private static var pendingDelegate: RequestDelegate?

    private static func embeddedSystemExtensionURL() -> URL? {
        let dir = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/SystemExtensions", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return nil }
        return items.first { $0.pathExtension == "systemextension" }
    }

    static func embeddedSystemExtensionBundleVersion() -> String? {
        guard let url = embeddedSystemExtensionURL(),
              let bundle = Bundle(url: url) else { return nil }
        return bundle.infoDictionary?["CFBundleVersion"] as? String
    }

    /// SHA-256 of the embedded sysex Mach-O; changes on every rebuild even when CFBundleVersion stays the same.
    static func embeddedSystemExtensionExecutableHash() -> String? {
        guard let sysexURL = embeddedSystemExtensionURL(),
              let executableURL = Bundle(url: sysexURL)?.executableURL,
              let data = try? Data(contentsOf: executableURL)
        else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func recordSuccessfulActivation() {
        if let hash = embeddedSystemExtensionExecutableHash() {
            UserDefaults.standard.set(hash, forKey: TunnelConstants.lastActivatedSysexHashDefaultsKey)
        }
        if let version = embeddedSystemExtensionBundleVersion() {
            UserDefaults.standard.set(version, forKey: TunnelConstants.lastActivatedSysexBundleVersionDefaultsKey)
        }
    }

    enum ActivationError: LocalizedError {
        case wrongInstallLocation(String)
        case requestFailed(String)
        case willCompleteAfterReboot
        case userCancelled
        case staleSystemExtensionInstalled(String)

        var errorDescription: String? {
            switch self {
            case .wrongInstallLocation(let path):
                return "Move DataGateMac.app to /Applications (not ~/Applications). Current path: \(path)"
            case .requestFailed(let message):
                return message
            case .willCompleteAfterReboot:
                return "The VPN system extension was approved but requires a restart before it can run."
            case .userCancelled:
                return "System extension activation was cancelled."
            case .staleSystemExtensionInstalled(let message):
                return message
            }
        }
    }

    /// Submits an activation request and waits until the system extension is ready (or fails).
    static func activateIfNeeded() async throws {
        guard AppBundleLocation.isSystemApplicationsInstall else {
            throw ActivationError.wrongInstallLocation(Bundle.main.bundlePath)
        }

        let currentHash = embeddedSystemExtensionExecutableHash()
        let currentVersion = embeddedSystemExtensionBundleVersion()
        let lastHash = UserDefaults.standard.string(forKey: TunnelConstants.lastActivatedSysexHashDefaultsKey)
        let lastVersion = UserDefaults.standard.string(forKey: TunnelConstants.lastActivatedSysexBundleVersionDefaultsKey)

        #if !DEBUG
        if let currentHash, let lastHash, lastHash == currentHash,
           let currentVersion, let lastVersion, lastVersion == currentVersion {
            log.debug("Embedded system extension unchanged; skipping activation request")
            return
        }
        #endif

        if lastVersion != nil, lastVersion != currentVersion {
            log.notice("Embedded sysex build \(currentVersion ?? "?") != last activated \(lastVersion ?? "?"); submitting activation so the system can replace it")
        } else if lastHash != nil, lastHash != currentHash {
            log.info("Embedded system extension binary changed; submitting activation (replace) request")
        } else {
            log.info("Submitting system extension activation request for \(TunnelConstants.packetTunnelBundleIdentifier, privacy: .public)")
        }
        // Do not deactivate first. A version bump used to call deactivationRequest, then
        // activate; if build 18 was already gone, macOS returned OSSystemExtensionError
        // extensionNotFound (4) and Connect never submitted the replacement for 20.
        try await submitRequest(activationRequest())
        recordSuccessfulActivation()
    }

    private static func activationRequest() -> OSSystemExtensionRequest {
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: TunnelConstants.packetTunnelBundleIdentifier,
            queue: .main
        )
        return request
    }

    private static func submitRequest(_ request: OSSystemExtensionRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = RequestDelegate { result in
                pendingDelegate = nil
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            pendingDelegate = delegate
            request.delegate = delegate
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    private final class RequestDelegate: NSObject, OSSystemExtensionRequestDelegate {
        private let onFinish: (Result<Void, Error>) -> Void
        private var didFinish = false

        init(onFinish: @escaping (Result<Void, Error>) -> Void) {
            self.onFinish = onFinish
        }

        func request(
            _ request: OSSystemExtensionRequest,
            actionForReplacingExtension existing: OSSystemExtensionProperties,
            withExtension ext: OSSystemExtensionProperties
        ) -> OSSystemExtensionRequest.ReplacementAction {
            SystemExtensionInstaller.log.notice(
                "Replacing sysex \(existing.bundleVersion, privacy: .public) -> \(ext.bundleVersion, privacy: .public)"
            )
            return .replace
        }

        func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
            SystemExtensionInstaller.log.notice("System extension awaiting user approval in System Settings")
        }

        func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
            switch result {
            case .completed:
                finishOnce(with: .success(()))
            case .willCompleteAfterReboot:
                finishOnce(with: .failure(ActivationError.willCompleteAfterReboot))
            @unknown default:
                finishOnce(with: .failure(ActivationError.requestFailed("Unknown system extension activation result.")))
            }
        }

        func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
            let nsError = error as NSError
            if nsError.domain == OSSystemExtensionErrorDomain,
               nsError.code == OSSystemExtensionError.requestCanceled.rawValue {
                finishOnce(with: .failure(ActivationError.userCancelled))
                return
            }
            finishOnce(with: .failure(ActivationError.requestFailed(Self.describe(nsError))))
        }

        private static func describe(_ nsError: NSError) -> String {
            guard nsError.domain == OSSystemExtensionErrorDomain else {
                return nsError.localizedDescription
            }
            let detail: String
            switch nsError.code {
            case OSSystemExtensionError.extensionNotFound.rawValue:
                detail = "extension not found (4). The previous build was probably already removed; Connect should retry activation without uninstalling first."
            case OSSystemExtensionError.unsupportedParentBundleLocation.rawValue:
                detail = "unsupported parent bundle location (3). Run DataGateMac from /Applications."
            case OSSystemExtensionError.codeSignatureInvalid.rawValue:
                detail = "code signature invalid (8)."
            case OSSystemExtensionError.validationFailed.rawValue:
                detail = "validation failed (9)."
            case OSSystemExtensionError.forbiddenBySystemPolicy.rawValue:
                detail = "forbidden by system policy (10). Allow the extension in System Settings."
            case OSSystemExtensionError.authorizationRequired.rawValue:
                detail = "authorization required (13). Approve the system extension prompt."
            default:
                detail = nsError.localizedDescription
            }
            return "OSSystemExtensionErrorDomain \(detail)"
        }

        private func finishOnce(with outcome: Result<Void, Error>) {
            guard !didFinish else { return }
            didFinish = true
            onFinish(outcome)
        }
    }
}
