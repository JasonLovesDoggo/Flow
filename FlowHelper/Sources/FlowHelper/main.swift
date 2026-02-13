//
// main.swift
// FlowHelper
//
// Minimal helper app (LSUIElement) that runs CGEventTap for hotkey detection.
// Communicates with main Flow app via JSON over stdin/stdout.
//
// As an agent/LSUIElement app, this process is NOT subject to App Nap,
// so the CGEventTap stays active even when the main app is backgrounded.
//

import ApplicationServices
import Foundation

// MARK: - JSON Protocol

struct HotkeyEvent: Codable {
    let event: String // "hotkey"
    let trigger: String // "pressed", "released", "toggle"
}

struct ConfigMessage: Codable {
    let command: String // "setHotkey", "quit"
    let hotkey: HotkeyConfig?
}

struct HotkeyConfig: Codable {
    let kind: String // "globe", "modifierOnly", "custom"
    let modifier: String? // For modifierOnly: "option", "shift", "control", "command"
    let keyCode: Int? // For custom
    let modifiers: Int? // For custom (bitmask: command=1, option=2, shift=4, control=8)
}

// MARK: - Hotkey Kind (mirrors main app's Hotkey.Kind)

enum HotkeyKind: Equatable {
    case globe
    case modifierOnly(ModifierKey)
    case custom(keyCode: Int, modifiers: Int)

    enum ModifierKey: String {
        case option, shift, control, command

        var cgFlag: CGEventFlags {
            switch self {
            case .option: return .maskAlternate
            case .shift: return .maskShift
            case .control: return .maskControl
            case .command: return .maskCommand
            }
        }
    }

    static func from(config: HotkeyConfig) -> HotkeyKind {
        switch config.kind {
        case "modifierOnly":
            if let mod = config.modifier, let key = ModifierKey(rawValue: mod) {
                return .modifierOnly(key)
            }
        case "custom":
            if let keyCode = config.keyCode, let modifiers = config.modifiers {
                return .custom(keyCode: keyCode, modifiers: modifiers)
            }
        default:
            break
        }
        return .globe
    }
}

// MARK: - Hotkey Handler

final class HotkeyHandler {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotkey: HotkeyKind

    // State for Fn key
    private var isFunctionDown = false
    private var functionUsedAsModifier = false
    private var hasFiredFnPressed = false
    private var fnPressTime: Date?

    // State for modifier-only
    private var isModifierDown = false
    private var modifierUsedAsModifier = false
    private var hasFiredModifierPressed = false
    private var modifierPressTime: Date?

    private let staleKeyTimeout: TimeInterval = 5.0

    init(hotkey: HotkeyKind) {
        self.hotkey = hotkey
    }

    func updateHotkey(_ hotkey: HotkeyKind) {
        self.hotkey = hotkey
        resetState()
    }

    private func resetState() {
        isFunctionDown = false
        functionUsedAsModifier = false
        hasFiredFnPressed = false
        fnPressTime = nil
        isModifierDown = false
        modifierUsedAsModifier = false
        hasFiredModifierPressed = false
        modifierPressTime = nil
    }

