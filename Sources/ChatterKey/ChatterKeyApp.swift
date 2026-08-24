import AppKit
import SwiftUI

@main
struct ChatterKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MainPopoverView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.phase == .listening ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppState.shared.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppState.shared.refreshPermissions()
    }
}
