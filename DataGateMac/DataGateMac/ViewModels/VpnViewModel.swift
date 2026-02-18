//
//  VpnViewModel.swift
//  DataGateMac
//
//  Created by Ivan Kolganov on 01/02/2026.
//

import Foundation
import Combine

@MainActor
final class VpnViewModel: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var isBusy: Bool = false
    @Published var statusText: String = "Disconnected"
    @Published var logText: String = ""

    private var runner: ProcessRunner?

    func toggle() {
        if isConnected {
            disconnect()
        } else {
            connect()
        }
    }

    func connect() {
        isBusy = true
        statusText = "Connecting..."
        appendLog("UI: connect tapped")

        // 1) Путь к бинарю openvpn3 (CLI).
        //    Сейчас хардкодим. Позже сделаем настройку.
        //    Варианты:
        //    - положить openvpn3 в app bundle (Resources/bin/openvpn3)
        //    - использовать /usr/local/bin/openvpn3 если ставил через brew/ручную установку
        let openvpn3Path = "/usr/local/bin/openvpn3"

        // 2) Хардкодим команду. Это пример — конкретные команды зависят от твоего openvpn3.
        //    Для демонстрации можно запустить любой бинарь и почитать логи.
        //
        //    ТИПИЧНЫЙ паттерн:
        //    - import profile
        //    - start session
        //
        //    Но чтобы не упереться в различия, сначала сделаем "probe":
        //    openvpn3 version
        let args = ["version"]

        runner = ProcessRunner(
            executablePath: openvpn3Path,
            arguments: args,
            onOutput: { [weak self] line in
                Task { @MainActor in self?.appendLog(line) }
            },
            onExit: { [weak self] (code: Int32) in
                Task { @MainActor in
                    guard let self else { return }
                    self.appendLog("Process exited with code: \(code)")
                    self.isBusy = false

                    if code == 0 {
                        self.isConnected = true
                        self.statusText = "Connected (demo)"
                        self.appendLog("Demo: marked as connected after successful command.")
                    } else {
                        self.isConnected = false
                        self.statusText = "Disconnected"
                        self.appendLog("Failed to run openvpn3. Check path/permissions.")
                    }
                }
            }
        )

        runner?.start()
    }

    func disconnect() {
        isBusy = true
        statusText = "Disconnecting..."
        appendLog("UI: disconnect tapped")

        // Для демо: просто останавливаем процесс (если он был долгоживущим).
        runner?.stop()
        runner = nil

        isConnected = false
        statusText = "Disconnected"
        isBusy = false
        appendLog("Disconnected (demo).")
    }

    private func appendLog(_ line: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        logText += "[\(ts)] \(line)\n"
    }
}
