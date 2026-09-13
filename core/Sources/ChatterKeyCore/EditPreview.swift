import Foundation

nonisolated package struct EditPreview: Sendable {
    package struct Segment: Equatable, Sendable {
        package var text: String
        package let changed: Bool
    }

    package struct ProtectedValue: Hashable, Sendable {
        package enum Kind: String, Sendable { case number = "Number", email = "Email", url = "URL" }
        package let kind: Kind
        package let text: String
    }

    package struct ValueChange: Identifiable, Sendable {
        package let value: ProtectedValue
        package let originalCount: Int
        package let proposedCount: Int
        package var id: ProtectedValue { value }
    }

    package let original: String
    package let proposed: String
    package let outputMode: OutputMode
    package let originalSegments: [Segment]
    package let proposedSegments: [Segment]
    package let usesPassageHighlight: Bool
    package let valueChanges: [ValueChange]

    package var hasChanges: Bool { original != proposed }

    package func allowsApply(acknowledgingValueChanges: Bool) -> Bool {
        hasChanges && !proposed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (valueChanges.isEmpty || acknowledgingValueChanges)
    }

    package init(original: String, proposed: String, outputMode: OutputMode) {
        self.original = original
        self.proposed = proposed
        self.outputMode = outputMode
        let before = Self.tokens(original)
        let after = Self.tokens(proposed)
        // Bound the quadratic diff work; large selections retain a complete,
        // literal preview with the changed passage highlighted instead.
        usesPassageHighlight = before.count > 1_000 || after.count > 1_000
        if usesPassageHighlight {
            let old = Array(original)
            let new = Array(proposed)
            let prefix = zip(old, new).prefix(while: { $0 == $1 }).count
            let suffix = zip(old.dropFirst(prefix).reversed(), new.dropFirst(prefix).reversed())
                .prefix(while: { $0 == $1 }).count
            originalSegments = Self.passage(old, prefix: prefix, suffix: suffix)
            proposedSegments = Self.passage(new, prefix: prefix, suffix: suffix)
        } else {
            let difference = after.difference(from: before)
            var removed = Set<Int>()
            var inserted = Set<Int>()
            for change in difference {
                switch change {
                case .remove(let offset, _, _): removed.insert(offset)
                case .insert(let offset, _, _): inserted.insert(offset)
                }
            }
            originalSegments = Self.segments(before, changed: removed)
            proposedSegments = Self.segments(after, changed: inserted)
        }
        let oldValues = Self.protectedValues(in: original)
        let newValues = Self.protectedValues(in: proposed)
        let oldCounts = Dictionary(oldValues.map { ($0, 1) }, uniquingKeysWith: +)
        let newCounts = Dictionary(newValues.map { ($0, 1) }, uniquingKeysWith: +)
        var seen = Set<ProtectedValue>()
        valueChanges = (oldValues + newValues).compactMap { value in
            guard seen.insert(value).inserted else { return nil }
            let before = oldCounts[value, default: 0]
            let after = newCounts[value, default: 0]
            guard before != after else { return nil }
            return ValueChange(value: value, originalCount: before, proposedCount: after)
        }
    }

    private static let tokenPattern = try! NSRegularExpression(pattern: #"\s+|[\p{L}\p{M}\p{N}_]+|[^\s]"#)
    private static let valuePattern = try! NSRegularExpression(
        pattern: #"((?:https?://|www\.)[^\s<>"`]+)|((?<![A-Z0-9.!#$%&'*+/=?^_`{|}~-])[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9.-]*[A-Z0-9])?\.[A-Z]{2,})|((?<![\p{L}\p{N}_])(?:[-+−]?\p{Sc}\s*|\p{Sc}\s*[-+−]?|[-+−]?)\p{Nd}+(?:[.,:/\-]\p{Nd}+)*(?:[%٪])?(?![\p{L}\p{N}_]))"#,
        options: [.caseInsensitive]
    )

    private static func tokens(_ text: String) -> [String] {
        let source = text as NSString
        return tokenPattern.matches(in: text, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range) }
    }

    package static func protectedValues(in text: String) -> [ProtectedValue] {
        let source = text as NSString
        return valuePattern.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            if match.range(at: 1).location != NSNotFound {
                // Keep punctuation: trimming it could conceal a changed URL path/query.
                return ProtectedValue(kind: .url, text: source.substring(with: match.range))
            }
            return ProtectedValue(
                kind: match.range(at: 2).location != NSNotFound ? .email : .number,
                text: source.substring(with: match.range)
            )
        }
    }

    private static func segments(_ tokens: [String], changed: Set<Int>) -> [Segment] {
        var result: [Segment] = []
        for (index, token) in tokens.enumerated() {
            let isChanged = changed.contains(index)
            if result.last?.changed == isChanged {
                result[result.count - 1].text += token
            } else {
                result.append(Segment(text: token, changed: isChanged))
            }
        }
        return result
    }

    private static func passage(_ characters: [Character], prefix: Int, suffix: Int) -> [Segment] {
        [
            Segment(text: String(characters.prefix(prefix)), changed: false),
            Segment(text: String(characters.dropFirst(prefix).dropLast(suffix)), changed: true),
            Segment(text: String(characters.suffix(suffix)), changed: false)
        ].filter { !$0.text.isEmpty }
    }
}
