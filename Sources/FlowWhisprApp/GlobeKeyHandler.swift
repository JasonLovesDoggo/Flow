//
// GlobeKeyHandler.swift
// FlowWhispr
//
// Captures the globe key (🌐) using IOHIDManager.
// The globe key is Apple's vendor-specific HID at usage page 0xFF, usage 0x03.
// Requires "Input Monitoring" permission in System Settings > Privacy & Security.
//

import Foundation
@preconcurrency import IOKit
@preconcurrency import IOKit.hid

@MainActor
final class GlobeKeyHandler {
    // nonisolated(unsafe) because IOHIDManager isn't Sendable but we only access it from main thread
    nonisolated(unsafe) private var manager: IOHIDManager?
    private var onGlobeKeyPressed: (@Sendable () -> Void)?
    private var callbackWrapper: CallbackWrapper?

    init(onGlobeKeyPressed: @escaping @Sendable () -> Void) {
        self.onGlobeKeyPressed = onGlobeKeyPressed
        setupHIDManager()
    }

    private func setupHIDManager() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager else { return }

        // Match all keyboards
        let matchingDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

        // Capture the callback in a way that's safe for cross-isolation
        let callback = self.onGlobeKeyPressed
        let wrappedCallback: GlobeKeyCallback = { usagePage, usage, intValue in
            // Apple Globe Key: usage page 0xFF (AppleVendor Top Case), usage 0x03 (KeyboardFn)
            // intValue == 1 means key press, 0 means release
            if usagePage == 0xFF && usage == 0x03 && intValue == 1 {
                callback?()
            }
        }

        // Store the callback wrapper so it stays alive
        callbackWrapper = CallbackWrapper(wrappedCallback)
        let context = Unmanaged.passUnretained(callbackWrapper!).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, globeKeyHIDCallback, context)

        // Schedule with run loop
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}

// Type alias for the callback closure
private typealias GlobeKeyCallback = @Sendable (UInt32, UInt32, CFIndex) -> Void

// Wrapper class to hold the callback for passing through C void pointer
private final class CallbackWrapper: @unchecked Sendable {
    let callback: GlobeKeyCallback

    init(_ callback: @escaping GlobeKeyCallback) {
        self.callback = callback
    }
}

// C callback function for IOHIDManager
private func globeKeyHIDCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context else { return }
    let wrapper = Unmanaged<CallbackWrapper>.fromOpaque(context).takeUnretainedValue()

    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let intValue = IOHIDValueGetIntegerValue(value)

    // Call the wrapped callback on the main thread
    DispatchQueue.main.async {
        wrapper.callback(usagePage, usage, intValue)
    }
}
