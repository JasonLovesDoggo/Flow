//
// SettingsView.swift
// Flow
//
// Clean, minimal settings with vertical sections. Swedish minimalism vibes.
//

import AppKit
import Flow
import SwiftUI

struct SettingsContentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FW.spacing24) {
                Text("Settings")
                    .font(.title.weight(.bold))
                    .foregroundStyle(FW.textPrimary)

                TranscriptionSection()
                APIKeysSection()
                GeneralSection()
                KeyboardSection()
                StatsSection()

                Divider()
                    .background(FW.border)

                AboutFooter()
            }
            .padding(FW.spacing32)
        }
        .background(FW.background)
    }
}

// MARK: - Transcription Section

private struct TranscriptionSection: View {
    @EnvironmentObject var appState: AppState
    @State private var useLocalTranscription = false
    @State private var selectedWhisperModel: WhisperModel = .balanced
    @State private var selectedCloudProvider: CloudTranscriptionProvider = .openAI
    @State private var base10ApiKey = ""
    @State private var existingBase10Key: String?
    @State private var showSavedFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: FW.spacing12) {
            Text("Transcription")
                .fwSectionHeader()

            VStack(spacing: FW.spacing16) {
                FWToggle(isOn: $useLocalTranscription, label: "Local Whisper")
                    .onChange(of: useLocalTranscription) { _, newValue in
                        if newValue {
                            _ = appState.engine.setTranscriptionMode(.local(model: selectedWhisperModel))
                        } else {
                            _ = appState.engine.setTranscriptionMode(.remote)
                        }
                    }

                if useLocalTranscription {
                    VStack(alignment: .leading, spacing: FW.spacing8) {
                        Text("Model")
                            .font(.subheadline)
                            .foregroundStyle(FW.textSecondary)

                        WhisperModelPicker(selection: $selectedWhisperModel)
                            .onChange(of: selectedWhisperModel) { _, newModel in
                                _ = appState.engine.setTranscriptionMode(.local(model: newModel))
                            }
                    }
                } else {
                    // Cloud transcription provider selection
                    VStack(alignment: .leading, spacing: FW.spacing12) {
                        Text("Cloud Provider")
                            .font(.subheadline)
                            .foregroundStyle(FW.textSecondary)

                        CloudTranscriptionProviderPicker(selection: $selectedCloudProvider)
                            .onChange(of: selectedCloudProvider) { _, newProvider in
                                // If switching to a provider that already has a key, apply it
                                if let existingKey = appState.engine.getMaskedCloudTranscriptionApiKey(for: newProvider), !existingKey.isEmpty {
                                    // Provider is already configured, just switch
                                    _ = appState.engine.setTranscriptionMode(.remote)
                                }
                            }

                        // Show Base10 API key input when Base10 is selected
                        if selectedCloudProvider == .base10 {
                            Base10ApiKeyInput(
                                key: $base10ApiKey,
                                hasExistingKey: existingBase10Key != nil,
                                showSavedFeedback: $showSavedFeedback,
                                onSave: saveBase10Key
                            )
                        }

                        // Status indicator
                        HStack(spacing: FW.spacing8) {
                            Circle()
                                .fill(isCloudProviderConfigured ? FW.success : FW.warning)
                                .frame(width: 8, height: 8)
                            Text(cloudProviderStatusText)
                                .font(.caption)
                                .foregroundStyle(isCloudProviderConfigured ? FW.success : FW.warning)
                        }
                    }
                }

            }
            .fwSection()
        }
        .onAppear {
            loadCurrentMode()
        }
    }

    private var isCloudProviderConfigured: Bool {
        switch selectedCloudProvider {
        case .openAI:
            return appState.engine.maskedOpenAIKey != nil
        case .base10:
            return existingBase10Key != nil
        }
    }

    private var cloudProviderStatusText: String {
        if isCloudProviderConfigured {
            return "\(selectedCloudProvider.displayName) configured"
        } else {
            return selectedCloudProvider == .base10 ? "Base10 API key required" : "OpenAI API key required (see API Keys section)"
        }
    }

    private func loadCurrentMode() {
        if let mode = appState.engine.getTranscriptionMode() {
            switch mode {
            case .local(let model):
                useLocalTranscription = true
                selectedWhisperModel = model
            case .remote:
                useLocalTranscription = false
            }
        }
        // Load cloud provider setting
        if let provider = appState.engine.cloudTranscriptionProvider {
            selectedCloudProvider = provider
        }
        // Load existing Base10 key
        existingBase10Key = appState.engine.getMaskedCloudTranscriptionApiKey(for: .base10)
    }

    private func saveBase10Key(_ key: String) {
        _ = appState.engine.setCloudTranscriptionProvider(.base10, apiKey: key)
        existingBase10Key = appState.engine.getMaskedCloudTranscriptionApiKey(for: .base10)
        base10ApiKey = ""

        withAnimation {
            showSavedFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSavedFeedback = false
            }
        }
    }
}

