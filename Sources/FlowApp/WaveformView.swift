//
// WaveformView.swift
// Flow
//
// Animated waveform visualization. The hero visual element.
//

import SwiftUI

// MARK: - Pre-computed color cache for gradient interpolation
private struct ColorCache {
    let recording: [Color]
    let idle: [Color]

    init(barCount: Int) {
        // Pre-compute all gradient colors to avoid per-frame NSColor conversions
        let recordingFrom = NSColor(FW.recording)
        let recordingTo = NSColor(FW.recording.withAlphaComponent(0.6))
        let accentFrom = NSColor(FW.accent)
        let accentTo = NSColor(FW.accentSecondary)

        var recordingColors: [Color] = []
        var idleColors: [Color] = []

        recordingColors.reserveCapacity(barCount)
        idleColors.reserveCapacity(barCount)

        for i in 0 ..< barCount {
            let progress = CGFloat(i) / CGFloat(max(barCount - 1, 1))
            recordingColors.append(ColorCache.interpolate(from: recordingFrom, to: recordingTo, progress: progress))
            idleColors.append(ColorCache.interpolate(from: accentFrom, to: accentTo, progress: progress))
        }

        recording = recordingColors
        idle = idleColors
    }

    private static func interpolate(from: NSColor, to: NSColor, progress: CGFloat) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0

        from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        return Color(
            red: r1 + (r2 - r1) * progress,
            green: g1 + (g2 - g1) * progress,
            blue: b1 + (b2 - b1) * progress,
            opacity: a1 + (a2 - a1) * progress
        )
    }
}

struct WaveformView: View {
    let isRecording: Bool
    let barCount: Int
    let audioLevel: Float?

    @State private var sampleBuffer: [Float] = []
    @State private var isDecaying = false
    @State private var colorCache: ColorCache?

    // Pre-computed constants
    private let barWidth: CGFloat = 1.5
    private let gap: CGFloat = 2.5

    init(isRecording: Bool, barCount: Int = 32, audioLevel: Float? = nil) {
        self.isRecording = isRecording
        self.barCount = barCount
        self.audioLevel = audioLevel
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { _ in
            Canvas { context, size in
                let totalWidth = CGFloat(barCount) * (barWidth + gap) - gap
                let startX = (size.width - totalWidth) / 2
                let maxHeight = size.height * 0.85
                let minHeight = size.height * 0.15

                // Get display samples (using current state, updates happen in onChange)
                let displaySamples = computeDisplaySamples()

                // Find max in current window for normalization
                let windowMax = displaySamples.max() ?? 0.01
                let normalizationFactor = max(0.3, windowMax)
                let bufferFilling = sampleBuffer.count < barCount

                // Get cached colors
                let colors = colorCache ?? ColorCache(barCount: barCount)

                for i in 0 ..< barCount {
                    let x = startX + CGFloat(i) * (barWidth + gap)

                    // Get sample for this bar and apply log scale normalization
                    var sample = displaySamples[i]

                    // Add positional variation when buffer is filling for immediate visual feedback
                    if bufferFilling && sample > 0.01 {
                        let barPosition = Double(i) / Double(barCount - 1)
                        let positionVariation = sin(barPosition * .pi)
                        sample = sample * Float(0.5 + positionVariation * 0.5)
                    }

                    let normalized = sample / normalizationFactor
                    let amplitude = normalized > 0.01 ? log10(1 + normalized * 9) : 0.0

                    let height = minHeight + (maxHeight - minHeight) * CGFloat(amplitude)
                    let y = (size.height - height) / 2

                    let rect = CGRect(x: x, y: y, width: barWidth, height: height)
                    let path = RoundedRectangle(cornerRadius: barWidth / 2).path(in: rect)

                    // Use cached colors instead of computing per-frame
                    let color = isRecording ? colors.recording[i] : colors.idle[i]
                    context.fill(path, with: .color(color))
                }
            }
        }
        .onAppear {
            colorCache = ColorCache(barCount: barCount)
        }
        .onChange(of: audioLevel) { _, newLevel in
            guard isRecording, let level = newLevel else { return }
            sampleBuffer.append(level)
            if sampleBuffer.count > barCount {
                sampleBuffer.removeFirst()
            }
        }
        .onChange(of: isRecording) { oldValue, newValue in
            if oldValue && !newValue {
                isDecaying = true
                startDecayAnimation()
            } else if newValue {
                isDecaying = false
            }
        }
    }

    private func computeDisplaySamples() -> [Float] {
        if sampleBuffer.count < barCount {
            let fillValue = sampleBuffer.last ?? 0.0
            return Array(repeating: fillValue, count: barCount - sampleBuffer.count) + sampleBuffer
        } else {
            return Array(sampleBuffer.suffix(barCount))
        }
    }

    private func startDecayAnimation() {
        guard isDecaying else { return }

        // Apply decay outside of Canvas render
        let allZero = sampleBuffer.allSatisfy { $0 < 0.01 }
        if allZero {
            isDecaying = false
            sampleBuffer = []
        } else {
            let count = sampleBuffer.count
            sampleBuffer = sampleBuffer.enumerated().map { index, value in
                let position = Float(index) / Float(max(count, 1))
                let decayRate = 0.92 + position * 0.05
                return value * decayRate
            }
            // Continue decay on next frame
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 / 30) {
                startDecayAnimation()
            }
        }
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
