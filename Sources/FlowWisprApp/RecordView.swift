//
// RecordView.swift
// FlowWispr
//
// Main recording view with waveform visualization and transcription output.
//

import FlowWispr
import SwiftUI

struct RecordView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let errorMessage = appState.errorMessage {
                    errorBanner(text: errorMessage)
                        .padding(.horizontal, FW.spacing24)
                        .padding(.top, FW.spacing24)
                }

                if !appState.isConfigured {
                    banner(text: "Add your OpenAI API key to start recording.", actionTitle: "Open Settings") {
                        appState.selectedTab = .settings
                    }
                    .padding(.horizontal, FW.spacing24)
                    .padding(.top, FW.spacing16)
                }

                if !appState.isAccessibilityEnabled {
                    banner(text: "Enable Accessibility to use the hotkey.", actionTitle: "Enable") {
                        appState.requestAccessibilityPermission()
                    }
                    .padding(.horizontal, FW.spacing24)
                    .padding(.top, FW.spacing16)
                }

                // hero waveform + record button
                heroSection
                    .padding(.horizontal, FW.spacing24)
                    .padding(.top, FW.spacing32)

                // context bar
                contextBar
                    .padding(.horizontal, FW.spacing24)
                    .padding(.top, FW.spacing24)

                // output area
                if let text = appState.lastTranscription {
                    outputSection(text)
                        .padding(.horizontal, FW.spacing24)
                        .padding(.top, FW.spacing16)
                }

                // history
                HistoryListView()
                    .padding(.horizontal, FW.spacing24)
                    .padding(.top, FW.spacing24)

                // footer
                footer
                    .padding(FW.spacing16)
            }
        }
        .background(FW.surfacePrimary)
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: FW.spacing24) {
            // waveform visualization
            WaveformView(isRecording: appState.isRecording, audioLevel: appState.smoothedAudioLevel)
                .frame(height: 80)
                .padding(.horizontal, FW.spacing16)

            // big record button
            Button(action: { appState.toggleRecording() }) {
                HStack(spacing: FW.spacing12) {
                    Image(systemName: appState.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .semibold))

                    if appState.isRecording {
                        Text(formatDuration(appState.recordingDuration))
                            .font(FW.fontMonoLarge)
                    } else {
                        Text("Record")
                            .font(.headline)
                    }
                }
                .frame(minWidth: 160)
            }
            .buttonStyle(FWPrimaryButtonStyle(isRecording: appState.isRecording))

            // shortcut hint
            if case .globe = appState.hotkey.kind {
                Text("Hold \(appState.hotkey.displayName) to record")
                    .font(FW.fontMonoSmall)
                    .foregroundStyle(FW.textTertiary)
            } else {
                Text("Hotkey: \(appState.hotkey.displayName)")
                    .font(FW.fontMonoSmall)
                    .foregroundStyle(FW.textTertiary)
            }
        }
        .padding(FW.spacing24)
        .fwCard()
    }

    // MARK: - Context Bar

    private var contextBar: some View {
        HStack(spacing: FW.spacing16) {
            // target app (the app we're configuring, not FlowWispr)
            HStack(spacing: FW.spacing8) {
                Image(systemName: "app.fill")
                    .font(.caption)
                    .foregroundStyle(FW.accent)

                Text(appState.targetAppName)
                    .font(.subheadline)
                    .foregroundStyle(FW.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            // mode picker
            Menu {
                ForEach(WritingMode.allCases, id: \.self) { mode in
                    Button {
                        appState.setMode(mode)
                    } label: {
                        HStack {
                            Text(mode.displayName)
                            if mode == appState.currentMode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: FW.spacing4) {
                    Text(appState.currentMode.displayName)
                        .font(.subheadline.weight(.medium))

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(FW.accent)
                .padding(.horizontal, FW.spacing12)
                .padding(.vertical, FW.spacing4)
                .background {
                    RoundedRectangle(cornerRadius: FW.radiusSmall)
                        .fill(FW.accent.opacity(0.1))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(FW.spacing12)
        .background {
            RoundedRectangle(cornerRadius: FW.radiusSmall)
                .fill(FW.surfaceElevated.opacity(0.5))
        }
    }

    // MARK: - Output Section

    private func outputSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: FW.spacing8) {
            HStack {
                Text("Output")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(FW.textTertiary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    HStack(spacing: FW.spacing4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.caption)
                }
                .buttonStyle(FWSecondaryButtonStyle())
            }

            Text(text)
                .font(.body)
                .foregroundStyle(FW.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(FW.spacing12)
                .background {
                    RoundedRectangle(cornerRadius: FW.radiusSmall)
                        .fill(FW.surfaceElevated.opacity(0.5))
                        .overlay {
                            RoundedRectangle(cornerRadius: FW.radiusSmall)
                                .strokeBorder(FW.accent.opacity(0.2), lineWidth: 1)
                        }
                }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()

            HStack(spacing: FW.spacing16) {
                statItem(value: "\(appState.totalTranscriptions)", label: "transcriptions")

                if appState.totalMinutes > 0 {
                    statItem(value: "\(appState.totalMinutes)", label: "minutes")
                }
            }
        }
    }

    private func statItem(value: String, label: String) -> some View {
        HStack(spacing: FW.spacing4) {
            Text(value)
                .font(FW.fontMonoSmall.weight(.medium))
                .foregroundStyle(FW.textPrimary)

            Text(label)
                .font(.caption)
                .foregroundStyle(FW.textTertiary)
        }
    }

    private func banner(text: String, actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: FW.spacing12) {
            Text(text)
                .font(.caption)
                .foregroundStyle(FW.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(FWSecondaryButtonStyle())
            }
        }
        .padding(FW.spacing12)
        .background {
            RoundedRectangle(cornerRadius: FW.radiusSmall)
                .fill(FW.surfaceElevated.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: FW.radiusSmall)
                        .strokeBorder(FW.accent.opacity(0.1), lineWidth: 1)
                }
        }
    }

    private func errorBanner(text: String) -> some View {
        HStack(spacing: FW.spacing12) {
            Text(text)
                .font(.caption)
                .foregroundStyle(FW.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Retry") {
                appState.retryLastTranscription()
            }
            .buttonStyle(FWSecondaryButtonStyle())

            Button("Dismiss") {
                appState.clearError()
            }
            .buttonStyle(FWSecondaryButtonStyle())
        }
        .padding(FW.spacing12)
        .background {
            RoundedRectangle(cornerRadius: FW.radiusSmall)
                .fill(FW.surfaceElevated.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: FW.radiusSmall)
                        .strokeBorder(FW.accent.opacity(0.1), lineWidth: 1)
                }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ ms: UInt64) -> String {
        let seconds = ms / 1000
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

#Preview {
    RecordView()
        .environmentObject(AppState())
}
