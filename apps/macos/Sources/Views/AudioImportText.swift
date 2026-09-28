import SwiftUI

struct AudioImportText: View {
    let text: String
    @State private var rendered: AttributedString?

    var body: some View {
        Text(rendered ?? AttributedString(text))
            .task(id: text) { rendered = Self.format(text) }
    }

    static func format(_ source: String) -> AttributedString {
        guard let parsed = try? AttributedString(markdown: source, options: .init(failurePolicy: .throwError)) else {
            return AttributedString(source)
        }
        var output = AttributedString()
        var previousList: Int?
        var previousHeading = false
        var seenItems = Set<Int>()
        for (intent, range) in parsed.runs[\.presentationIntent] {
            var block = AttributedString(parsed[range])
            var prefix = ""
            var item: Int?
            var ordinal: Int?
            var ordered = false
            var listDepth = 0
            var rootList: Int?
            var heading = false
            for component in intent?.components ?? [] {
                switch component.kind {
                case .header(let level):
                    heading = true
                    block.font = .system(size: level == 1 ? 23 : level == 2 ? 18 : 16, weight: .semibold)
                case .listItem(let number):
                    if item == nil { item = component.identity; ordinal = number }
                case .orderedList:
                    if listDepth == 0 { ordered = true }
                    listDepth += 1
                    rootList = component.identity
                case .unorderedList:
                    listDepth += 1
                    rootList = component.identity
                case .codeBlock:
                    block.font = .system(size: 13, design: .monospaced)
                case .blockQuote:
                    prefix = "│ "
                case .paragraph:
                    break
                default:
                    // Keep unsupported layouts (such as tables) intact instead of flattening their meaning.
                    return AttributedString(source)
                }
            }
            if let item {
                let marker = seenItems.insert(item).inserted ? (ordered ? "\(ordinal ?? 1). " : "• ") : "  "
                prefix = String(repeating: "    ", count: max(0, listDepth - 1)) + marker
            }
            if !output.characters.isEmpty {
                let compact = previousHeading || (rootList != nil && rootList == previousList)
                output.append(AttributedString(compact ? "\n" : "\n\n"))
            }
            // Generated links remain text, not interactive actions. Copy/Save retain the source verbatim.
            block.link = nil
            output.append(AttributedString(prefix))
            output.append(block)
            previousList = rootList
            previousHeading = heading
        }
        return output.characters.isEmpty ? AttributedString(source) : output
    }
}
