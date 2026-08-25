import Foundation

nonisolated enum UsageAnalytics {
    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    static func estimatedCost(
        durationSeconds: Double,
        spokenText: String,
        finalText: String,
        settings: ProviderSettings
    ) -> Double {
        let minutes = max(durationSeconds, 0) / 60
        let transcriptionCost = minutes * settings.costRates.transcriptionPerMinute
        guard settings.smartPolish, !settings.polishModel.isEmpty else { return transcriptionCost }
        let promptTokens = Double(wordCount(spokenText) + wordCount(ProviderClient(settings: settings, apiKey: "").effectiveProcessingPrompt)) * 1.35
        let outputTokens = Double(wordCount(finalText)) * 1.35
        return transcriptionCost
            + promptTokens / 1_000_000 * settings.costRates.inputPerMillionTokens
            + outputTokens / 1_000_000 * settings.costRates.outputPerMillionTokens
    }

    static func suggestions(for text: String) -> [String] {
        let words = normalizedWords(text)
        guard words.count >= 5 else { return [] }
        var results: [String] = []

        let fillerPhrases = ["basically", "actually", "literally", "just", "like", "you know", "i mean", "matlab", "toh"]
        for phrase in fillerPhrases {
            let count = phraseCount(phrase, in: words)
            if count >= 2 {
                results.append("You used “\(phrase)” \(count) times. Try a short pause instead of repeating it.")
            }
        }

        let repeated = repeatedPhrase(in: words)
        if let repeated, results.count < 3 {
            results.append("“\(repeated.phrase)” appeared \(repeated.count) times. State it once, then continue with the next point.")
        }

        let punctuationCount = text.filter { ".?!".contains($0) }.count
        if words.count >= 55, punctuationCount <= 1, results.count < 3 {
            results.append("This was a long thought. Pause between ideas to produce shorter, clearer sentences.")
        }

        if results.isEmpty {
            results.append("Your speech was clear and direct. Keep using short pauses between important ideas.")
        }
        return Array(results.prefix(3))
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func phraseCount(_ phrase: String, in words: [String]) -> Int {
        let target = phrase.split(separator: " ").map(String.init)
        guard words.count >= target.count else { return 0 }
        return (0...(words.count - target.count)).reduce(0) { count, index in
            count + (Array(words[index..<(index + target.count)]) == target ? 1 : 0)
        }
    }

    private static func repeatedPhrase(in words: [String]) -> (phrase: String, count: Int)? {
        guard words.count >= 6 else { return nil }
        let ignored = Set(["the", "and", "that", "this", "with", "have", "will", "your", "you", "for", "but", "are", "was", "hai", "ke", "ki", "ka"])
        var counts: [String: Int] = [:]
        for index in 0..<(words.count - 1) {
            let pair = "\(words[index]) \(words[index + 1])"
            guard !ignored.contains(words[index]), !ignored.contains(words[index + 1]) else { continue }
            counts[pair, default: 0] += 1
        }
        guard let match = counts.max(by: { $0.value < $1.value }), match.value >= 2 else { return nil }
        return (match.key, match.value)
    }
}
