//
// FlowWhispr.swift
// FlowWhispr Swift Wrapper
//
// A Swift-friendly interface to the FlowWhispr Rust core.
//

import CFlowWhispr
import Foundation

/// Writing modes for text style adjustment
public enum WritingMode: UInt8, Sendable {
    case formal = 0
    case casual = 1
    case veryCasual = 2
    case excited = 3
}

/// Main interface to the FlowWhispr engine
public final class FlowWhispr: @unchecked Sendable {
    private let handle: OpaquePointer?

    /// Initialize the FlowWhispr engine
    /// - Parameter dbPath: Optional path to the SQLite database. If nil, uses default location.
    public init(dbPath: String? = nil) {
        if let path = dbPath {
            handle = path.withCString { cPath in
                flowwhispr_init(cPath)
            }
        } else {
            handle = flowwhispr_init(nil)
        }
    }

    deinit {
        if let handle = handle {
            flowwhispr_destroy(handle)
        }
    }

    /// Check if the engine is properly initialized
    public var isInitialized: Bool {
        handle != nil
    }

    // MARK: - Audio

    /// Start audio recording
    /// - Returns: true if recording started successfully
    public func startRecording() -> Bool {
        guard let handle = handle else { return false }
        return flowwhispr_start_recording(handle)
    }

    /// Stop audio recording
    /// - Returns: Duration of the recording in milliseconds, or 0 on failure
    public func stopRecording() -> UInt64 {
        guard let handle = handle else { return 0 }
        return flowwhispr_stop_recording(handle)
    }

    /// Check if currently recording
    public var isRecording: Bool {
        guard let handle = handle else { return false }
        return flowwhispr_is_recording(handle)
    }

    // MARK: - Transcription

    /// Transcribe the recorded audio and process it
    /// - Parameter appName: Optional name of the current app for mode selection
    /// - Returns: Processed text, or nil on failure
    public func transcribe(appName: String? = nil) -> String? {
        guard let handle = handle else { return nil }

        let result: UnsafeMutablePointer<CChar>?
        if let app = appName {
            result = app.withCString { cApp in
                flowwhispr_transcribe(handle, cApp)
            }
        } else {
            result = flowwhispr_transcribe(handle, nil)
        }

        guard let cString = result else { return nil }
        let string = String(cString: cString)
        flowwhispr_free_string(cString)
        return string
    }

    // MARK: - Shortcuts

    /// Add a voice shortcut
    /// - Parameters:
    ///   - trigger: The trigger phrase
    ///   - replacement: The replacement text
    /// - Returns: true on success
    public func addShortcut(trigger: String, replacement: String) -> Bool {
        guard let handle = handle else { return false }
        return trigger.withCString { cTrigger in
            replacement.withCString { cReplacement in
                flowwhispr_add_shortcut(handle, cTrigger, cReplacement)
            }
        }
    }

    /// Remove a voice shortcut
    /// - Parameter trigger: The trigger phrase to remove
    /// - Returns: true on success
    public func removeShortcut(trigger: String) -> Bool {
        guard let handle = handle else { return false }
        return trigger.withCString { cTrigger in
            flowwhispr_remove_shortcut(handle, cTrigger)
        }
    }

    /// Get the number of shortcuts
    public var shortcutCount: Int {
        guard let handle = handle else { return 0 }
        return flowwhispr_shortcut_count(handle)
    }

    // MARK: - Writing Modes

    /// Set the writing mode for an app
    /// - Parameters:
    ///   - mode: The writing mode to set
    ///   - appName: The name of the app
    /// - Returns: true on success
    public func setMode(_ mode: WritingMode, for appName: String) -> Bool {
        guard let handle = handle else { return false }
        return appName.withCString { cApp in
            flowwhispr_set_app_mode(handle, cApp, mode.rawValue)
        }
    }

    /// Get the writing mode for an app
    /// - Parameter appName: The name of the app
    /// - Returns: The writing mode for the app
    public func getMode(for appName: String) -> WritingMode {
        guard let handle = handle else { return .casual }
        let rawValue = appName.withCString { cApp in
            flowwhispr_get_app_mode(handle, cApp)
        }
        return WritingMode(rawValue: rawValue) ?? .casual
    }

    // MARK: - Learning

    /// Report a user edit to learn from
    /// - Parameters:
    ///   - original: The original transcribed text
    ///   - edited: The text after user edits
    /// - Returns: true on success
    public func learnFromEdit(original: String, edited: String) -> Bool {
        guard let handle = handle else { return false }
        return original.withCString { cOriginal in
            edited.withCString { cEdited in
                flowwhispr_learn_from_edit(handle, cOriginal, cEdited)
            }
        }
    }

    /// Get the number of learned corrections
    public var correctionCount: Int {
        guard let handle = handle else { return 0 }
        return flowwhispr_correction_count(handle)
    }

    // MARK: - Stats

    /// Get total transcription time in minutes
    public var totalTranscriptionMinutes: UInt64 {
        guard let handle = handle else { return 0 }
        return flowwhispr_total_transcription_minutes(handle)
    }

    /// Get total transcription count
    public var transcriptionCount: UInt64 {
        guard let handle = handle else { return 0 }
        return flowwhispr_transcription_count(handle)
    }

    // MARK: - Configuration

    /// Check if the transcription provider is configured
    public var isConfigured: Bool {
        guard let handle = handle else { return false }
        return flowwhispr_is_configured(handle)
    }

    /// Set the OpenAI API key
    /// - Parameter apiKey: The OpenAI API key
    /// - Returns: true on success
    public func setApiKey(_ apiKey: String) -> Bool {
        guard let handle = handle else { return false }
        return apiKey.withCString { cKey in
            flowwhispr_set_api_key(handle, cKey)
        }
    }
}
