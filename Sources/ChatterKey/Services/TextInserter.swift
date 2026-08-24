import AppKit
import CoreGraphics

@MainActor
enum TextInserter {
    static func insert(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.pasteboardItems?.compactMap { item -> [String: Data]? in
            var values: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { values[type.rawValue] = data }
            }
            return values
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw InsertError.couldNotPaste
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        if let previous {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                pasteboard.clearContents()
                for values in previous {
                    let item = NSPasteboardItem()
                    for (rawType, data) in values {
                        item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
                    }
                    pasteboard.writeObjects([item])
                }
            }
        }
    }
}

nonisolated enum InsertError: LocalizedError {
    case couldNotPaste
    var errorDescription: String? { "Text could not be pasted into the focused app." }
}
