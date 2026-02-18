//
// AppDelegate.swift
// Flow
//
// Handles window lifecycle: ensures window opens on launch and handles reopen.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        DispatchQueue.main.async { @MainActor in
            NSApp.setActivationPolicy(.regular)
            WindowManager.openMainWindow()
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        WindowManager.openMainWindow()
        return true
    }
}