private struct CloudTranscriptionProviderPicker: View {
    @Binding var selection: CloudTranscriptionProvider

    private let providers: [(CloudTranscriptionProvider, String, String)] = [
        (.openAI, "OpenAI", "Uses your OpenAI API key"),
        (.base10, "Base10", "Dedicated Whisper endpoint")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(providers, id: \.0) { provider, label, tooltip in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = provider
                    }
                } label: {
                    Text(label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(selection == provider ? FW.textPrimary : FW.textSecondary)
                        .padding(.horizontal, FW.spacing16)
                        .padding(.vertical, FW.spacing8)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selection == provider {
                                RoundedRectangle(cornerRadius: FW.radiusSmall - 2)
                                    .fill(FW.surface)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tooltip)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: FW.radiusSmall)
                .fill(FW.background)
        }
    }
}

private struct Base10ApiKeyInput: View {
    @Binding var key: String
    let hasExistingKey: Bool
    @Binding var showSavedFeedback: Bool
    let onSave: (String) -> Void

    var body: some View {
        HStack(spacing: FW.spacing12) {
            if hasExistingKey {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(FW.success)
            }

            FWSecureField(
                text: $key,
                placeholder: hasExistingKey ? "Enter new key to replace..." : "Base10 API key...",
                onSubmit: { if !key.isEmpty { onSave(key) } }
            )

            Button {
                onSave(key)
            } label: {
                if showSavedFeedback {
                    HStack(spacing: FW.spacing4) {
                        Image(systemName: "checkmark")
                        Text("Saved")
                    }
                } else {
                    Text("Save")
                }
            }
            .buttonStyle(FWSecondaryButtonStyle())
            .disabled(key.isEmpty)
        }
    }
}

private struct WhisperModelPicker: View {
    @Binding var selection: WhisperModel

    private let models: [(WhisperModel, String, String)] = [
        (.fast, "Fast", "Tiny (~39MB). Quick, less accurate."),
        (.balanced, "Balanced", "Base (~142MB). Good tradeoff."),
        (.quality, "Quality", "Distil-medium (~400MB). Best accuracy.")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(models, id: \.0) { model, label, tooltip in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = model
                    }
                } label: {
                    Text(label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(selection == model ? FW.textPrimary : FW.textSecondary)
                        .padding(.horizontal, FW.spacing16)
                        .padding(.vertical, FW.spacing8)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selection == model {
                                RoundedRectangle(cornerRadius: FW.radiusSmall - 2)
                                    .fill(FW.surface)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tooltip)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: FW.radiusSmall)
                .fill(FW.background)
        }
    }
}

// MARK: - API Keys Section

private struct APIKeysSection: View {
    @EnvironmentObject var appState: AppState
    @State private var openAIKey = ""
    @State private var geminiKey = ""
    @State private var openRouterKey = ""
    @State private var selectedProvider: CompletionProvider = .openAI
    @State private var existingOpenAIKey: String?
    @State private var existingGeminiKey: String?
    @State private var existingOpenRouterKey: String?
    @State private var showSavedFeedback = false

    private var currentProviderHasKey: Bool {
        currentExistingKey != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FW.spacing12) {
            Text("API Keys")
                .fwSectionHeader()

            VStack(spacing: FW.spacing20) {
                VStack(alignment: .leading, spacing: FW.spacing12) {
                    Text("Provider")
                        .font(.subheadline)
                        .foregroundStyle(FW.textSecondary)

                    FWSegmentedControl(
                        selection: $selectedProvider,
                        options: [CompletionProvider.openAI, CompletionProvider.gemini, CompletionProvider.openRouter],
                        label: { $0.displayName }
                    )
                    .onChange(of: selectedProvider) { _, newProvider in
                        _ = appState.engine.switchCompletionProvider(newProvider)
                        appState.isConfigured = appState.engine.isConfigured
                        showSavedFeedback = false
                    }
                }

                APIKeyInput(
                    provider: selectedProvider,
                    key: currentKeyBinding,
                    hasExistingKey: currentProviderHasKey,
                    showSavedFeedback: $showSavedFeedback,
                    onSave: saveCurrentKey
                )

                HStack(spacing: FW.spacing8) {
                    Circle()
                        .fill(currentProviderHasKey ? FW.success : FW.warning)
                        .frame(width: 8, height: 8)
                    Text(currentProviderHasKey ? "\(selectedProvider.displayName) configured" : "\(selectedProvider.displayName) key required")
                        .font(.caption)
                        .foregroundStyle(currentProviderHasKey ? FW.success : FW.warning)
                }
            }
            .fwSection()
        }
        .onAppear {
            if let current = appState.engine.completionProvider {
                selectedProvider = current
            }
            refreshKeys()
        }
    }

    private func refreshKeys() {
        existingOpenAIKey = appState.engine.maskedOpenAIKey
        existingGeminiKey = appState.engine.maskedGeminiKey
        existingOpenRouterKey = appState.engine.maskedOpenRouterKey
    }

    private var currentKeyBinding: Binding<String> {
        switch selectedProvider {
        case .openAI: return $openAIKey
        case .gemini: return $geminiKey
        case .openRouter: return $openRouterKey
        }
    }

    private var currentExistingKey: String? {
        switch selectedProvider {
        case .openAI: return existingOpenAIKey
        case .gemini: return existingGeminiKey
        case .openRouter: return existingOpenRouterKey
        }
    }

    private func saveCurrentKey(_ key: String) {
        appState.setApiKey(key, for: selectedProvider)
        refreshKeys()

        switch selectedProvider {
        case .openAI: openAIKey = ""
        case .gemini: geminiKey = ""
        case .openRouter: openRouterKey = ""
        }

        withAnimation {
            showSavedFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSavedFeedback = false
            }
        }
    }
}

