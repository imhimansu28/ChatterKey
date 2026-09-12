import Foundation

nonisolated enum VoiceTextProcessor {
    static func process(_ text: String, settings: ProviderSettings) -> String {
        guard settings.outputMode != .verbatim else { return text }
        var output = text
        if settings.spokenCommandsEnabled {
            output = applyCommands(to: output)
        }
        output = applySnippets(to: output, snippets: settings.voiceSnippets)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func applyCommands(to text: String) -> String {
        let commands: [(phrases: [String], replacement: String)] = [
            (["new paragraph kar do", "naya paragraph", "new paragraph"], "\n\n"),
            (["new line kar do", "nayi line", "new line"], "\n"),
            (["bullet point kar do", "bullet point"], "\n•"),
            (["question mark"], "?"),
            (["full stop"], "."),
            (["comma"], ",")
        ]

        var output = text
        for command in commands {
            for phrase in command.phrases {
                output = replacePhrase(phrase, with: command.replacement, in: output)
            }
        }

        output = output.replacingOccurrences(of: #"[ \t]+([,?.])"#, with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return output
    }

    private static func applySnippets(to text: String, snippets: [VoiceSnippet]) -> String {
        let entries = snippets.filter {
            !$0.cue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.content.isEmpty
        }.sorted { $0.cue.count > $1.cue.count }
        guard !entries.isEmpty else { return text }
        let alternatives = entries.map { NSRegularExpression.escapedPattern(for: $0.cue.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let expression = try? NSRegularExpression(
            pattern: "(?i)(?<![\\p{L}\\p{N}_])(?:\(alternatives.joined(separator: "|")))(?![\\p{L}\\p{N}_])"
        ) else { return text }
        let original = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: original.length))
        let result = NSMutableString(string: text)
        // Match the original once so expanded content remains literal.
        for match in matches.reversed() {
            let cue = original.substring(with: match.range)
            if let entry = entries.first(where: {
                $0.cue.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(cue) == .orderedSame
            }) {
                result.replaceCharacters(in: match.range, with: entry.content)
            }
        }
        return result as String
    }

    private static func replacePhrase(_ phrase: String, with replacement: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: phrase.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !escaped.isEmpty,
              let expression = try? NSRegularExpression(
                pattern: "(?i)(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
              ) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }
}
