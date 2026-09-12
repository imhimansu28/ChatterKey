import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
enum TextInserter {
    static func insert(
        _ text: String,
        into target: TextSelectionReader.Target,
        replacing selection: String? = nil
    ) async throws {
        guard target.isCurrent else { throw InsertError.targetChanged }
        if let selection {
            guard try await TextSelectionReader.selectedText(in: target) == selection else {
                throw InsertError.targetChanged
            }
        }
        try await ClipboardTransaction.perform {
            guard target.isCurrent else { throw InsertError.targetChanged }
            if let element = target.element {
                let subrole = TextSelectionReader.stringAttribute(kAXSubroleAttribute, from: element)
                let role = TextSelectionReader.stringAttribute(kAXRoleAttribute, from: element)
                guard subrole != kAXSecureTextFieldSubrole, role != kAXStaticTextRole else {
                    throw InsertError.couldNotPaste
                }
            }
            guard let source = CGEventSource(stateID: .hidSystemState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                throw InsertError.couldNotPaste
            }
            let pasteboard = NSPasteboard.general
            let previous = ClipboardSnapshot(pasteboard)
            pasteboard.clearContents()
            let written = pasteboard.setString(text, forType: .string)
            let changeCount = pasteboard.changeCount
            defer { previous.restore(to: pasteboard, ifUnchangedSince: changeCount) }
            guard written else { throw InsertError.couldNotPaste }
            for event in [down, up] {
                event.flags = .maskCommand
                event.setIntegerValueField(.eventSourceUserData, value: TextSelectionReader.syntheticTextEventTag)
                event.post(tap: .cghidEventTap)
            }
            try await Task.sleep(for: .milliseconds(700))
        }
    }
}

nonisolated enum InsertError: LocalizedError {
    case couldNotPaste
    case targetChanged

    var errorDescription: String? {
        switch self {
        case .couldNotPaste: "Text could not be pasted into the focused app."
        case .targetChanged: "The original field or selection changed before the text was ready."
        }
    }
}
