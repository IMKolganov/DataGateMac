//
//  ProcessRunner.swift
//  DataGateMac
//
//  Runs an external process, streams stdout/stderr and reports exit code.
//

import Foundation

final class ProcessRunner {
    private let process = Process()
    private let executablePath: String
    private let arguments: [String]
    private let onOutput: (String) -> Void
    private let onExit: (Int32) -> Void

    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    init(
        executablePath: String,
        arguments: [String],
        onOutput: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.onOutput = onOutput
        self.onExit = onExit
    }

    func start() {
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        outputPipe = outPipe
        errorPipe = errPipe

        process.terminationHandler = { [weak self] finishedProcess in
            let code = finishedProcess.terminationStatus
            self?.onExit(code)
        }

        readPipe(outPipe) { [weak self] line in
            self?.onOutput(line)
        }
        readPipe(errPipe) { [weak self] line in
            self?.onOutput(line)
        }

        do {
            try process.run()
        } catch {
            onOutput("Failed to start: \(error.localizedDescription)")
            onExit(-1)
        }
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
    }

    private func readPipe(_ pipe: Pipe, lineHandler: @escaping (String) -> Void) {
        let fd = pipe.fileHandleForReading.fileDescriptor
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8)?
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init) {
                for line in text where !line.isEmpty {
                    lineHandler(line)
                }
            }
        }
    }
}
