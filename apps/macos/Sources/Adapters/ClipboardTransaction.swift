import AppKit

@MainActor
enum ClipboardTransaction {
    private static var busy = false

    static func perform<Value: Sendable>(
        _ operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        while busy { try await Task.sleep(for: .milliseconds(10)) }
        try Task.checkCancellation()
        busy = true
        // A posted copy/paste cannot be cancelled. Finish its bounded cleanup
        // before allowing another attempt to borrow the clipboard.
        let task = Task { @MainActor in
            defer { busy = false }
            return try await operation()
        }
        let value = try await task.value
        try Task.checkCancellation()
        return value
    }
}

@MainActor
struct ClipboardSnapshot {
    private let items: [NSPasteboardItem]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { source in
            let copy = NSPasteboardItem()
            for type in source.types {
                if let data = source.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    func restore(to pasteboard: NSPasteboard, ifUnchangedSince changeCount: Int) {
        guard pasteboard.changeCount == changeCount else { return }
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
