import AppKit
import CoreGraphics

@MainActor
enum TextInserter {
    static func insert(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        let previousItems = snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let transcriptChangeCount = pasteboard.changeCount

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            restore(previousItems, to: pasteboard)
            throw InsertError.couldNotPaste
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            // Do not overwrite something the user copied after dictation.
            guard pasteboard.changeCount == transcriptChangeCount else { return }
            restore(previousItems, to: pasteboard)
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        pasteboard.pasteboardItems?.map { source in
            let copy = NSPasteboardItem()
            for type in source.types {
                if let data = source.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []
    }
}

nonisolated enum InsertError: LocalizedError {
    case couldNotPaste
    var errorDescription: String? { "Text could not be pasted into the focused app." }
}
