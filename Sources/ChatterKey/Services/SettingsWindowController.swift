import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(appState: AppState) {
        if window == nil {
            let content = SettingsView().environmentObject(appState)
            let controller = NSHostingController(rootView: content)
            let window = NSWindow(contentViewController: controller)
            window.title = "ChatterKey Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 560, height: 590))
            window.minSize = NSSize(width: 560, height: 590)
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
