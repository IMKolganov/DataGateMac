//
//  CrashReporting.swift
//  DataGateMac
//
//  Host-process crash capture (Windows engine dumps + Android next-launch ingest).
//

import Foundation
import os

#if arch(arm64)
nonisolated(unsafe) private let crashArch = "arm64"
#else
nonisolated(unsafe) private let crashArch = "x86_64"
#endif

@_silgen_name("DataGateInstallCrashSignalHandler")
nonisolated func DataGateInstallCrashSignalHandler(_ path: UnsafePointer<CChar>?)

nonisolated(unsafe) private let crashInstallLog = Logger(subsystem: "imkolganov.DataGateMac", category: "CrashReport")

nonisolated enum CrashReporting {
    nonisolated(unsafe) private static var installed = false
    nonisolated(unsafe) private static var previousExceptionHandler: NSUncaughtExceptionHandler?

    static func install() {
        guard !installed else { return }
        installed = true

        let appVersion = currentAppVersion()
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        CrashReportStore.promotePendingSignalIfNeeded(
            appVersion: appVersion,
            osVersion: osVersion,
            arch: crashArch
        )

        if let path = try? CrashReportStore.pendingSignalURL().path {
            path.withCString { DataGateInstallCrashSignalHandler($0) }
        }

        previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(datagateUncaughtException)
    }

    static func startUploadOnLaunch() {
        Task.detached {
            await uploadPending()
        }
    }

    static func uploadPending() async {
        guard let appConfig = try? AppConfig.load(),
              let ingestURL = CrashReportUploader.ingestURL(apiBaseUrl: appConfig.apiBaseUrl),
              let directory = try? CrashReportStore.directory() else {
            return
        }
        let config = CrashReportUploadConfig(
            ingestURL: ingestURL,
            process: CrashReportText.processId,
            token: appConfig.crashReportToken
        )
        await CrashReportUploader.uploadPending(
            directory: directory,
            session: ClientIdentity.session,
            config: config
        )
    }

    fileprivate static func handleUncaught(_ exception: NSException) {
        record(exception)
        previousExceptionHandler?(exception)
    }

    private static func record(_ exception: NSException) {
        let text = CrashReportText.body(
            timestamp: Date(),
            appVersion: currentAppVersion(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            arch: crashArch,
            kind: "fatal",
            exceptionName: exception.name.rawValue,
            message: exception.reason,
            stack: exception.callStackSymbols
        )
        let name = CrashReportText.fileName(at: Date(), timeZone: .current)
        do {
            let url = try CrashReportStore.write(text, named: name)
            crashInstallLog.error("Wrote crash report \(url.lastPathComponent, privacy: .public)")
        } catch {
            crashInstallLog.error("Failed to write crash report: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func currentAppVersion() -> String {
        let bundle = Bundle.main
        let marketing = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(marketing) (\(build))"
    }
}

nonisolated private func datagateUncaughtException(_ exception: NSException) {
    CrashReporting.handleUncaught(exception)
}
