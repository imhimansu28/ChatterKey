import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
enum TextSelectionReader {
    static let syntheticTextEventTag: Int64 = 0x434B434F5059

    @MainActor
    struct Target {
        let processIdentifier: pid_t
        let element: AXUIElement?
        let range: CFRange?

        var isCurrent: Bool {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier else { return false }
            guard let element else { return true }
            guard let focused = focusedElement(), CFEqual(element, focused) else { return false }
            if let range {
                guard let current = selectedRange(from: focused),
                      current.location == range.location, current.length == range.length else { return false }
            }
            return true
        }
    }

    static func target() -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = focusedElement()
        return Target(processIdentifier: app.processIdentifier, element: element, range: element.flatMap(selectedRange))
    }

    static func selectedText(in target: Target) async throws -> String? {
        try Task.checkCancellation()
        guard target.isCurrent else { throw SelectionError.focusChanged }
        if let element = target.element {
            guard stringAttribute(kAXSubroleAttribute, from: element) != kAXSecureTextFieldSubrole else { return nil }
            if let text = try usableSelection(stringAttribute(kAXSelectedTextAttribute, from: element)) {
                return text
            }
            if let text = try usableSelection(selectedTextFromValueAndRange(element)) {
                return text
            }
            // A known insertion point is not a selection. Do not copy the
            // current line in editors whose Cmd+C also works without selection.
            if target.range?.length == 0 { return nil }
        }
        return try await ClipboardTransaction.perform {
            guard target.isCurrent else { throw SelectionError.focusChanged }
            let text = try await copiedText(from: .general, copy: postCopy, isCurrent: { target.isCurrent })
            return try usableSelection(text)
        }
    }

    static func usableSelection(_ text: String?) throws -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard text.count <= 50_000 else { throw SelectionError.tooLong }
        return text
    }

    static func text(in value: String, range: CFRange) -> String? {
        let value = value as NSString
        guard range.location >= 0, range.length > 0,
              range.location <= value.length, range.length <= value.length - range.location else { return nil }
        return value.substring(with: NSRange(location: range.location, length: range.length))
    }

    private static func focusedElement() -> AXUIElement? {
        if let element = elementAttribute(kAXFocusedUIElementAttribute, from: AXUIElementCreateSystemWide()) {
            return element
        }
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        return elementAttribute(kAXFocusedUIElementAttribute, from: AXUIElementCreateApplication(application.processIdentifier))
    }

    private static func selectedTextFromValueAndRange(_ element: AXUIElement) -> String? {
        guard let value = stringAttribute(kAXValueAttribute, from: element),
              let range = selectedRange(from: element) else { return nil }
        return text(in: value, range: range)
    }

    private static func selectedRange(from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range) else { return nil }
        return range
    }

    static func copiedText(
        from pasteboard: NSPasteboard,
        copy: () throws -> Void,
        isCurrent: () -> Bool
    ) async throws -> String? {
        let previous = ClipboardSnapshot(pasteboard)
        let initialChangeCount = pasteboard.changeCount
        try copy()
        // Yield to the event tap and the target app rather than sleeping on
        // their event-processing thread. Never read a stale clipboard string.
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(750))
        while ContinuousClock.now < deadline {
            let copiedChangeCount = pasteboard.changeCount
            if copiedChangeCount != initialChangeCount,
               let text = pasteboard.string(forType: .string) {
                guard isCurrent() else { throw SelectionError.focusChanged }
                previous.restore(to: pasteboard, ifUnchangedSince: copiedChangeCount)
                return text
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard isCurrent() else { throw SelectionError.focusChanged }
        if pasteboard.changeCount != initialChangeCount {
            previous.restore(to: pasteboard, ifUnchangedSince: pasteboard.changeCount)
        }
        return nil
    }

    private static func postCopy() throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            throw SelectionError.couldNotCopy
        }
        for event in [down, up] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: syntheticTextEventTag)
            event.post(tap: .cghidEventTap)
        }
    }

    private static func elementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

nonisolated enum SelectionError: LocalizedError {
    case focusChanged
    case tooLong
    case couldNotCopy

    var errorDescription: String? {
        switch self {
        case .focusChanged: "The focused field or selection changed. Select the text again and start a new recording."
        case .tooLong: "Select no more than 50,000 characters for a voice edit."
        case .couldNotCopy: "The selected text could not be copied. Please try again."
        }
    }
}
