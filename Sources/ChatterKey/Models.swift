import Foundation

nonisolated enum AIProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case google
    case openAI
    case openRouter
    case custom

    var id: String { rawValue }

    static let availableConnections: [AIProvider] = [.google, .openRouter]
    var supportsAudioRequests: Bool { Self.availableConnections.contains(self) }

    var defaultModel: String {
        self == .google ? "gemini-3.5-flash-lite" : "google/gemini-3.5-flash-lite"
    }

    func requestModelID(_ value: String) -> String {
        var model = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if self == .google {
            for prefix in ["google/", "models/"] where model.hasPrefix(prefix) {
                model = String(model.dropFirst(prefix.count))
            }
        }
        return model
    }

    var title: String {
        switch self {
        case .google: "Google Direct"
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .custom: "Custom"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .google: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openAI: "https://api.openai.com/v1"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .custom: ""
        }
    }
}

nonisolated enum OutputMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case cleanSameLanguage
    case translateEnglish
    case professional
    case casual
    case concise
    case bulletPoints
    case technical
    case verbatim

    var id: String { rawValue }

    var title: String {
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

    var shortTitle: String {
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

    var instruction: String {
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

nonisolated enum HotkeyShortcut: String, CaseIterable, Codable, Identifiable, Sendable {
    case function
    case rightOption
    case optionSpace
    case commandShiftSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .function: "Fn"
        case .rightOption: "Right Option"
        case .optionSpace: "Option + Space"
        case .commandShiftSpace: "Command + Shift + Space"
        }
    }

    var symbols: String {
        switch self {
        case .function: "Fn"
        case .rightOption: "⌥ (Right)"
        case .optionSpace: "⌥ Space"
        case .commandShiftSpace: "⌘ ⇧ Space"
        }
    }
}

nonisolated struct CostRates: Codable, Sendable {
    var audioPerMillionTokens: Double
    var inputPerMillionTokens: Double
    var outputPerMillionTokens: Double

    // Gemini 3.5 Flash-Lite standard USD rates; editable for future models.
    static let geminiFlashLite = CostRates(audioPerMillionTokens: 0.30, inputPerMillionTokens: 0.30, outputPerMillionTokens: 2.50)

    static func migrationRates(for model: String) -> CostRates {
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
}

nonisolated struct UsageRecord: Codable, Identifiable, Sendable {
    var id = UUID()
    let createdAt: Date
    let provider: AIProvider
    let model: String
    let wordCount: Int
    let audioDurationSeconds: Double
    let estimatedCostUSD: Double
    let suggestions: [String]

    init(createdAt: Date, provider: AIProvider, model: String, wordCount: Int,
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

    init(from decoder: Decoder) throws {
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

nonisolated struct DictionaryEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var spoken: String
    var replacement: String
}

nonisolated struct VoiceSnippet: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var cue: String
    var content: String
}

nonisolated struct DictationHistoryItem: Codable, Identifiable, Sendable {
    var id = UUID()
    let text: String
    let createdAt: Date
    let outputMode: OutputMode
}

nonisolated enum DiagnosticState: String, Sendable {
    case checking
    case passed
    case failed
}

nonisolated struct DiagnosticItem: Identifiable, Sendable {
    let id: String
    let title: String
    let state: DiagnosticState
    let detail: String
}

nonisolated struct AudioModelConfiguration: Codable, Sendable {
    var model: String
    var costRates: CostRates
}

nonisolated struct ProviderSettings: Codable, Sendable {
    var provider: AIProvider = .google
    var baseURL = AIProvider.google.defaultBaseURL
    static let defaultModel = AIProvider.google.defaultModel
    var model = Self.defaultModel
    var systemPrompt = Self.defaultSystemPrompt
    var costRates = CostRates.geminiFlashLite
    private var connectionModels: [String: AudioModelConfiguration] = [:]
    var smartPolish = true
    var outputMode: OutputMode = .translateEnglish
    var hotkeyShortcut: HotkeyShortcut = .function
    var personalDictionary: [DictionaryEntry] = []
    var voiceSnippets: [VoiceSnippet] = []
    var spokenCommandsEnabled = true
    var liveTranscriptionEnabled = true
    var historyEnabled = false
    var historyRetentionDays = 7

    static let storageKey = "provider-settings"
    private static let starterContentMigrationKey = "starter-content-v1-installed"

    static let defaultSystemPrompt = """
    You are the final writing layer for voice dictation.
    Preserve the speaker's meaning while making the result clear, natural, and ready to use.
    Follow the selected writing mode without adding unsupported facts or ideas.
    """

    static let starterVocabulary = [
        DictionaryEntry(spoken: "chat gpt", replacement: "ChatGPT"),
        DictionaryEntry(spoken: "open ai", replacement: "OpenAI"),
        DictionaryEntry(spoken: "open router", replacement: "OpenRouter"),
        DictionaryEntry(spoken: "github", replacement: "GitHub"),
        DictionaryEntry(spoken: "mac os", replacement: "macOS"),
        DictionaryEntry(spoken: "javascript", replacement: "JavaScript"),
        DictionaryEntry(spoken: "typescript", replacement: "TypeScript")
    ]

    static let starterSnippets = [
        VoiceSnippet(
            cue: "insert quick thanks",
            content: "Thanks! I’ll get back to you shortly."
        ),
        VoiceSnippet(
            cue: "insert review request",
            content: "Please review this and let me know if you have any feedback."
        ),
        VoiceSnippet(
            cue: "insert meeting follow up",
            content: "Thanks for your time today. Here’s a quick summary of the next steps:"
        )
    ]

    init() {
        personalDictionary = Self.starterVocabulary
        voiceSnippets = Self.starterSnippets
    }

    mutating func selectProvider(_ selected: AIProvider) {
        guard selected.supportsAudioRequests, selected != provider else { return }
        connectionModels[provider.rawValue] = AudioModelConfiguration(model: model, costRates: costRates)
        provider = selected
        baseURL = selected.defaultBaseURL
        let saved = connectionModels[selected.rawValue]
        model = saved?.model ?? selected.defaultModel
        costRates = saved?.costRates ?? .geminiFlashLite
    }

    mutating func validate() throws {
        guard provider.supportsAudioRequests else { throw ProviderError.unsupportedProvider }
        model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !provider.requestModelID(model).isEmpty else { throw ProviderError.missingProcessingModel }
        let rates = [costRates.audioPerMillionTokens, costRates.inputPerMillionTokens, costRates.outputPerMillionTokens]
        guard rates.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw ProviderError.invalidCostRates }
        baseURL = provider.defaultBaseURL
    }

    private enum CodingKeys: String, CodingKey {
        case provider, baseURL, model, polishModel, systemPrompt, costRates, connectionModels
        case smartPolish, preserveHinglish
        case outputMode, hotkeyShortcut, personalDictionary
        case voiceSnippets, spokenCommandsEnabled, liveTranscriptionEnabled
        case historyEnabled, historyRetentionDays
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Retain working connections. Unsupported legacy providers keep the v4.5 migration path.
        // No keys are read or copied during decoding or connection switching.
        let previousProvider = try values.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .google
        provider = previousProvider.supportsAudioRequests ? previousProvider : .openRouter
        baseURL = provider.defaultBaseURL
        connectionModels = try values.decodeIfPresent([String: AudioModelConfiguration].self, forKey: .connectionModels) ?? [:]
        if let savedModel = try values.decodeIfPresent(String.self, forKey: .model) {
            model = savedModel
        } else {
            let previousModel = try values.decodeIfPresent(String.self, forKey: .polishModel)
            if previousProvider == .openRouter, let previousModel, previousModel.hasPrefix("google/gemini-") {
                model = previousModel
            } else {
                model = provider.defaultModel
            }
        }
        systemPrompt = try values.decodeIfPresent(String.self, forKey: .systemPrompt) ?? Self.defaultSystemPrompt
        costRates = (try? values.decode(CostRates.self, forKey: .costRates)) ?? .migrationRates(for: model)
        smartPolish = try values.decodeIfPresent(Bool.self, forKey: .smartPolish) ?? true
        let legacyTranslate = try values.decodeIfPresent(Bool.self, forKey: .preserveHinglish) ?? true
        outputMode = try values.decodeIfPresent(OutputMode.self, forKey: .outputMode)
            ?? (legacyTranslate ? .translateEnglish : .cleanSameLanguage)
        hotkeyShortcut = try values.decodeIfPresent(HotkeyShortcut.self, forKey: .hotkeyShortcut) ?? .function
        personalDictionary = try values.decodeIfPresent([DictionaryEntry].self, forKey: .personalDictionary) ?? []
        voiceSnippets = try values.decodeIfPresent([VoiceSnippet].self, forKey: .voiceSnippets) ?? []
        spokenCommandsEnabled = try values.decodeIfPresent(Bool.self, forKey: .spokenCommandsEnabled) ?? true
        liveTranscriptionEnabled = try values.decodeIfPresent(Bool.self, forKey: .liveTranscriptionEnabled) ?? true
        historyEnabled = try values.decodeIfPresent(Bool.self, forKey: .historyEnabled) ?? false
        historyRetentionDays = try values.decodeIfPresent(Int.self, forKey: .historyRetentionDays) ?? 7
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(provider, forKey: .provider)
        try values.encode(baseURL, forKey: .baseURL)
        try values.encode(model, forKey: .model)
        try values.encode(systemPrompt, forKey: .systemPrompt)
        try values.encode(costRates, forKey: .costRates)
        try values.encode(connectionModels, forKey: .connectionModels)
        try values.encode(smartPolish, forKey: .smartPolish)
        try values.encode(outputMode == .translateEnglish, forKey: .preserveHinglish)
        try values.encode(outputMode, forKey: .outputMode)
        try values.encode(hotkeyShortcut, forKey: .hotkeyShortcut)
        try values.encode(personalDictionary, forKey: .personalDictionary)
        try values.encode(voiceSnippets, forKey: .voiceSnippets)
        try values.encode(spokenCommandsEnabled, forKey: .spokenCommandsEnabled)
        try values.encode(liveTranscriptionEnabled, forKey: .liveTranscriptionEnabled)
        try values.encode(historyEnabled, forKey: .historyEnabled)
        try values.encode(historyRetentionDays, forKey: .historyRetentionDays)
    }

    static func load(defaults: UserDefaults = .standard) -> ProviderSettings {
        var value: ProviderSettings
        if let data = defaults.data(forKey: storageKey) {
            // Preserve unreadable settings for recovery instead of overwriting them.
            guard let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return ProviderSettings() }
            value = decoded
        } else {
            value = ProviderSettings()
        }

        if !defaults.bool(forKey: starterContentMigrationKey) {
            value.addStarterContent()
            defaults.set(true, forKey: starterContentMigrationKey)
        }
        value.save(defaults: defaults) // Persist the single-model migration, including removal of obsolete keys.
        return value
    }

    private mutating func addStarterContent() {
        let existingWords = Set(personalDictionary.map { $0.spoken.lowercased() })
        personalDictionary.append(contentsOf: Self.starterVocabulary.filter {
            !existingWords.contains($0.spoken.lowercased())
        })

        let existingCues = Set(voiceSnippets.map { $0.cue.lowercased() })
        voiceSnippets.append(contentsOf: Self.starterSnippets.filter {
            !existingCues.contains($0.cue.lowercased())
        })
    }

    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

nonisolated enum DictationPhase: Equatable, Sendable {
    case idle
    case listening
    case processing
    case pasteSent
    case failed(String)
}
