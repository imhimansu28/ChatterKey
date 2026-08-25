import ApplicationServices
import Foundation

nonisolated enum TextSelectionReader {
    static func selectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let focusedElement = elementAttribute(kAXFocusedUIElementAttribute, from: systemWide),
              stringAttribute(kAXSubroleAttribute, from: focusedElement) != kAXSecureTextFieldSubrole else {
            return nil
        }

        let selectedText = stringAttribute(kAXSelectedTextAttribute, from: focusedElement)
            ?? selectedTextFromValueAndRange(focusedElement)
        guard let selectedText else { return nil }

        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 50_000 else { return nil }
        return selectedText
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
