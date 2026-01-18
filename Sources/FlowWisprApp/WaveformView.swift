//
// WaveformView.swift
// FlowWispr
//
// Animated waveform visualization. The hero visual element.
//

import SwiftUI

struct WaveformView: View {
    let isRecording: Bool
    let barCount: Int
    let audioLevel: Float?

    @State private var animationPhase: CGFloat = 0
    @State private var lastRealLevel: Float = 0.0

    init(isRecording: Bool, barCount: Int = 32, audioLevel: Float? = nil) {
        self.isRecording = isRecording
        self.barCount = barCount
        self.audioLevel = audioLevel
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            Canvas { context, size in
                let barWidth: CGFloat = 1.5
                let gap: CGFloat = 2.5
                let totalWidth = CGFloat(barCount) * (barWidth + gap) - gap
                let startX = (size.width - totalWidth) / 2
                let maxHeight = size.height * 0.85
                let minHeight = size.height * 0.15

                let time = timeline.date.timeIntervalSinceReferenceDate

                for i in 0..<barCount {
                    let x = startX + CGFloat(i) * (barWidth + gap)

                    // generate wave height based on position and time
                    let basePhase = Double(i) / Double(barCount) * .pi * 2
                    let timePhase = time * (isRecording ? 3.5 : 0.5)

                    let wave1 = sin(basePhase + timePhase) * 0.35
                    let wave2 = sin(basePhase * 2.3 + timePhase * 1.3) * 0.25
                    let wave3 = sin(basePhase * 0.7 + timePhase * 0.7) * 0.2

                    // Update last real level when we have valid audio data
                    var currentLevel = lastRealLevel
                    if let level = audioLevel, level > 0.01 {
                        currentLevel = level
                        if i == 0 {
                            // Only update state once per frame (on first bar)
                            DispatchQueue.main.async {
                                lastRealLevel = level
                            }
                        }
                    } else if i == 0 && lastRealLevel > 0.01 {
                        // Gradually decay the last real level when no new data
                        let decayedLevel = lastRealLevel * 0.92
                        DispatchQueue.main.async {
                            lastRealLevel = decayedLevel
                        }
                    }

                    var amplitude: Double
                    if currentLevel > 0.01 {
                        // Use real audio level (current or decaying) with wave modulation
                        let levelAmplitude = Double(currentLevel) * 0.75 + 0.15
                        let waveModulation = (wave1 + wave2 + wave3) * 0.3
                        amplitude = levelAmplitude + waveModulation
                    } else {
                        // Only use fake animation when level has decayed to near zero
                        amplitude = isRecording
                            ? 0.5 + wave1 + wave2 + wave3
                            : 0.35 + wave1 * 0.5 + wave2 * 0.4
                    }
                    amplitude = max(0.15, min(1.0, amplitude))

                    let height = minHeight + (maxHeight - minHeight) * amplitude
                    let y = (size.height - height) / 2

                    let rect = CGRect(x: x, y: y, width: barWidth, height: height)
                    let path = RoundedRectangle(cornerRadius: barWidth / 2)
                        .path(in: rect)

                    // color gradient based on position
                    let progress = CGFloat(i) / CGFloat(barCount - 1)
                    let color = isRecording
                        ? interpolateColor(from: FW.recording, to: FW.recording.opacity(0.6), progress: progress)
                        : interpolateColor(from: FW.accent, to: FW.accentSecondary, progress: progress)

                    context.fill(path, with: .color(color))
                }
            }
        }
    }

    private func interpolateColor(from: Color, to: Color, progress: CGFloat) -> Color {
        // simplified linear interpolation
        let nsFrom = NSColor(from)
        let nsTo = NSColor(to)

        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0

        nsFrom.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        nsTo.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        return Color(
            red: r1 + (r2 - r1) * progress,
            green: g1 + (g2 - g1) * progress,
            blue: b1 + (b2 - b1) * progress,
            opacity: a1 + (a2 - a1) * progress
        )
    }
}

// MARK: - Compact waveform for menu bar

struct CompactWaveformView: View {
    let isRecording: Bool
    let audioLevel: Float?

    init(isRecording: Bool, audioLevel: Float? = nil) {
        self.isRecording = isRecording
        self.audioLevel = audioLevel
    }

    var body: some View {
        WaveformView(isRecording: isRecording, barCount: 9, audioLevel: audioLevel)
            .frame(width: 50, height: 14)
    }
}

// MARK: - Preview

#Preview("Idle") {
    WaveformView(isRecording: false)
        .frame(width: 300, height: 80)
        .padding()
        .background(Color.black.opacity(0.9))
}

#Preview("Recording") {
    WaveformView(isRecording: true)
        .frame(width: 300, height: 80)
        .padding()
        .background(Color.black.opacity(0.9))
}