    func startListening() -> Bool {
        guard eventTap == nil else { return true }

        // Check accessibility permission
        let options = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            sendError("Accessibility permission not granted")
            return false
        }

        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            sendError("Failed to create event tap")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)

        // Start health check timer
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.ensureTapEnabled()
        }

        return true
    }

    private func ensureTapEnabled() {
        guard let tap = eventTap else { return }
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            NSLog("[FlowHelper] Re-enabled event tap")
        }
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
        // Handle tap being disabled by system
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        switch hotkey {
        case .globe:
            handleGlobeHotkey(type: type, event: event)
        case let .modifierOnly(modifier):
            handleModifierOnlyHotkey(type: type, event: event, modifier: modifier)
        case let .custom(keyCode, modifiers):
            handleCustomHotkey(type: type, event: event, keyCode: keyCode, modifiers: modifiers)
        }
    }

    // MARK: - Globe (Fn) Key Handler

    private func handleGlobeHotkey(type: CGEventType, event: CGEvent) {
        switch type {
        case .flagsChanged:
            handleFnFlagChange(event)
        case .keyDown:
            if isFunctionDown, event.flags.contains(.maskSecondaryFn) {
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                if keycode != 63 { // kVK_Function
                    functionUsedAsModifier = true
                }
            }
        default:
            break
        }
    }

    private func handleFnFlagChange(_ event: CGEvent) {
        let hasFn = event.flags.contains(.maskSecondaryFn)

        // Stale state recovery
        if isFunctionDown, let pressTime = fnPressTime,
           Date().timeIntervalSince(pressTime) > staleKeyTimeout
        {
            resetState()
        }

        guard hasFn != isFunctionDown else { return }

        if hasFn {
            isFunctionDown = true
            fnPressTime = Date()
            functionUsedAsModifier = false
            hasFiredFnPressed = true
            sendEvent("pressed")
            return
        }

        guard isFunctionDown else { return }
        isFunctionDown = false
        fnPressTime = nil

        if hasFiredFnPressed, !functionUsedAsModifier {
            sendEvent("released")
        }
        hasFiredFnPressed = false
    }

    // MARK: - Modifier-Only Handler

    private func handleModifierOnlyHotkey(type: CGEventType, event: CGEvent, modifier: HotkeyKind.ModifierKey) {
        switch type {
        case .flagsChanged:
            handleModifierFlagChange(event, modifier: modifier)
        case .keyDown:
            if isModifierDown, event.flags.contains(modifier.cgFlag) {
                modifierUsedAsModifier = true
            }
        default:
            break
        }
    }

    private func handleModifierFlagChange(_ event: CGEvent, modifier: HotkeyKind.ModifierKey) {
        let hasModifier = event.flags.contains(modifier.cgFlag)

        // Stale state recovery
        if isModifierDown, let pressTime = modifierPressTime,
           Date().timeIntervalSince(pressTime) > staleKeyTimeout
        {
            resetState()
        }

        let otherModifiersPressed = hasOtherModifiers(event.flags, excluding: modifier)

        guard hasModifier != isModifierDown else {
            if isModifierDown, otherModifiersPressed {
                modifierUsedAsModifier = true
            }
            return
        }

        if hasModifier {
            if otherModifiersPressed { return }
            isModifierDown = true
            modifierPressTime = Date()
            modifierUsedAsModifier = false
            hasFiredModifierPressed = true
            sendEvent("pressed")
            return
        }

        guard isModifierDown else { return }
        isModifierDown = false
        modifierPressTime = nil

        if hasFiredModifierPressed, !modifierUsedAsModifier {
            sendEvent("released")
        }
        hasFiredModifierPressed = false
    }

    private func hasOtherModifiers(_ flags: CGEventFlags, excluding: HotkeyKind.ModifierKey) -> Bool {
        let allModifiers: [(CGEventFlags, HotkeyKind.ModifierKey)] = [
            (.maskAlternate, .option),
            (.maskShift, .shift),
            (.maskControl, .control),
            (.maskCommand, .command),
        ]
        for (flag, key) in allModifiers {
            if key != excluding, flags.contains(flag) {
                return true
            }
        }
        return false
    }

    // MARK: - Custom Key Combo Handler

    private func handleCustomHotkey(type: CGEventType, event: CGEvent, keyCode: Int, modifiers: Int) {
        guard type == .keyDown else { return }

        let pressedKeyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let pressedModifiers = modifiersFromCGFlags(event.flags)

        if pressedKeyCode == keyCode, pressedModifiers == modifiers {
            sendEvent("toggle")
        }
    }

    private func modifiersFromCGFlags(_ flags: CGEventFlags) -> Int {
        var result = 0
        if flags.contains(.maskCommand) { result |= 1 }
        if flags.contains(.maskAlternate) { result |= 2 }
        if flags.contains(.maskShift) { result |= 4 }
        if flags.contains(.maskControl) { result |= 8 }
        return result
    }

    // MARK: - Output

    private func sendEvent(_ trigger: String) {
        let event = HotkeyEvent(event: "hotkey", trigger: trigger)
        send(event)
    }

    private func sendError(_ message: String) {
        let error = ["event": "error", "message": message]
        if let data = try? JSONEncoder().encode(error),
           let json = String(data: data, encoding: .utf8)
        {
            print(json)
            fflush(stdout)
        }
    }

    private func send<T: Encodable>(_ value: T) {
        if let data = try? JSONEncoder().encode(value),
           let json = String(data: data, encoding: .utf8)
        {
            print(json)
            fflush(stdout)
        }
    }
}

// MARK: - Event Tap Callback

private func eventTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }
    let handler = Unmanaged<HotkeyHandler>.fromOpaque(refcon).takeUnretainedValue()
    handler.handleEvent(type: type, event: event)
    return Unmanaged.passUnretained(event)
}

// MARK: - Main

// Default to globe key
var currentHotkey = HotkeyKind.globe
let handler = HotkeyHandler(hotkey: currentHotkey)

// Start listening
guard handler.startListening() else {
    exit(1)
}

// Send ready message
let ready = ["event": "ready"]
if let data = try? JSONEncoder().encode(ready),
   let json = String(data: data, encoding: .utf8)
{
    print(json)
    fflush(stdout)
}

// Read config from stdin in background
DispatchQueue.global(qos: .userInteractive).async {
    while let line = readLine() {
        guard let data = line.data(using: .utf8),
              let message = try? JSONDecoder().decode(ConfigMessage.self, from: data)
        else { continue }

        switch message.command {
        case "setHotkey":
            if let config = message.hotkey {
                let newHotkey = HotkeyKind.from(config: config)
                DispatchQueue.main.async {
                    handler.updateHotkey(newHotkey)
                }
            }
        case "quit":
            exit(0)
        default:
            break
        }
    }
}

// Run the main loop
RunLoop.main.run()
