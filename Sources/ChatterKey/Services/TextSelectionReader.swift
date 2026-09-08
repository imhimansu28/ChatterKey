import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
enum TextSelectionReader {
    static let syntheticCopyEventTag: Int64 = 0x434B434F5059

    static func selectedText() -> String? {
        let focusedElement = focusedElement()
        if let focusedElement,
           stringAttribute(kAXSubroleAttribute, from: focusedElement) == kAXSecureTextFieldSubrole {
            return nil
        }

        let accessibilitySelection = focusedElement.flatMap {
            stringAttribute(kAXSelectedTextAttribute, from: $0)
                ?? selectedTextFromValueAndRange($0)
        }
        guard let selectedText = accessibilitySelection ?? selectedTextFromClipboard() else { return nil }

        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 50_000 else { return nil }
        return selectedText
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        if let element = elementAttribute(kAXFocusedUIElementAttribute, from: systemWide) {
            return element
        }

        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        return elementAttribute(kAXFocusedUIElementAttribute, from: applicationElement)
    }

    private static func selectedTextFromValueAndRange(_ element: AXUIElement) -> String? {
        guard let value = stringAttribute(kAXValueAttribute, from: element) else { return nil }

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success,
        let rangeValue,
        CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }

        let axValue = unsafeDowncast(rangeValue, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range), range.length > 0 else { return nil }

        let nsRange = NSRange(location: range.location, length: range.length)
        let nsValue = value as NSString
        guard NSMaxRange(nsRange) <= nsValue.length else { return nil }
        return nsValue.substring(with: nsRange)
    }

    private static func selectedTextFromClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        let previousItems = snapshot(pasteboard)
        pasteboard.clearContents()
        let emptyChangeCount = pasteboard.changeCount

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            restore(previousItems, to: pasteboard)
            return nil
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticCopyEventTag)
        keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticCopyEventTag)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        for _ in 0..<12 where pasteboard.changeCount == emptyChangeCount {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let selectedText = pasteboard.changeCount == emptyChangeCount
            ? nil
            : pasteboard.string(forType: .string)
        restore(previousItems, to: pasteboard)
        return selectedText
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

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    private static func elementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
