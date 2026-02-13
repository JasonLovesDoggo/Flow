//
// Hotkey.swift
// Flow
//
// Storage and display helpers for recording hotkeys.
//

import AppKit
import Foundation

// Key codes from Carbon (avoiding Carbon.HIToolbox dependency)
// These are stable macOS virtual key codes
enum KeyCode {
    static let returnKey = 0x24
    static let tab = 0x30
    static let space = 0x31
    static let delete = 0x33
    static let escape = 0x35
    static let forwardDelete = 0x75
    static let help = 0x72
    static let home = 0x73
    static let end = 0x77
    static let pageUp = 0x74
    static let pageDown = 0x79
    static let leftArrow = 0x7B
    static let rightArrow = 0x7C
    static let downArrow = 0x7D
    static let upArrow = 0x7E
    static let f1 = 0x7A
    static let f2 = 0x78
    static let f3 = 0x63
    static let f4 = 0x76
    static let f5 = 0x60
    static let f6 = 0x61
    static let f7 = 0x62
    static let f8 = 0x64
    static let f9 = 0x65
    static let f10 = 0x6D
    static let f11 = 0x67
    static let f12 = 0x6F
    static let f13 = 0x69
    static let f14 = 0x6B
    static let f15 = 0x71
    static let f16 = 0x6A
    static let f17 = 0x40
    static let f18 = 0x4F
    static let f19 = 0x50
    static let f20 = 0x5A
}

struct Hotkey: Equatable {
    enum Kind: Equatable {
        case globe
        case modifierOnly(ModifierKey)
        case custom(keyCode: Int, modifiers: Modifiers, keyLabel: String)
    }

    enum ModifierKey: String, Codable, CaseIterable {
        case option
        case shift
        case control
        case command

        var cgFlag: CGEventFlags {
            switch self {
            case .option: return .maskAlternate
            case .shift: return .maskShift
            case .control: return .maskControl
            case .command: return .maskCommand
            }
        }

        var displayName: String {
            switch self {
            case .option: return "⌥ Option"
            case .shift: return "⇧ Shift"
            case .control: return "⌃ Control"
            case .command: return "⌘ Command"
            }
        }

        var symbol: String {
            switch self {
            case .option: return "⌥"
            case .shift: return "⇧"
            case .control: return "⌃"
            case .command: return "⌘"
            }
        }

        static func from(cgFlags: CGEventFlags) -> ModifierKey? {
            // Return the single modifier if exactly one is pressed
            let modifiers: [(CGEventFlags, ModifierKey)] = [
                (.maskAlternate, .option),
                (.maskShift, .shift),
                (.maskControl, .control),
                (.maskCommand, .command),
            ]
            var found: ModifierKey?
            for (flag, key) in modifiers {
                if cgFlags.contains(flag) {
                    if found != nil { return nil } // Multiple modifiers pressed
                    found = key
                }
            }
            return found
        }
    }

    struct Modifiers: OptionSet, Equatable {
        let rawValue: Int

        static let command = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let control = Modifiers(rawValue: 1 << 3)
    }

    private struct StoredHotkey: Codable {
        var kind: String
        var keyCode: Int?
        var modifiers: Int?
        var keyLabel: String?
        var modifierKey: String?
    }

    static let storageKey = "recordHotkey"
    static let defaultHotkey = Hotkey(kind: .globe)

    let kind: Kind

    var displayName: String {
        switch kind {
        case .globe:
            return "Fn key"
        case let .modifierOnly(modifier):
            return modifier.displayName
        case let .custom(_, modifiers, keyLabel):
            return "\(modifiers.displayString)\(keyLabel)"
        }
    }

