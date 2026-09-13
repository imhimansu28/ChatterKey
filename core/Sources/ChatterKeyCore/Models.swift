import Foundation

nonisolated package enum AIProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case google
    case openAI
    case openRouter
    case custom

    package var id: String { rawValue }

    package static let availableConnections: [AIProvider] = [.google, .openRouter]
    package var supportsAudioRequests: Bool { Self.availableConnections.contains(self) }

    package var defaultModel: String {
        self == .google ? "gemini-3.5-flash-lite" : "google/gemini-3.5-flash-lite"
    }

    package func requestModelID(_ value: String) -> String {
        var model = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if self == .google {
            for prefix in ["google/", "models/"] where model.hasPrefix(prefix) {
                model = String(model.dropFirst(prefix.count))
            }
        }
        return model
    }

    package var title: String {
        switch self {
        case .google: "Google Direct"
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .custom: "Custom"
        }
    }

    package var defaultBaseURL: String {
        switch self {
        case .google: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openAI: "https://api.openai.com/v1"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .custom: ""
        }
    }
}

nonisolated package enum OutputMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case cleanSameLanguage
    case translateEnglish
    case professional
    case casual
    case concise
    case bulletPoints
    case technical
    case verbatim

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .cleanSameLanguage: "Clean Same Language"
        case .translateEnglish: "Translate to English"
        case .professional: "Professional"
        case .casual: "Casual"
        case .concise: "Concise"
        case .bulletPoints: "Bullet Points"
        case .technical: "Technical"
        case .verbatim: "Verbatim"
        }
    }

    package var shortTitle: String {
        switch self {
        case .cleanSameLanguage: "Clean"
        case .translateEnglish: "English"
        case .professional: "Professional"
        case .casual: "Casual"
        case .concise: "Concise"
        case .bulletPoints: "Bullets"
        case .technical: "Technical"
        case .verbatim: "Verbatim"
        }
    }

    package var instruction: String {
        switch self {
        case .cleanSameLanguage:
            "Keep the speaker's original language and natural code-switching. Clean grammar and punctuation without translating."
        case .translateEnglish:
            "Convert every Hindi, Hinglish, or other non-English fragment—including isolated conversational words—into fluent, idiomatic English. Keep and correct already-English content. Output English only; never retain Devanagari or Romanized Hindi except proper names, brands, quoted text, code, URLs, and filenames."
        case .professional:
            "Return polished professional English suitable for email or workplace communication. Preserve intent without sounding robotic."
        case .casual:
            "Return friendly, natural, conversational English. Keep it relaxed and human."
        case .concise:
            "Return concise natural English. Remove repetition and unnecessary words while preserving every important point."
        case .bulletPoints:
            "Return clear plain-text bullet points when there are multiple ideas or tasks. Translate non-English speech into English."
        case .technical:
            "Return precise technical English. Preserve code identifiers, commands, URLs, filenames, acronyms, and developer terminology."
        case .verbatim:
            "Transcribe as literally as practical in the original language. Add only essential punctuation and do not rewrite the speaker's style."
        }
    }
}

nonisolated package struct CostRates: Codable, Sendable {
    package var audioPerMillionTokens: Double
    package var inputPerMillionTokens: Double
    package var outputPerMillionTokens: Double

    // Gemini 3.5 Flash-Lite standard USD rates; editable for future models.
    package static let geminiFlashLite = CostRates(audioPerMillionTokens: 0.30, inputPerMillionTokens: 0.30, outputPerMillionTokens: 2.50)

    package static func migrationRates(for model: String) -> CostRates {
        // Known standard rates as of September 7, 2026. Update in Settings when pricing changes.
        switch AIProvider.google.requestModelID(model) {
        case "gemini-3.5-flash-lite": return .geminiFlashLite
        case "gemini-3.5-flash":
            return CostRates(audioPerMillionTokens: 3, inputPerMillionTokens: 1.50, outputPerMillionTokens: 9)
        case "gemini-3.8-flash", "gemini-3.7-flash", "gemini-3.6-flash":
            return CostRates(audioPerMillionTokens: 0.75, inputPerMillionTokens: 0.75, outputPerMillionTokens: 3.75)
        default:
            // Unknown model rates must be supplied by the user, not guessed from another model.
            return CostRates(audioPerMillionTokens: 0, inputPerMillionTokens: 0, outputPerMillionTokens: 0)
        }
    }

    package init(audioPerMillionTokens: Double, inputPerMillionTokens: Double, outputPerMillionTokens: Double) {
        self.audioPerMillionTokens = audioPerMillionTokens
        self.inputPerMillionTokens = inputPerMillionTokens
        self.outputPerMillionTokens = outputPerMillionTokens
    }
}

nonisolated package struct UsageRecord: Codable, Identifiable, Sendable {
    package var id = UUID()
    package let createdAt: Date
    package let provider: AIProvider
    package let model: String
    package let wordCount: Int
    package let audioDurationSeconds: Double
    package let estimatedCostUSD: Double
    package let suggestions: [String]

    package init(createdAt: Date, provider: AIProvider, model: String, wordCount: Int,
         audioDurationSeconds: Double, estimatedCostUSD: Double, suggestions: [String]) {
        self.createdAt = createdAt
        self.provider = provider
        self.model = model
        self.wordCount = wordCount
        self.audioDurationSeconds = audioDurationSeconds
        self.estimatedCostUSD = estimatedCostUSD
        self.suggestions = suggestions
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, provider, model, wordCount, audioDurationSeconds, estimatedCostUSD, suggestions
    }
    private enum LegacyKeys: String, CodingKey { case polishModel, transcriptionModel }

    package init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        provider = try values.decode(AIProvider.self, forKey: .provider)
        model = try values.decodeIfPresent(String.self, forKey: .model)
            ?? legacy.decodeIfPresent(String.self, forKey: .polishModel)
            ?? legacy.decodeIfPresent(String.self, forKey: .transcriptionModel) ?? "Unknown"
        wordCount = try values.decode(Int.self, forKey: .wordCount)
        audioDurationSeconds = try values.decode(Double.self, forKey: .audioDurationSeconds)
        estimatedCostUSD = try values.decode(Double.self, forKey: .estimatedCostUSD)
        suggestions = try values.decode([String].self, forKey: .suggestions)
    }
}

nonisolated package struct DictionaryEntry: Codable, Identifiable, Hashable, Sendable {
    package var id: UUID
    package var spoken: String
    package var replacement: String

    package init(id: UUID = UUID(), spoken: String, replacement: String) {
        self.id = id
        self.spoken = spoken
        self.replacement = replacement
    }
}

nonisolated package struct VoiceSnippet: Codable, Identifiable, Hashable, Sendable {
    package var id: UUID
    package var cue: String
    package var content: String

    package init(id: UUID = UUID(), cue: String, content: String) {
        self.id = id
        self.cue = cue
        self.content = content
    }
}

nonisolated package struct DictationHistoryItem: Codable, Identifiable, Sendable {
    package var id: UUID
    package let text: String
    package let createdAt: Date
    package let outputMode: OutputMode

    package init(id: UUID = UUID(), text: String, createdAt: Date, outputMode: OutputMode) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.outputMode = outputMode
    }
}

nonisolated package enum DictationPhase: Equatable, Sendable {
    case idle
    case listening
    case processing
    case reviewing
    case pasteSent
    case failed(String)

    package var isBusy: Bool {
        switch self {
        case .listening, .processing, .reviewing: true
        case .idle, .pasteSent, .failed: false
        }
    }
}
