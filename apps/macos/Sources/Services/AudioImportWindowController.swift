import AppKit
import SwiftUI

@MainActor
final class AudioImportWindowController: NSObject, NSWindowDelegate {
    static let shared = AudioImportWindowController()
    private var window: NSWindow?
    private weak var model: AudioImportModel?

    func show(appState: AppState) {
        if window == nil {
            model = appState.audioImport
            let view = AudioImportView(model: appState.audioImport).environmentObject(appState)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "ChatterKey — Import Audio"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 960, height: 700))
            window.minSize = NSSize(width: 820, height: 600)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let model else { return true }
        return confirmDiscard(model)
    }

    func confirmDiscard(_ model: AudioImportModel) -> Bool {
        guard model.requiresDiscardConfirmation else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard this audio import?"
        alert.informativeText = "This cancels active processing and clears completed chunks and unsaved results. Audio already sent to the provider cannot be recalled. Copy or Save any completed result before discarding."
        alert.addButton(withTitle: "Keep Open")
        alert.addButton(withTitle: "Discard")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        model?.clear()
    }
}