    static func load() -> Hotkey {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return defaultHotkey
        }
        guard let stored = try? JSONDecoder().decode(StoredHotkey.self, from: data) else {
            return defaultHotkey
        }
        return fromStored(stored)
    }

    func save() {
        let stored = toStored()
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: Hotkey.storageKey)
    }

    static func from(event: NSEvent) -> Hotkey {
        let modifiers = Modifiers.from(nsFlags: event.modifierFlags)
        let keyCode = Int(event.keyCode)
        let keyLabel = keyLabel(for: event)
        return Hotkey(kind: .custom(keyCode: keyCode, modifiers: modifiers, keyLabel: keyLabel))
    }

    static func modifiersMatch(_ modifiers: Modifiers, eventFlags: CGEventFlags) -> Bool {
        modifiers == Modifiers.from(cgFlags: eventFlags)
    }

    private func toStored() -> StoredHotkey {
        switch kind {
        case .globe:
            return StoredHotkey(kind: "globe")
        case let .modifierOnly(modifier):
            return StoredHotkey(kind: "modifierOnly", modifierKey: modifier.rawValue)
        case let .custom(keyCode, modifiers, keyLabel):
            return StoredHotkey(
                kind: "custom",
                keyCode: keyCode,
                modifiers: modifiers.rawValue,
                keyLabel: keyLabel
            )
        }
    }

    private static func fromStored(_ stored: StoredHotkey) -> Hotkey {
        switch stored.kind {
        case "modifierOnly":
            if let modifierKeyRaw = stored.modifierKey,
               let modifier = ModifierKey(rawValue: modifierKeyRaw)
            {
                return Hotkey(kind: .modifierOnly(modifier))
            }
        case "custom":
            if let keyCode = stored.keyCode,
               let modifiersRaw = stored.modifiers,
               let keyLabel = stored.keyLabel,
               !keyLabel.isEmpty
            {
                return Hotkey(
                    kind: .custom(
                        keyCode: keyCode,
                        modifiers: Modifiers(rawValue: modifiersRaw),
                        keyLabel: keyLabel
                    )
                )
            }
        default:
            break
        }

        return defaultHotkey
    }

    private static func keyLabel(for event: NSEvent) -> String {
        let keyCode = Int(event.keyCode)
        if let label = specialKeyLabels[keyCode] {
            return label
        }

        if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
            return characters.uppercased()
        }

        return "Key \(keyCode)"
    }

    private static let specialKeyLabels: [Int: String] = [
        KeyCode.returnKey: "Return",
        KeyCode.tab: "Tab",
        KeyCode.space: "Space",
        KeyCode.delete: "Delete",
        KeyCode.escape: "Esc",
        KeyCode.forwardDelete: "Forward Delete",
        KeyCode.help: "Help",
        KeyCode.home: "Home",
        KeyCode.end: "End",
        KeyCode.pageUp: "Page Up",
        KeyCode.pageDown: "Page Down",
        KeyCode.leftArrow: "Left",
        KeyCode.rightArrow: "Right",
        KeyCode.downArrow: "Down",
        KeyCode.upArrow: "Up",
        KeyCode.f1: "F1",
        KeyCode.f2: "F2",
        KeyCode.f3: "F3",
        KeyCode.f4: "F4",
        KeyCode.f5: "F5",
        KeyCode.f6: "F6",
        KeyCode.f7: "F7",
        KeyCode.f8: "F8",
        KeyCode.f9: "F9",
        KeyCode.f10: "F10",
        KeyCode.f11: "F11",
        KeyCode.f12: "F12",
        KeyCode.f13: "F13",
        KeyCode.f14: "F14",
        KeyCode.f15: "F15",
        KeyCode.f16: "F16",
        KeyCode.f17: "F17",
        KeyCode.f18: "F18",
        KeyCode.f19: "F19",
        KeyCode.f20: "F20",
    ]
}

extension Hotkey.Modifiers {
    var displayString: String {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        return parts.joined()
    }

    static func from(nsFlags: NSEvent.ModifierFlags) -> Hotkey.Modifiers {
        var modifiers: Hotkey.Modifiers = []
        if nsFlags.contains(.control) { modifiers.insert(.control) }
        if nsFlags.contains(.option) { modifiers.insert(.option) }
        if nsFlags.contains(.shift) { modifiers.insert(.shift) }
        if nsFlags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    static func from(cgFlags: CGEventFlags) -> Hotkey.Modifiers {
        var modifiers: Hotkey.Modifiers = []
        if cgFlags.contains(.maskControl) { modifiers.insert(.control) }
        if cgFlags.contains(.maskAlternate) { modifiers.insert(.option) }
        if cgFlags.contains(.maskShift) { modifiers.insert(.shift) }
        if cgFlags.contains(.maskCommand) { modifiers.insert(.command) }
        return modifiers
    }
}
