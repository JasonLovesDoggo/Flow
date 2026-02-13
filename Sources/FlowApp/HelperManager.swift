//
// HelperManager.swift
// Flow
//
// Manages the FlowHelper process for reliable background hotkey detection.
// The helper is an LSUIElement app that runs CGEventTap without App Nap restrictions.
//

import Foundation

/// Manages communication with the FlowHelper process
final class HelperManager {
    /// Hotkey trigger callback (same type as GlobeKeyHandler.Trigger)
    enum Trigger {
        case pressed
        case released
        case toggle
    }

    private var helperProcess: Process?
    private var outputPipe: Pipe?
    private var inputPipe: Pipe?
    private var outputBuffer = Data()
    private var isReady = false
    private var pendingHotkey: Hotkey?
    private var restartCount = 0
    private let maxRestarts = 5

    var onHotkeyTriggered: ((Trigger) -> Void)?
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] [HELPER] \(message)")
    }

    /// Start the helper process
    func start() {
        guard helperProcess == nil else {
            log("Helper already running")
            return
        }

        let process = Process()

        // Look for helper in multiple locations
        let helperURL = findHelperURL()
        guard let url = helperURL else {
            log("FlowHelper not found")
            onError?("FlowHelper not found")
            return
        }

        log("Starting helper from: \(url.path)")
        process.executableURL = url

        // Setup pipes for communication
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice

        outputPipe = output
        inputPipe = input

        // Handle helper output (JSON events)
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                // EOF - helper terminated
                DispatchQueue.main.async {
                    self?.handleHelperTerminated()
                }
                return
            }
            self?.handleOutput(data)
        }

        // Handle process termination
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.log("Helper terminated with status: \(proc.terminationStatus)")
                self?.handleHelperTerminated()
            }
        }

        do {
            try process.run()
            helperProcess = process
            log("Helper started with PID: \(process.processIdentifier)")
        } catch {
            log("Failed to start helper: \(error)")
            onError?("Failed to start helper: \(error.localizedDescription)")
        }
    }

    /// Stop the helper process
    func stop() {
        guard let process = helperProcess else { return }

        log("Stopping helper")
        sendCommand(["command": "quit"])

        // Give it a moment to exit gracefully, then terminate
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if process.isRunning {
                process.terminate()
            }
            DispatchQueue.main.async {
                self?.cleanup()
            }
        }
    }

    /// Update the hotkey configuration
    func updateHotkey(_ hotkey: Hotkey) {
        if !isReady {
            // Store for when helper becomes ready
            pendingHotkey = hotkey
            return
        }

        let config = hotkeyConfig(from: hotkey)
        sendCommand([
            "command": "setHotkey",
            "hotkey": config,
        ])
    }

    /// Check if the helper is running
    var isRunning: Bool {
        helperProcess?.isRunning ?? false
    }

    // MARK: - Private

    private func findHelperURL() -> URL? {
        // Check multiple locations for the helper binary

        // 1. Inside the app bundle (for production)
        if let bundleURL = Bundle.main.url(forResource: "FlowHelper", withExtension: nil, subdirectory: "Helpers") {
            log("Found helper in bundle: \(bundleURL.path)")
            return bundleURL
        }

        // 2. In the same directory as the main executable (for development)
        if let execURL = Bundle.main.executableURL {
            let siblingURL = execURL.deletingLastPathComponent().appendingPathComponent("FlowHelper")
            if FileManager.default.fileExists(atPath: siblingURL.path) {
                log("Found helper next to executable: \(siblingURL.path)")
                return siblingURL
            }
        }

        // 3. Relative to the executable's parent (for Swift Package build structure)
        // When running from .build/debug/Flow, helper is in FlowHelper/.build/debug/FlowHelper
        if let execURL = Bundle.main.executableURL {
            // .build/debug/Flow -> .build -> flow -> FlowHelper/.build/debug/FlowHelper
            let projectRoot = execURL
                .deletingLastPathComponent() // debug
                .deletingLastPathComponent() // .build
            let debugPath = projectRoot.appendingPathComponent("FlowHelper/.build/debug/FlowHelper")
            let releasePath = projectRoot.appendingPathComponent("FlowHelper/.build/release/FlowHelper")

            if FileManager.default.fileExists(atPath: debugPath.path) {
                log("Found helper in FlowHelper build: \(debugPath.path)")
                return debugPath
            }
            if FileManager.default.fileExists(atPath: releasePath.path) {
                log("Found helper in FlowHelper build: \(releasePath.path)")
                return releasePath
            }
        }

        // 4. Relative to current working directory (for development/testing)
        let buildPaths = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("FlowHelper/.build/debug/FlowHelper"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("FlowHelper/.build/release/FlowHelper"),
        ]

        for path in buildPaths {
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }

        return nil
    }

    private func handleOutput(_ data: Data) {
        outputBuffer.append(data)

        // Process complete JSON lines
        while let newlineIndex = outputBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = outputBuffer[..<newlineIndex]
            outputBuffer = Data(outputBuffer[(newlineIndex + 1)...])

            guard let line = String(data: lineData, encoding: .utf8),
                  !line.isEmpty,
                  let jsonData = line.data(using: .utf8)
            else { continue }

            processMessage(jsonData)
        }
    }

    private func processMessage(_ data: Data) {
        // Try to decode as a generic dictionary first to check event type
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = dict["event"] as? String
        else { return }

        switch eventType {
        case "ready":
            DispatchQueue.main.async { [weak self] in
                self?.handleReady()
            }

        case "hotkey":
            guard let trigger = dict["trigger"] as? String else { return }
            let triggerType: Trigger
            switch trigger {
            case "pressed": triggerType = .pressed
            case "released": triggerType = .released
            case "toggle": triggerType = .toggle
            default: return
            }

            DispatchQueue.main.async { [weak self] in
                self?.log("Hotkey triggered: \(trigger)")
                self?.onHotkeyTriggered?(triggerType)
            }

        case "error":
            let message = dict["message"] as? String ?? "Unknown error"
            DispatchQueue.main.async { [weak self] in
                self?.log("Helper error: \(message)")
                self?.onError?(message)
            }

        default:
            break
        }
    }

    private func handleReady() {
        log("Helper ready")
        isReady = true
        restartCount = 0

        // Send any pending hotkey config
        if let hotkey = pendingHotkey {
            updateHotkey(hotkey)
            pendingHotkey = nil
        }

        onReady?()
    }

    private func handleHelperTerminated() {
        log("Helper terminated unexpectedly")
        cleanup()

        restartCount += 1
        if restartCount > maxRestarts {
            log("Helper exceeded max restarts (\(maxRestarts)), giving up")
            onError?("Helper crashed too many times")
            return
        }

        // Auto-restart after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.log("Auto-restarting helper (attempt \(self?.restartCount ?? 0)/\(self?.maxRestarts ?? 0))")
            self?.start()
        }
    }

    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        inputPipe = nil
        helperProcess = nil
        isReady = false
        outputBuffer = Data()
    }

    private func sendCommand(_ command: [String: Any]) {
        guard let input = inputPipe,
              let data = try? JSONSerialization.data(withJSONObject: command),
              var json = String(data: data, encoding: .utf8)
        else { return }

        json += "\n"
        if let jsonData = json.data(using: .utf8) {
            input.fileHandleForWriting.write(jsonData)
        }
    }

    private func hotkeyConfig(from hotkey: Hotkey) -> [String: Any] {
        switch hotkey.kind {
        case .globe:
            return ["kind": "globe"]

        case let .modifierOnly(modifier):
            return [
                "kind": "modifierOnly",
                "modifier": modifier.rawValue,
            ]

        case let .custom(keyCode, modifiers, _):
            return [
                "kind": "custom",
                "keyCode": keyCode,
                "modifiers": modifiers.rawValue,
            ]
        }
    }
}
