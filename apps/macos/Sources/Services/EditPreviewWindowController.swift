import AppKit
import SwiftUI

@MainActor
final class EditPreviewWindowController: NSObject, NSWindowDelegate {
    static let shared = EditPreviewWindowController()
    private var window: NSWindow?
    private weak var appState: AppState?

    func show(appState: AppState) {
        guard let preview = appState.editPreview else { return }
        self.appState = appState
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 660),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
            )
            window.title = "ChatterKey — Review voice edit"
            window.minSize = NSSize(width: 700, height: 620)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        window?.contentView = NSHostingView(rootView: EditPreviewView(
            preview: preview,
            recoveryMessage: appState.editPreviewMessage,
            canApplyToTarget: appState.canApplyEditPreview,
            apply: { [weak appState] acknowledged in appState?.applyEditPreview(acknowledgingValueChanges: acknowledged) },
            copy: { [weak appState] in appState?.copyEditPreview() },
            discard: { [weak appState] in appState?.discardEditPreview() }
        ))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
        // Release the preview text and closures instead of retaining discarded edits.
        window?.contentView = nil
    }

    func windowWillClose(_ notification: Notification) {
        appState?.discardEditPreview()
    }
}
