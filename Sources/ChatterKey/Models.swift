import Foundation

nonisolated enum AIProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAI
    case openRouter
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .custom: "Custom"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .custom: ""
        }
    }

    var defaultTranscriptionModel: String {
        switch self {
        case .openAI: "gpt-4o-mini-transcribe"
        case .openRouter: "openai/whisper-large-v3"
        case .custom: ""
        }
    }

    var defaultPolishModel: String {
        switch self {
        case .openAI: "gpt-4.1-mini"
        case .openRouter: "google/gemini-3.5-flash-lite"
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
            "Translate all Hindi, Hinglish, or other non-English speech into fluent natural English. Never return Devanagari or Roman Hindi."
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

nonisolated struct ProviderSettings: Codable, Sendable {
    var provider: AIProvider = .openAI
    var baseURL = AIProvider.openAI.defaultBaseURL
    var transcriptionModel = AIProvider.openAI.defaultTranscriptionModel
    var polishModel = AIProvider.openAI.defaultPolishModel
    var smartPolish = true
    var fastSinglePass = true
    var outputMode: OutputMode = .translateEnglish
    var hotkeyShortcut: HotkeyShortcut = .function
    var personalDictionary: [DictionaryEntry] = []
    var voiceSnippets: [VoiceSnippet] = []
    var spokenCommandsEnabled = true
    var liveTranscriptionEnabled = true
    var historyEnabled = false
    var historyRetentionDays = 7

    static let storageKey = "provider-settings"

    init() {}

    private enum CodingKeys: String, CodingKey {
        case provider, baseURL, transcriptionModel, polishModel
        case smartPolish, preserveHinglish, fastSinglePass
        case outputMode, hotkeyShortcut, personalDictionary
        case voiceSnippets, spokenCommandsEnabled, liveTranscriptionEnabled
        case historyEnabled, historyRetentionDays
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .openAI
        baseURL = try values.decodeIfPresent(String.self, forKey: .baseURL) ?? provider.defaultBaseURL
        transcriptionModel = try values.decodeIfPresent(String.self, forKey: .transcriptionModel) ?? provider.defaultTranscriptionModel
        polishModel = try values.decodeIfPresent(String.self, forKey: .polishModel) ?? provider.defaultPolishModel
        smartPolish = try values.decodeIfPresent(Bool.self, forKey: .smartPolish) ?? true
        fastSinglePass = try values.decodeIfPresent(Bool.self, forKey: .fastSinglePass) ?? true
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
        try values.encode(transcriptionModel, forKey: .transcriptionModel)
        try values.encode(polishModel, forKey: .polishModel)
        try values.encode(smartPolish, forKey: .smartPolish)
        try values.encode(fastSinglePass, forKey: .fastSinglePass)
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

    static func load() -> ProviderSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return ProviderSettings()
        }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

nonisolated enum DictationPhase: Equatable, Sendable {
    case idle
    case listening
    case processing
    case inserted
    case failed(String)
}
