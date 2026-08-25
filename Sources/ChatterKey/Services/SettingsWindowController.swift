import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?

    func show(appState: AppState, section: SettingsSection = .general) {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        SettingsNavigation.shared.selectedSection = section
        if window == nil {
            let content = SettingsView().environmentObject(appState)
            let controller = NSHostingController(rootView: content)
            let window = NSWindow(contentViewController: controller)
            window.title = "ChatterKey Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 840, height: 660))
            window.minSize = NSSize(width: 800, height: 620)
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

    func insert(_ item: DictationHistoryItem, appState: AppState) {
        window?.orderOut(nil)
        previousApp?.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            appState.insert(item)
        }
    }
}
