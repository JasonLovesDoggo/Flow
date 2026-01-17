//
// FlowWhisprApp.swift
// FlowWhispr
//
// Main app entry point with single-window architecture.
//

import SwiftUI

@main
struct FlowWhisprApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

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
            Image(systemName: appState.isRecording ? "mic.fill" : "mic")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(appState.isRecording ? .red : .primary)
        }
        .menuBarExtraStyle(.menu)
    }
}
