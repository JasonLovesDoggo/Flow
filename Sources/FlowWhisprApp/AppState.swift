//
// AppState.swift
// FlowWhispr
//
// Observable state for the FlowWhispr app.
//

import AppKit
import Combine
import FlowWhispr
import Foundation

/// Main app state observable
@MainActor
final class AppState: ObservableObject {
    /// The FlowWhispr engine
    let engine: FlowWhispr

    /// Current recording state
    @Published var isRecording = false

    /// Last transcribed text
    @Published var lastTranscription: String?

    /// Current writing mode
    @Published var currentMode: WritingMode = .casual

    /// Current app name
    @Published var currentApp: String = "Unknown"

    /// Current app category
    @Published var currentCategory: AppCategory = .unknown

    /// API key configured
    @Published var isConfigured = false

    /// Error message to display
    @Published var errorMessage: String?

    /// Recording duration in milliseconds
    @Published var recordingDuration: UInt64 = 0

    /// Workspace observer for app changes
    private var workspaceObserver: NSObjectProtocol?
    private var recordingTimer: Timer?
    private var globeKeyHandler: GlobeKeyHandler?

    init() {
        self.engine = FlowWhispr()
        self.isConfigured = engine.isConfigured

        setupGlobeKey()
        setupWorkspaceObserver()
        updateCurrentApp()
    }

    func cleanup() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    // MARK: - Globe Key

    private func setupGlobeKey() {
        globeKeyHandler = GlobeKeyHandler { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
    }

    // MARK: - Workspace Observer

    private func setupWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let appName = app.localizedName ?? "Unknown"
            let bundleId = app.bundleIdentifier

            Task { @MainActor in
                self?.handleAppActivation(appName: appName, bundleId: bundleId)
            }
        }
    }

    private func handleAppActivation(appName: String, bundleId: String?) {
        currentApp = appName
        let suggestedMode = engine.setActiveApp(name: appName, bundleId: bundleId)
        currentCategory = engine.currentAppCategory

        if let styleSuggestion = engine.styleSuggestion {
            currentMode = styleSuggestion
        } else {
            currentMode = suggestedMode
        }
    }

    private func updateCurrentApp() {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let appName = frontApp.localizedName ?? "Unknown"
            let bundleId = frontApp.bundleIdentifier

            currentApp = appName
            let suggestedMode = engine.setActiveApp(name: appName, bundleId: bundleId)
            currentCategory = engine.currentAppCategory
            currentMode = suggestedMode
        }
    }

    // MARK: - Recording

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard engine.isConfigured else {
            errorMessage = "Please configure your API key in Settings"
            return
        }

        if engine.startRecording() {
            isRecording = true
            recordingDuration = 0

            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    if let self = self, self.isRecording {
                        self.recordingDuration += 100
                    }
                }
            }
        } else {
            errorMessage = "Failed to start recording"
        }
    }

    func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil

        let duration = engine.stopRecording()
        isRecording = false

        if duration > 0 {
            transcribe()
        }
    }

    private func transcribe() {
        Task {
            let result = engine.transcribe(appName: currentApp)
            await MainActor.run {
                if let text = result {
                    lastTranscription = text
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    pasteText()
                } else {
                    errorMessage = "Transcription failed"
                }
            }
        }
    }

    private func pasteText() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Settings

    func setApiKey(_ key: String) {
        if engine.setApiKey(key) {
            isConfigured = engine.isConfigured
            errorMessage = nil
        } else {
            errorMessage = "Failed to set API key"
        }
    }

    func setAnthropicKey(_ key: String) {
        if engine.setAnthropicKey(key) {
            isConfigured = true
            errorMessage = nil
        } else {
            errorMessage = "Failed to set Anthropic API key"
        }
    }

    func setMode(_ mode: WritingMode) {
        if engine.setMode(mode, for: currentApp) {
            currentMode = mode
        }
    }

    // MARK: - Shortcuts

    func addShortcut(trigger: String, replacement: String) -> Bool {
        return engine.addShortcut(trigger: trigger, replacement: replacement)
    }

    func removeShortcut(trigger: String) -> Bool {
        return engine.removeShortcut(trigger: trigger)
    }

    // MARK: - Stats

    var totalTranscriptions: Int {
        (engine.stats?["total_transcriptions"] as? Int) ?? 0
    }

    var totalMinutes: Int {
        let ms = (engine.stats?["total_duration_ms"] as? Int) ?? 0
        return ms / 60000
    }
}
