//
// FlowApp.swift
// Flow
//
// Main app entry point with single-window architecture.
//

import SwiftUI

@main
struct FlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    private var menuBarIcon: NSImage? {
        guard let iconURL = Bundle.module.url(forResource: "menubar", withExtension: "png"),
              let icon = NSImage(contentsOf: iconURL)
        else {
            return nil
        }
        icon.isTemplate = true
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }

    var body: some Scene {
        // main window
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: WindowSize.width, height: WindowSize.height)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // menu bar
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            if let icon = menuBarIcon {
                Image(nsImage: icon)
                    .padding(.top, 2)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
