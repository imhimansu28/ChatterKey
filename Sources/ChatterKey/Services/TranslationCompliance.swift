import Foundation

nonisolated enum TranslationCompliance {
    static func containsUntranslatedHindi(_ text: String) -> Bool {
        if text.unicodeScalars.contains(where: { (0x0900...0x097F).contains(Int($0.value)) }) {
            return true
        }

        let originalWords = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let words = originalWords.map { $0.lowercased() }

        let decisiveMarkers: Set<String> = [
            "mujhe", "kyunki", "chahiye", "karo", "karna", "nahi", "lekin",
            "aapko", "humko", "kaise", "batao", "samajh", "raha", "rahi"
        ]
        if words.contains(where: decisiveMarkers.contains) { return true }

        let isolatedLowercaseMarkers: Set<String> = [
            "hai", "hain", "tha", "thi", "toh", "aur", "wala", "wali", "acha", "accha"
        ]
        return originalWords.contains { word in
            word == word.lowercased() && isolatedLowercaseMarkers.contains(word)
        }
    }
}
