//
// Theme.swift
// Flow
//
// Swedish minimalism design system. Adapts to light/dark mode.
//

import AppKit
import SwiftUI

// MARK: - Window Size

enum WindowSize {
    static var screen: CGRect { NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900) }
    static var width: CGFloat { screen.width * 0.7 }
    static var height: CGFloat { screen.height * 0.7 }
    static let minWidth: CGFloat = 700
    static let minHeight: CGFloat = 500
}

// MARK: - Design System

enum FW {
    // MARK: - Colors (Adaptive Light/Dark)

    // Dark mode: warm charcoal palette with subtle depth
    // Light mode: clean whites with soft grey accents

    /// Background - adapts to system appearance
    static let background = Color(nsColor: .init(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.09, green: 0.086, blue: 0.082, alpha: 1) // #171615 warm charcoal
                : NSColor(red: 0.976, green: 0.973, blue: 0.969, alpha: 1) // #F9F8F7 warm white
        }
    ))

    /// Elevated surface for cards
    static let surface = Color(nsColor: .init(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.125, green: 0.12, blue: 0.114, alpha: 1) // #201F1D warm grey
                : NSColor(red: 1, green: 1, blue: 1, alpha: 1) // #FFFFFF
        }
    ))

    /// Subtle border/divider
    static let border = Color(nsColor: .init(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.18, green: 0.173, blue: 0.165, alpha: 1) // #2E2C2A warm border
                : NSColor(red: 0.91, green: 0.898, blue: 0.886, alpha: 1) // #E8E5E2 warm light border
        }
    ))

    /// Primary text
    static let textPrimary = Color(nsColor: .init(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.95, green: 0.94, blue: 0.92, alpha: 1) // #F2F0EB warm white
                : NSColor(red: 0.1, green: 0.094, blue: 0.086, alpha: 1) // #1A1816 warm black
        }
    ))

    /// Secondary text
    static let textSecondary = Color(nsColor: .init(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.65, green: 0.62, blue: 0.58, alpha: 1) // #A69E94 warm grey
                : NSColor(red: 0.4, green: 0.38, blue: 0.35, alpha: 1) // #666159 warm dark grey
        }
    ))

    /// Muted/tertiary text
    static let textMuted = Color(nsColor: .init(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.47, green: 0.45, blue: 0.42, alpha: 1) // #78736B warm muted
                : NSColor(red: 0.56, green: 0.53, blue: 0.5, alpha: 1) // #8F8780 warm light muted
        }
    ))

    /// Primary accent - indigo
    static let accent = Color(red: 0.388, green: 0.4, blue: 0.945) // #6366F1

    /// Hover/active state - indigo darker
    static let accentMuted = Color(red: 0.31, green: 0.275, blue: 0.898) // #4F46E5

    /// Recording/danger state - red
    static let danger = Color(red: 0.937, green: 0.267, blue: 0.267) // #EF4444

    /// Success/configured state - green
    static let success = Color(red: 0.133, green: 0.773, blue: 0.369) // #22C55E

    /// Warning state - amber
    static let warning = Color(red: 0.95, green: 0.65, blue: 0.15)

    // Legacy aliases
    static var recording: Color { danger }
    static var surfacePrimary: Color { background }
    static var surfaceElevated: Color { surface }
    static var textTertiary: Color { textMuted }
    static var accentSecondary: Color { accentMuted }

    // MARK: - Spacing

    static let spacing2: CGFloat = 2
    static let spacing4: CGFloat = 4
    static let spacing6: CGFloat = 6
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32

    // MARK: - Radii

    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16
    static let radiusXL: CGFloat = 24

    // MARK: - Typography

    static let fontMono = Font.system(.body, design: .monospaced)
    static let fontMonoSmall = Font.system(.caption, design: .monospaced)
    static let fontMonoLarge = Font.system(.title3, design: .monospaced).weight(.medium)
}

// MARK: - View Extensions

extension View {
    /// Modern card with subtle border
    func fwCard() -> some View {
        background {
            RoundedRectangle(cornerRadius: FW.radiusMedium)
                .fill(FW.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: FW.radiusMedium)
                        .strokeBorder(FW.border, lineWidth: 1)
                }
        }
    }

    /// Section card with minimal styling
    func fwSection() -> some View {
        padding(FW.spacing20)
            .background {
                RoundedRectangle(cornerRadius: FW.radiusMedium)
                    .fill(FW.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: FW.radiusMedium)
                            .strokeBorder(FW.border, lineWidth: 1)
                    }
            }
    }

    /// Section header style (uppercase, muted, small)
    func fwSectionHeader() -> some View {
        font(.caption.weight(.semibold))
            .foregroundStyle(FW.textMuted)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

// MARK: - Button Styles

struct FWPrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, FW.spacing20)
            .padding(.vertical, FW.spacing12)
            .background {
                RoundedRectangle(cornerRadius: FW.radiusSmall)
                    .fill(isDestructive ? FW.danger : FW.accent)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct FWSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(FW.accent)
            .padding(.horizontal, FW.spacing12)
            .padding(.vertical, FW.spacing8)
            .background {
                RoundedRectangle(cornerRadius: FW.radiusSmall)
                    .fill(FW.accent.opacity(configuration.isPressed ? 0.15 : 0.1))
            }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct FWGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(configuration.isPressed ? FW.textMuted : FW.textSecondary)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Form Row Component

struct FWFormRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(FW.textPrimary)

            Spacer()

            content
        }
    }
}
