//
// ShortcutsView.swift
// Flow
//
// Voice shortcuts management interface.
//

import SwiftUI

struct ShortcutsContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var newTrigger = ""
    @State private var newReplacement = ""
    @State private var shortcuts: [ShortcutItem] = []
    @State private var showingAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: FW.spacing4) {
                    Text("Voice Shortcuts")
                        .font(.title.weight(.bold))
                        .foregroundStyle(FW.textPrimary)

                    Text("Expand phrases while dictating")
                        .font(.body)
                        .foregroundStyle(FW.textSecondary)
                }

                Spacer()

                Button {
                    showingAddSheet = true
                } label: {
                    HStack(spacing: FW.spacing6) {
                        Image(systemName: "plus")
                        Text("Add")
                    }
                }
                .buttonStyle(FWSecondaryButtonStyle())
            }
            .padding(FW.spacing32)

            // Separator
            Rectangle()
                .fill(FW.border)
                .frame(height: 1)

            // List
            if shortcuts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: FW.spacing12) {
                        ForEach(shortcuts) { shortcut in
                            shortcutRow(shortcut)
                        }
                    }
                    .padding(FW.spacing32)
                }
            }
        }
        .background(FW.background)
        .sheet(isPresented: $showingAddSheet) {
            AddShortcutSheet(
                trigger: $newTrigger,
                replacement: $newReplacement,
                onAdd: addShortcut,
                onCancel: { showingAddSheet = false }
            )
        }
        .onAppear {
            refreshShortcuts()
        }
    }

    private var emptyState: some View {
        VStack(spacing: FW.spacing20) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(FW.textMuted)

            VStack(spacing: FW.spacing8) {
                Text("No shortcuts yet")
                    .font(.headline)
                    .foregroundStyle(FW.textPrimary)

                Text("Add shortcuts to quickly expand phrases")
                    .font(.body)
                    .foregroundStyle(FW.textSecondary)
            }

            Button("Add Shortcut") {
                showingAddSheet = true
            }
            .buttonStyle(FWPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shortcutRow(_ shortcut: ShortcutItem) -> some View {
        HStack(spacing: FW.spacing16) {
            VStack(alignment: .leading, spacing: FW.spacing4) {
                Text(shortcut.trigger)
                    .font(.headline)
                    .foregroundStyle(FW.accent)

                Text(shortcut.replacement)
                    .font(.body)
                    .foregroundStyle(FW.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            if shortcut.useCount > 0 {
                Text("\(shortcut.useCount)")
                    .font(FW.fontMonoSmall)
                    .foregroundStyle(FW.textMuted)
                    .padding(.horizontal, FW.spacing8)
                    .padding(.vertical, FW.spacing4)
                    .background {
                        Capsule()
                            .fill(FW.background)
                    }
            }

            Button {
                deleteShortcut(shortcut)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(FW.danger.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(FW.spacing16)
        .fwSection()
    }

    private func refreshShortcuts() {
        if let raw = appState.engine.shortcuts {
            shortcuts = raw.compactMap { dict in
                guard let trigger = dict["trigger"] as? String,
                      let replacement = dict["replacement"] as? String
                else {
                    return nil
                }
                let useCount = dict["use_count"] as? Int ?? 0
                return ShortcutItem(trigger: trigger, replacement: replacement, useCount: useCount)
            }
        }
    }

    private func addShortcut() {
        guard !newTrigger.isEmpty, !newReplacement.isEmpty else { return }

        if appState.addShortcut(trigger: newTrigger, replacement: newReplacement) {
            refreshShortcuts()
            newTrigger = ""
            newReplacement = ""
            showingAddSheet = false
        }
    }

    private func deleteShortcut(_ shortcut: ShortcutItem) {
        if appState.removeShortcut(trigger: shortcut.trigger) {
            refreshShortcuts()
        }
    }
}

// MARK: - Supporting Types

struct ShortcutItem: Identifiable {
    let id = UUID()
    let trigger: String
    let replacement: String
    let useCount: Int
}

struct AddShortcutSheet: View {
    @Binding var trigger: String
    @Binding var replacement: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: FW.spacing24) {
            // Header
            VStack(spacing: FW.spacing8) {
                Text("Add Shortcut")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FW.textPrimary)

                Text("Say the trigger phrase to expand it")
                    .font(.body)
                    .foregroundStyle(FW.textSecondary)
            }

            // Form
            VStack(spacing: FW.spacing16) {
                VStack(alignment: .leading, spacing: FW.spacing8) {
                    Text("Trigger")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FW.textSecondary)

                    FWTextField(text: $trigger, placeholder: "e.g., 'my email'")
                }

                VStack(alignment: .leading, spacing: FW.spacing8) {
                    Text("Replacement")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FW.textSecondary)

                    FWTextField(text: $replacement, placeholder: "e.g., 'hello@example.com'")
                }
            }

            // Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(FWGhostButtonStyle())

                Spacer()

                Button("Add") {
                    onAdd()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(FWPrimaryButtonStyle())
                .disabled(trigger.isEmpty || replacement.isEmpty)
                .opacity(trigger.isEmpty || replacement.isEmpty ? 0.5 : 1)
            }
        }
        .padding(FW.spacing24)
        .frame(width: 400)
        .background(FW.surface)
    }
}

#Preview {
    ShortcutsContentView()
        .environmentObject(AppState())
}
