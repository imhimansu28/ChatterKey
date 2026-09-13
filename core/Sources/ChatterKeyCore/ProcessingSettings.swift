import Foundation

// Platform settings expose only the values used by a processing attempt.
nonisolated package protocol ProcessingSettings: Sendable {
    var provider: AIProvider { get }
    var baseURL: String { get }
    var model: String { get }
    var systemPrompt: String { get }
    var costRates: CostRates { get }
    var smartPolish: Bool { get }
    var outputMode: OutputMode { get }
    var personalDictionary: [DictionaryEntry] { get }
    var voiceSnippets: [VoiceSnippet] { get }
    var spokenCommandsEnabled: Bool { get }
}
