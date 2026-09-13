import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show(appState: AppState) {
        if window == nil {
            let controller = NSHostingController(rootView: OnboardingView().environmentObject(appState))
            let window = NSWindow(contentViewController: controller)
            window.title = "Welcome to ChatterKey"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 640, height: 560))
            window.minSize = NSSize(width: 640, height: 560)
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

    func close() {
        window?.orderOut(nil)
    }
}
