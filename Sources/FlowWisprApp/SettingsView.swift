//
// SettingsView.swift
// FlowWispr
//
// Settings content view with sections for API, general settings, and about.
//

import AppKit
import FlowWispr
import SwiftUI

struct SettingsContentView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: FW.spacing24) {
                APISettingsSection()
                Divider()
                GeneralSettingsSection()
                Divider()
                AccessibilitySection()
                Divider()
                AboutSection()
            }
            .padding(FW.spacing24)
        }
    }
}

// MARK: - API Settings

struct APISettingsSection: View {
    @EnvironmentObject var appState: AppState
    @State private var openAIKey = ""
    @State private var showOpenAIKey = false
    @State private var geminiKey = ""
    @State private var showGeminiKey = false
    @State private var openRouterKey = ""
    @State private var showOpenRouterKey = false
    @State private var selectedProvider: CompletionProvider = .openAI

    var body: some View {
        VStack(alignment: .leading, spacing: FW.spacing16) {
            Label("API Keys", systemImage: "key")
                .font(.headline)

            // Provider Selection
            VStack(alignment: .leading, spacing: FW.spacing8) {
                Text("Active Provider")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FW.textPrimary)

                Picker("", selection: $selectedProvider) {
                    ForEach([CompletionProvider.openAI, CompletionProvider.gemini, CompletionProvider.openRouter], id: \.rawValue) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: selectedProvider) { _, newProvider in
                    // Switch provider when selection changes
                    let apiKey: String
                    switch newProvider {
                    case .openAI: apiKey = openAIKey
                    case .gemini: apiKey = geminiKey
                    case .openRouter: apiKey = openRouterKey
                    }
                    if !apiKey.isEmpty {
                        appState.setProvider(newProvider, apiKey: apiKey)
                    }
                }
                .onAppear {
                    // Load current provider
                    if let current = appState.engine.completionProvider {
                        selectedProvider = current
                    }
                }

                if let current = appState.engine.completionProvider {
                    Text("Currently using: \(current.displayName)")
                        .font(.caption)
                        .foregroundStyle(FW.textTertiary)
                }
            }

            Divider()

            // OpenAI
            VStack(alignment: .leading, spacing: FW.spacing8) {
                Text("OpenAI (Whisper)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FW.textPrimary)

                HStack {
                    Group {
                        if showOpenAIKey {
                            TextField("sk-...", text: $openAIKey)
                        } else {
                            SecureField("sk-...", text: $openAIKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(FW.fontMonoSmall)

                    Button {
                        showOpenAIKey.toggle()
                    } label: {
                        Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)

                    Button("Save") {
                        appState.setApiKey(openAIKey)
                        if selectedProvider == .openAI {
                            appState.setProvider(.openAI, apiKey: openAIKey)
                        }
                    }
                    .buttonStyle(FWSecondaryButtonStyle())
                    .disabled(openAIKey.isEmpty)
                }

                Text("Required for transcription")
                    .font(.caption)
                    .foregroundStyle(FW.textTertiary)
            }

            // Gemini
            VStack(alignment: .leading, spacing: FW.spacing8) {
                Text("Gemini")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FW.textPrimary)

                HStack {
                    Group {
                        if showGeminiKey {
                            TextField("AI...", text: $geminiKey)
                        } else {
                            SecureField("AI...", text: $geminiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(FW.fontMonoSmall)

                    Button {
                        showGeminiKey.toggle()
                    } label: {
                        Image(systemName: showGeminiKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)

                    Button("Save") {
                        appState.setGeminiApiKey(geminiKey)
                        if selectedProvider == .gemini {
                            appState.setProvider(.gemini, apiKey: geminiKey)
                        }
                    }
                    .buttonStyle(FWSecondaryButtonStyle())
                    .disabled(geminiKey.isEmpty)
                }

                Text("Alternative provider for transcription and completion")
                    .font(.caption)
                    .foregroundStyle(FW.textTertiary)
            }

            // OpenRouter
            VStack(alignment: .leading, spacing: FW.spacing8) {
                Text("OpenRouter")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FW.textPrimary)

                HStack {
                    Group {
                        if showOpenRouterKey {
                            TextField("sk-or-v1-...", text: $openRouterKey)
                        } else {
                            SecureField("sk-or-v1-...", text: $openRouterKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(FW.fontMonoSmall)

                    Button {
                        showOpenRouterKey.toggle()
                    } label: {
                        Image(systemName: showOpenRouterKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)

                    Button("Save") {
                        appState.setOpenRouterApiKey(openRouterKey)
                        if selectedProvider == .openRouter {
                            appState.setProvider(.openRouter, apiKey: openRouterKey)
                        }
                    }
                    .buttonStyle(FWSecondaryButtonStyle())
                    .disabled(openRouterKey.isEmpty)
                }

                Text("Access multiple LLM providers (Llama, Claude, GPT, etc.)")
                    .font(.caption)
                    .foregroundStyle(FW.textTertiary)
            }

            // Status
            HStack(spacing: FW.spacing8) {
                Circle()
                    .fill(appState.isConfigured ? FW.success : FW.warning)
                    .frame(width: 10, height: 10)

                Text(appState.isConfigured ? "API configured" : "API key required")
                    .foregroundStyle(appState.isConfigured ? FW.success : FW.warning)
            }
            .padding(.top, FW.spacing8)
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsSection: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("playSounds") private var playSounds = true
    @AppStorage("defaultMode") private var defaultMode = 1

    var body: some View {
        VStack(alignment: .leading, spacing: FW.spacing16) {
            Label("General", systemImage: "gear")
                .font(.headline)

            VStack(alignment: .leading, spacing: FW.spacing12) {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Play sounds", isOn: $playSounds)
            }

            VStack(alignment: .leading, spacing: FW.spacing8) {
                Text("Default writing mode")
                    .font(.subheadline.weight(.medium))

                Picker("", selection: $defaultMode) {
                    ForEach(WritingMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(Int(mode.rawValue))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if let mode = WritingMode(rawValue: UInt8(defaultMode)) {
                    Text(mode.description)
                        .font(.caption)
                        .foregroundStyle(FW.textTertiary)
                }
            }
        }
    }
}

// MARK: - Accessibility
struct AccessibilitySection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: FW.spacing16) {
            Label("Keyboard", systemImage: "keyboard")
                .font(.headline)

            VStack(alignment: .leading, spacing: FW.spacing8) {
                HStack(spacing: FW.spacing8) {
                    Text("🌐")
                        .font(.title2)
                    Text("Fn key is the default hotkey")
                        .font(.subheadline.weight(.medium))
                }

                Text("Hold the Fn key to record, release to stop. Custom hotkeys toggle recording. This requires Accessibility permission.")
                    .font(.caption)
                    .foregroundStyle(FW.textSecondary)

                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(FWSecondaryButtonStyle())
                .padding(.top, FW.spacing4)
            }

            Divider()

            VStack(alignment: .leading, spacing: FW.spacing8) {
                Text("Recording hotkey")
                    .font(.subheadline.weight(.medium))

                Text("Current: \(appState.hotkey.displayName)")
                    .font(.caption)
                    .foregroundStyle(FW.textSecondary)

                HStack(spacing: FW.spacing12) {
                    Button(appState.isCapturingHotkey ? "Press keys..." : "Change Hotkey") {
                        if appState.isCapturingHotkey {
                            appState.endHotkeyCapture()
                        } else {
                            appState.beginHotkeyCapture()
                        }
                    }
                    .buttonStyle(FWSecondaryButtonStyle())

                    Button("Use Fn Key") {
                        appState.setHotkey(Hotkey.defaultHotkey)
                    }
                    .buttonStyle(FWSecondaryButtonStyle())
                }

                if appState.isCapturingHotkey {
                    Text("Press a key combination, or Esc to cancel.")
                        .font(.caption)
                        .foregroundStyle(FW.textTertiary)
                }
            }
        }
        .onDisappear {
            if appState.isCapturingHotkey {
                appState.endHotkeyCapture()
            }
        }
    }
}

// MARK: - About

struct AboutSection: View {
    var body: some View {
        VStack(spacing: FW.spacing16) {
            // logo
            ZStack {
                Circle()
                    .fill(FW.accentGradient)
                    .frame(width: 60, height: 60)

                Image(systemName: "waveform")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(spacing: FW.spacing4) {
                Text("Flow")
                    .font(.title3.weight(.semibold))

                Text("v1.0.0")
                    .font(FW.fontMonoSmall)
                    .foregroundStyle(FW.textTertiary)
            }

            Text("Voice dictation powered by AI")
                .font(.subheadline)
                .foregroundStyle(FW.textSecondary)

            HStack(spacing: FW.spacing24) {
                Link(destination: URL(string: "https://gowithflow.tech")!) {
                    HStack(spacing: FW.spacing4) {
                        Image(systemName: "globe")
                        Text("Website")
                    }
                    .font(.caption)
                    .foregroundStyle(FW.accent)
                }

                Link(destination: URL(string: "https://github.com/jasonlovesdoggo/flow")!) {
                    HStack(spacing: FW.spacing4) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text("GitHub")
                    }
                    .font(.caption)
                    .foregroundStyle(FW.accent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FW.spacing16)
    }
}

#Preview {
    SettingsContentView()
        .environmentObject(AppState())
}