private struct APIKeyInput: View {
    let provider: CompletionProvider
    @Binding var key: String
    let hasExistingKey: Bool
    @Binding var showSavedFeedback: Bool
    let onSave: (String) -> Void

    var body: some View {
        HStack(spacing: FW.spacing12) {
            if hasExistingKey {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(FW.success)
            }

            FWSecureField(
                text: $key,
                placeholder: hasExistingKey ? "Enter new key to replace..." : provider.placeholder,
                onSubmit: { if !key.isEmpty { onSave(key) } }
            )

            Button {
                onSave(key)
            } label: {
                if showSavedFeedback {
                    HStack(spacing: FW.spacing4) {
                        Image(systemName: "checkmark")
                        Text("Saved")
                    }
                } else {
                    Text("Save")
                }
            }
            .buttonStyle(FWSecondaryButtonStyle())
            .disabled(key.isEmpty)
        }
    }
}

private extension CompletionProvider {
    var placeholder: String {
        switch self {
        case .openAI: return "sk-..."
        case .gemini: return "AI..."
        case .openRouter: return "sk-or-v1-..."
        }
    }
}

// MARK: - General Section

private struct GeneralSection: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: FW.spacing12) {
            Text("General")
                .fwSectionHeader()

            VStack(spacing: FW.spacing16) {
                FWToggle(isOn: $launchAtLogin, label: "Launch at login")
            }
            .fwSection()
        }
    }
}

// MARK: - Keyboard Section

private struct KeyboardSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: FW.spacing12) {
            Text("Keyboard")
                .fwSectionHeader()

            VStack(spacing: FW.spacing16) {
                HStack {
                    VStack(alignment: .leading, spacing: FW.spacing4) {
                        Text("Hotkey")
                            .font(.body)
                            .foregroundStyle(FW.textPrimary)

                        Text(appState.hotkey.displayName)
                            .font(FW.fontMono)
                            .foregroundStyle(FW.textSecondary)
                    }

                    Spacer()

                    HStack(spacing: FW.spacing8) {
                        Button(appState.isCapturingHotkey ? "Press keys..." : "Change") {
                            if appState.isCapturingHotkey {
                                appState.endHotkeyCapture()
                            } else {
                                appState.beginHotkeyCapture()
                            }
                        }
                        .buttonStyle(FWSecondaryButtonStyle())

                        Button("Reset to Fn") {
                            appState.setHotkey(Hotkey.defaultHotkey)
                        }
                        .buttonStyle(FWGhostButtonStyle())
                    }
                }
            }
            .fwSection()
        }
    }
}

// MARK: - Stats Section

private struct StatsSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: FW.spacing12) {
            Text("Stats")
                .fwSectionHeader()

            HStack(spacing: FW.spacing16) {
                statItem(
                    icon: "brain.head.profile",
                    value: "\(appState.engine.correctionCount)",
                    label: "Corrections"
                )
                statItem(
                    icon: "clock",
                    value: "\(appState.totalMinutes)",
                    label: "Minutes"
                )
                statItem(
                    icon: "text.word.spacing",
                    value: "\(appState.totalWordsDictated)",
                    label: "Words"
                )
            }
            .fwSection()
        }
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: FW.spacing8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(FW.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FW.textPrimary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(FW.textMuted)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - About Footer

private struct AboutFooter: View {
    var body: some View {
        HStack {
            HStack(spacing: FW.spacing8) {
                Image(systemName: "waveform")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FW.accent)

                Text("Flow")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FW.textPrimary)

                Text("v0.1.7")
                    .font(.caption)
                    .foregroundStyle(FW.textMuted)
            }

            Spacer()

            Link(destination: URL(string: "https://github.com/jasonlovesdoggo/flow")!) {
                HStack(spacing: FW.spacing4) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                    Text("GitHub")
                }
                .font(.subheadline)
                .foregroundStyle(FW.accent)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    SettingsContentView()
        .environmentObject(AppState())
}
