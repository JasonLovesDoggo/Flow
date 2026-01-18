//
// RecordingIndicatorWindow.swift
// FlowWispr
//
// Lightweight, non-activating recording indicator shown while recording or processing.
//

import AppKit
import SwiftUI

@MainActor
final class RecordingIndicatorWindow {
    private let window: NSPanel

    init(appState: AppState) {
        let view = RecordingIndicatorView()
            .environmentObject(appState)
        let hosting = NSHostingController(rootView: view)

        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.setFrame(NSRect(x: 0, y: 0, width: 400, height: 32), display: false)

        self.window = panel
        positionWindow()
    }

    func show() {
        positionWindow()
        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0

            // Slide down slightly
            var frame = window.frame
            frame.origin.y -= 15
            window.animator().setFrame(frame, display: true)
        }, completionHandler: {
            self.window.orderOut(nil)
            self.window.alphaValue = 1
            Task { @MainActor in
                self.positionWindow() // Reset position for next show
            }
        })
    }

    private func positionWindow() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let size = window.frame.size
        let padding: CGFloat = 12
        let origin = CGPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.minY + padding
        )
        window.setFrameOrigin(origin)
    }
}

private struct RecordingIndicatorView: View {
    @EnvironmentObject var appState: AppState
    @State private var pulse = false

    var showPill: Bool {
        appState.isRecording || appState.isProcessing || appState.isInitializingModel
    }

    var body: some View {
        HStack(spacing: FW.spacing6) {
            Circle()
                .fill(appState.isRecording ? FW.recording : FW.accent)
                .frame(width: 8, height: 8)
                .opacity(pulse ? 0.6 : 1.0)

            if appState.isRecording {
                CompactWaveformView(isRecording: true, audioLevel: appState.smoothedAudioLevel)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            if appState.isProcessing && !appState.isInitializingModel {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(.white.opacity(0.9))
                    .frame(width: 50, height: 14)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.5)).animation(.spring(response: 0.65, dampingFraction: 0.75).delay(0.35)),
                        removal: .opacity.combined(with: .scale(scale: 0.8)).animation(.spring(response: 0.5, dampingFraction: 0.75))
                    ))
            }

            if appState.isInitializingModel {
                HStack(spacing: FW.spacing6) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(.white.opacity(0.9))

                    Text("Initializing Whisper model...")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
                .frame(height: 14)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.5)).animation(.spring(response: 0.65, dampingFraction: 0.75).delay(0.35)),
                    removal: .opacity.combined(with: .scale(scale: 0.8)).animation(.spring(response: 0.5, dampingFraction: 0.75))
                ))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, FW.spacing6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.55))
        )
        .compositingGroup()
        .animation(.spring(response: 0.85, dampingFraction: 0.82), value: appState.isRecording)
        .animation(.spring(response: 0.85, dampingFraction: 0.82), value: appState.isProcessing)
        .animation(.spring(response: 0.85, dampingFraction: 0.82), value: appState.isInitializingModel)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
