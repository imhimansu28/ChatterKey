import ChatterKeyCore
import Foundation

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

    var recordingInstructions: String {
        self == .function
            ? "Hold Fn to talk, or double-tap Fn for hands-free recording. Press Fn again to stop; Esc cancels."
            : "Hold \(title) to record, then release to process. Esc cancels."
    }
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

nonisolated struct ProviderSettings: ProcessingSettings, Codable, Sendable {
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

    static let defaultSystemPrompt = ProcessingPrompt.defaultSystemPrompt

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
