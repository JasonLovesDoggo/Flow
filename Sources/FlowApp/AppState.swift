//
// AppState.swift
// Flow
//
// Observable state for the Flow app.
//

import AppKit
import Combine
import Flow
import Foundation

/// Main app state observable
@MainActor
final class AppState: ObservableObject {
    /// The Flow engine
    let engine: Flow

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] \(message)")
    }

    /// Current recording state
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var isInitializingModel = false
    @Published var audioLevel: Float = 0.0
    @Published var smoothedAudioLevel: Float = 0.0

    /// Last transcribed text
    @Published var lastTranscription: String?

    /// Current writing mode
    @Published var currentMode: WritingMode = .casual

    /// Current app name (tracks frontmost app, including Flow itself)
    @Published var currentApp: String = "Unknown"

    /// Current app category
    @Published var currentCategory: AppCategory = .unknown

    /// Target app for mode configuration (the app before Flow became active)
    @Published var targetAppName: String = "Unknown"
    @Published var targetAppBundleId: String?
    @Published var targetAppMode: WritingMode = .casual
    @Published var targetAppCategory: AppCategory = .unknown

    /// Recent transcriptions
    @Published var history: [TranscriptionSummary] = []
    @Published var retryableHistoryId: String?

    /// API key configured
    @Published var isConfigured = false

    /// Current selected tab
    @Published var selectedTab: AppTab = .record

    /// Current recording hotkey
    @Published var hotkey: Hotkey
    @Published var isCapturingHotkey = false
    @Published var isAccessibilityEnabled = false
    @Published var isOnboardingComplete: Bool

    /// Error message to display
    @Published var errorMessage: String?

    /// Recording duration in milliseconds
    @Published var recordingDuration: UInt64 = 0

    /// Workspace observer for app changes
    private var workspaceObserver: NSObjectProtocol?
    private var recordingTimer: Timer?
    private var audioLevelTimer: Timer?
    private var modelLoadingTimer: Timer?
    private var helperManager: HelperManager?
    private var globeKeyHandler: GlobeKeyHandler? // Fallback if helper unavailable
    private var hotkeyCaptureMonitor: Any?
    private var hotkeyFlagsMonitor: Any?
    private var pendingModifierCapture: Hotkey.ModifierKey?
    private var appActiveObserver: NSObjectProtocol?
    private var appInactiveObserver: NSObjectProtocol?
    private var recordingIndicator: RecordingIndicatorWindow?
    private var targetApplication: NSRunningApplication?
    private let volumeManager = VolumeManager()
    private var textFieldContext: TextFieldContext?
    private var ideContext: IDEContext?

    private static let onboardingKey = "onboardingComplete"

    init() {
        engine = Flow()
        isConfigured = engine.isConfigured
        hotkey = Hotkey.load()
        isOnboardingComplete = UserDefaults.standard.bool(forKey: Self.onboardingKey)
        isAccessibilityEnabled = GlobeKeyHandler.isAccessibilityAuthorized()

        if !isAccessibilityEnabled {
            log("⚠️ [INIT] Accessibility NOT enabled - hotkey will not work globally!")
            log("⚠️ [INIT] Grant permission in System Settings > Privacy & Security > Accessibility")
        }

        setupGlobeKey()
        setupLifecycleObserver()
        setupWorkspaceObserver()
        setupModelLoadingPoller()
        updateCurrentApp()
        refreshHistory()

        // Configure the edit learning service
        EditLearningService.shared.configure(engine: engine)
    }

    func cleanup() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        if let observer = appActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            appActiveObserver = nil
        }
        if let observer = appInactiveObserver {
            NotificationCenter.default.removeObserver(observer)
            appInactiveObserver = nil
        }
        recordingTimer?.invalidate()
        recordingTimer = nil
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        modelLoadingTimer?.invalidate()
        modelLoadingTimer = nil
        helperManager?.stop()
        helperManager = nil
        globeKeyHandler = nil
        endHotkeyCapture()
        recordingIndicator?.hide()
    }

    // MARK: - Globe Key

    private func setupGlobeKey() {
        // Use HelperManager as primary (immune to App Nap)
        helperManager = HelperManager()
        helperManager?.onHotkeyTriggered = { [weak self] trigger in
            let globeTrigger: GlobeKeyHandler.Trigger = switch trigger {
            case .pressed: .pressed
            case .released: .released
            case .toggle: .toggle
            }
            self?.handleHotkeyTrigger(globeTrigger)
        }
        helperManager?.onError = { [weak self] message in
            self?.log("Helper error: \(message)")
        }
        helperManager?.updateHotkey(hotkey)
        helperManager?.start()
    }

    private func handleHotkeyTrigger(_ trigger: GlobeKeyHandler.Trigger) {
        log("🎹 [HOTKEY] Trigger detected: \(trigger)")

        // Check user's preferred activation mode
        let modeString = UserDefaults.standard.string(forKey: "hotkeyActivationMode") ?? "hold"
        let useToggleMode = modeString == "toggle"

        if useToggleMode {
            // Toggle mode: any trigger toggles recording state
            switch trigger {
            case .pressed:
                // First press starts recording
                toggleRecording()
            case .released:
                // Ignore release in toggle mode
                break
            case .toggle:
                toggleRecording()
            }
        } else {
            // Hold mode: press to start, release to stop
            switch trigger {
            case .pressed:
                if !isRecording {
                    startRecording()
                }
            case .released:
                if isRecording {
                    stopRecording()
                }
            case .toggle:
                // For custom hotkeys in hold mode, treat as toggle (legacy behavior)
                toggleRecording()
            }
        }
    }

    private func setupLifecycleObserver() {
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.refreshAccessibilityStatus()
            }
        }

        appInactiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.updateRecordingIndicatorVisibility()
            }
        }
    }

    private func setupModelLoadingPoller() {
        // Poll model loading state every 0.5 seconds
        modelLoadingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isLoading = self.engine.isModelLoading()
                if self.isInitializingModel != isLoading {
                    self.isInitializingModel = isLoading
                    self.updateRecordingIndicatorVisibility()
                }
            }
        }
    }

    func setHotkey(_ hotkey: Hotkey) {
        self.hotkey = hotkey
        hotkey.save()
        helperManager?.updateHotkey(hotkey)
        globeKeyHandler?.updateHotkey(hotkey)

    }

    func requestAccessibilityPermission() {
        let started = globeKeyHandler?.startListening(prompt: true) ?? false
        if started {
            isAccessibilityEnabled = true
            // Restart helper now that we have permission
            restartHelperIfNeeded()
        } else {
            refreshAccessibilityStatus()
        }
    }

    func refreshAccessibilityStatus() {
        let wasEnabled = isAccessibilityEnabled
        let enabled = GlobeKeyHandler.isAccessibilityAuthorized()
        isAccessibilityEnabled = enabled

        if !wasEnabled, enabled {
            restartHelperIfNeeded()
        }

        if enabled {
            _ = globeKeyHandler?.startListening(prompt: false)
        }
    }

    private func restartHelperIfNeeded() {
        guard let manager = helperManager, !manager.isRunning else { return }
        log("Restarting helper after accessibility permission granted")
        manager.start()
    }

    func clearError() {
        errorMessage = nil
    }

    func refreshHistory(limit: Int = 50) {
        history = engine.recentTranscriptions(limit: limit)
        if let latest = history.first, latest.status == .failed {
            retryableHistoryId = latest.id
        } else {
            retryableHistoryId = nil
        }
    }

    func completeOnboarding() {
        isOnboardingComplete = true
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
    }

    func beginHotkeyCapture() {
        guard hotkeyCaptureMonitor == nil, hotkeyFlagsMonitor == nil else { return }
        isCapturingHotkey = true
        pendingModifierCapture = nil

        // Monitor for key+modifier combos
        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            Task { @MainActor [weak self] in
                self?.handleHotkeyKeyCapture(event)
            }
            return nil
        }

        // Monitor for modifier-only hotkeys
        hotkeyFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            Task { @MainActor [weak self] in
                self?.handleHotkeyFlagsCapture(event)
            }
            return event
        }
    }

    func endHotkeyCapture() {
        if let monitor = hotkeyCaptureMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyCaptureMonitor = nil
        }
        if let monitor = hotkeyFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyFlagsMonitor = nil
        }
        isCapturingHotkey = false
        pendingModifierCapture = nil
    }

    private func handleHotkeyKeyCapture(_ event: NSEvent) {
        pendingModifierCapture = nil // Key pressed, cancel any pending modifier capture

        let modifiers = Hotkey.Modifiers.from(nsFlags: event.modifierFlags)
        if event.keyCode == UInt16(KeyCode.escape), modifiers.isEmpty {
            endHotkeyCapture()
            return
        }

        setHotkey(Hotkey.from(event: event))
        endHotkeyCapture()
    }

    private func handleHotkeyFlagsCapture(_ event: NSEvent) {
        // Detect single modifier press/release for modifier-only hotkeys
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Map NSEvent flags to our ModifierKey
        let modifierMappings: [(NSEvent.ModifierFlags, Hotkey.ModifierKey)] = [
            (.option, .option),
            (.shift, .shift),
            (.control, .control),
            (.command, .command),
        ]

        // Count how many modifiers are currently pressed
        var pressedModifier: Hotkey.ModifierKey?
        var count = 0
        for (flag, key) in modifierMappings {
            if flags.contains(flag) {
                pressedModifier = key
                count += 1
            }
        }

        if count == 1, let modifier = pressedModifier {
            // Single modifier pressed, start pending capture
            pendingModifierCapture = modifier
        } else if count == 0, let pending = pendingModifierCapture {
            // All modifiers released, if we had a pending single modifier, capture it
            setHotkey(Hotkey(kind: .modifierOnly(pending)))
            endHotkeyCapture()
        } else {
            // Multiple modifiers or no modifiers, cancel pending
            pendingModifierCapture = nil
        }
    }

    // MARK: - Workspace Observer

    private func setupWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let appName = app.localizedName ?? "Unknown"
            let bundleId = app.bundleIdentifier

            Task { @MainActor [weak self] in
                self?.handleAppActivation(appName: appName, bundleId: bundleId)
            }
        }
    }

    private func handleAppActivation(appName: String, bundleId: String?) {
        currentApp = appName

        // Check if Flow itself became active
        let isFlow = bundleId == Bundle.main.bundleIdentifier

        if !isFlow {
            // This is an external app - save it as the target for mode configuration
            targetAppName = appName
            targetAppBundleId = bundleId

            let suggestedMode = engine.setActiveApp(name: appName, bundleId: bundleId)
            currentCategory = engine.currentAppCategory
            targetAppCategory = currentCategory

            if let styleSuggestion = engine.styleSuggestion {
                currentMode = styleSuggestion
                targetAppMode = styleSuggestion
            } else {
                currentMode = suggestedMode
                targetAppMode = suggestedMode
            }
        } else {
            // Flow became active - preserve the target app for mode changes
            // Update currentMode to reflect the target app's mode
            currentMode = targetAppMode
            currentCategory = targetAppCategory
        }
    }

    private func updateCurrentApp() {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let appName = frontApp.localizedName ?? "Unknown"
            let bundleId = frontApp.bundleIdentifier

            currentApp = appName

            // Initialize target app if this is not Flow
            let isFlow = bundleId == Bundle.main.bundleIdentifier
            if !isFlow {
                targetAppName = appName
                targetAppBundleId = bundleId
            }

            let suggestedMode = engine.setActiveApp(name: appName, bundleId: bundleId)
            currentCategory = engine.currentAppCategory
            currentMode = suggestedMode

            if !isFlow {
                targetAppMode = suggestedMode
                targetAppCategory = currentCategory
            }
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
        let totalStart = CFAbsoluteTimeGetCurrent()

        // Refresh accessibility status before recording
        let t0 = CFAbsoluteTimeGetCurrent()
        refreshAccessibilityStatus()
        log("⏱️ [TIMING] refreshAccessibilityStatus: \(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")

        guard isAccessibilityEnabled else {
            errorMessage = "Accessibility permission required for hotkey. Enable in System Settings > Privacy & Security > Accessibility."
            log("⚠️ [RECORDING] Blocked - Accessibility not enabled")
            return
        }

        guard engine.isConfigured else {
            errorMessage = "Please configure your API key in Settings"
            return
        }

        targetApplication = NSWorkspace.shared.frontmostApplication

        log("🎤 [RECORDING] Starting recording - App: \(currentApp), Mode: \(currentMode.displayName)")

        // Update UI immediately for instant feedback
        isRecording = true
        isProcessing = false
        updateRecordingIndicatorVisibility()
        recordingDuration = 0
        log("⏱️ [TIMING] UI updated: \(Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000))ms")

        // Play start sound
        AudioFeedback.shared.playStart()

        // Start engine and setup timers in a task so UI can update first
        Task { @MainActor [weak self] in
            guard let self else { return }

            let t = CFAbsoluteTimeGetCurrent()
            self.volumeManager.muteForRecording()
            self.log("⏱️ [TIMING] muteForRecording: \(Int((CFAbsoluteTimeGetCurrent() - t) * 1000))ms")

            let engineStart = CFAbsoluteTimeGetCurrent()
            if self.engine.startRecording() {
                self.log("⏱️ [TIMING] engine.startRecording: \(Int((CFAbsoluteTimeGetCurrent() - engineStart) * 1000))ms")
                self.log("⏱️ [TIMING] TOTAL: \(Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000))ms")

                // Extract context in background
                Task.detached { [weak self] in
                    let textContext = AccessibilityContext.extractFocusedTextContext()
                    let ide = AccessibilityContext.extractIDEContext()
                    if let self = self {
                        await MainActor.run {
                            self.textFieldContext = textContext
                            self.ideContext = ide
                        }
                    }
                }

                self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.isRecording else { return }
                        self.recordingDuration += 100
                    }
                }

                self.audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.isRecording else { return }
                        let newLevel = self.engine.audioLevel
                        self.audioLevel = newLevel
                        let smoothingFactor: Float = 0.8
                        self.smoothedAudioLevel = self.smoothedAudioLevel * (1 - smoothingFactor) + newLevel * smoothingFactor
                    }
                }
            } else {
                // Revert UI state
                self.isRecording = false
                self.updateRecordingIndicatorVisibility()
                self.errorMessage = self.engine.lastError ?? "Failed to start recording"
                AudioFeedback.shared.playError()
                self.volumeManager.restoreAfterRecording()
            }
        }
    }

    func stopRecording() {
        log("⏹️ [RECORDING] Stopping recording - Duration: \(recordingDuration)ms")

        // Play stop sound immediately so user gets instant feedback
        AudioFeedback.shared.playStop()

        recordingTimer?.invalidate()
        recordingTimer = nil
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        audioLevel = 0.0
        smoothedAudioLevel = 0.0

        let duration = engine.stopRecording()
        isRecording = false

        // Restore volume immediately (was muted to prevent feedback)
        volumeManager.restoreAfterRecording()

        if duration > 0 {
            log("✅ [RECORDING] Recording stopped successfully - Duration: \(duration)ms")
            setProcessing(true)
            transcribe()
        } else {
            log("⚠️ [RECORDING] Recording cancelled (too short)")
            updateRecordingIndicatorVisibility()
        }
    }

    private func transcribe() {
        let appName = currentApp
        let appCategory = currentCategory
        let mode = currentMode
        let duration = recordingDuration

        log("🔄 [TRANSCRIBE] Starting transcription - App: \(appName), Mode: \(mode.displayName)")

        Task.detached { [weak self] in
            guard let self else { return }
            let result = await Task {
                self.engine.transcribe(appName: appName)
            }.value

            await MainActor.run { [weak self] in
                guard let self else { return }
                if let text = result {
                    self.log("✅ [TRANSCRIBE] Transcription completed - Length: \(text.count) chars")
                    self.log("📝 [TRANSCRIBE] Result: \(text.prefix(100))...")
                    self.lastTranscription = text
                    self.errorMessage = nil
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    self.log("📋 [CLIPBOARD] Text copied to clipboard")

                    self.activateTargetAppIfNeeded()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                        self?.pasteText()
                        self?.finishProcessing()
                    }
                    self.refreshHistory()
                } else {
                    let errorMsg = self.engine.lastError ?? "Transcription failed"
                    self.log("❌ [TRANSCRIBE] Transcription failed: \(errorMsg)")
                    self.errorMessage = errorMsg

                    // Play error sound to alert user
                    AudioFeedback.shared.playError()

                    self.refreshHistory()
                    self.finishProcessing()
                }
            }
        }
    }

    func retryLastTranscription() {
        setProcessing(true)
        let appName = currentApp

        Task.detached { [weak self] in
            guard let self else { return }
            let result = await Task {
                self.engine.retryLastTranscription(appName: appName)
            }.value

            await MainActor.run { [weak self] in
                guard let self else { return }
                if let text = result {
                    self.lastTranscription = text
                    self.errorMessage = nil
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)

                    self.activateTargetAppIfNeeded()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                        self?.pasteText()
                        self?.finishProcessing()
                    }
                    self.refreshHistory()
                } else {
                    let errorMsg = self.engine.lastError ?? "Retry failed"
                    self.errorMessage = errorMsg

                    AudioFeedback.shared.playError()

                    self.refreshHistory()
                    self.finishProcessing()
                }
            }
        }
    }

    private func pasteText() {
        log("📌 [PASTE] Sending paste command (Cmd+V) to app: \(targetApplication?.localizedName ?? "Unknown")")
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        log("✅ [PASTE] Paste command sent successfully")

        // Start monitoring for edits to learn from user corrections
        if let pastedText = lastTranscription {
            EditLearningService.shared.startMonitoring(
                originalText: pastedText,
                targetApp: targetApplication
            )
        }
    }

    private func activateTargetAppIfNeeded() {
        guard let app = targetApplication else { return }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }
        if #available(macOS 14, *) {
            _ = app.activate(options: [.activateAllWindows])
        } else {
            _ = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }

    private func ensureRecordingIndicator() {
        if recordingIndicator == nil {
            recordingIndicator = RecordingIndicatorWindow(appState: self)
        }
    }

    private func setProcessing(_ processing: Bool) {
        isProcessing = processing
        updateRecordingIndicatorVisibility()
    }

    private func finishProcessing() {
        setProcessing(false)
    }

    private func updateRecordingIndicatorVisibility() {
        if isRecording || isProcessing || isInitializingModel {
            ensureRecordingIndicator()
            recordingIndicator?.show()
        } else {
            recordingIndicator?.hide()
        }
    }

    // MARK: - Settings

    func setApiKey(_ key: String, for provider: CompletionProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if engine.setCompletionProvider(provider, apiKey: trimmed) {
            isConfigured = engine.isConfigured
            errorMessage = nil
        } else {
            isConfigured = engine.isConfigured
            errorMessage = engine.lastError ?? "Failed to set \(provider.displayName) API key"
        }
    }

    func setProvider(_ provider: CompletionProvider, apiKey: String? = nil) {
        let success: Bool
        if let key = apiKey, !key.isEmpty {
            // Save API key and switch provider
            success = engine.setCompletionProvider(provider, apiKey: key)
        } else {
            // Just switch provider using saved key
            success = engine.switchCompletionProvider(provider)
        }

        if success {
            isConfigured = engine.isConfigured
            errorMessage = nil
        } else {
            isConfigured = engine.isConfigured
            errorMessage = engine.lastError ?? "Failed to set provider"
        }
    }

    func setMode(_ mode: WritingMode) {
        // Always set the mode for the target app (not Flow itself)
        if engine.setMode(mode, for: targetAppName) {
            currentMode = mode
            targetAppMode = mode
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

    var todayTranscriptions: Int {
        let calendar = Calendar.current
        return history.filter { calendar.isDateInToday($0.createdAt) }.count
    }

    var totalTranscriptions: Int {
        (engine.stats?["total_transcriptions"] as? Int) ?? 0
    }

    var totalMinutes: Int {
        let ms = (engine.stats?["total_duration_ms"] as? Int) ?? 0
        return ms / 60000
    }

    var totalWordsDictated: Int {
        (engine.stats?["total_words_dictated"] as? Int) ?? 0
    }
}
