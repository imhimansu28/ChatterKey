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

nonisolated struct ProviderSettings: Codable, Sendable {
    var provider: AIProvider = .openAI
    var baseURL = AIProvider.openAI.defaultBaseURL
    var transcriptionModel = AIProvider.openAI.defaultTranscriptionModel
    var polishModel = AIProvider.openAI.defaultPolishModel
    var smartPolish = true
    // Kept under the old storage name so existing settings migrate safely.
    // true now means Hindi/Hinglish should become polished English.
    var preserveHinglish = true
    var fastSinglePass = true

    static let storageKey = "provider-settings"

    init() {}

    private enum CodingKeys: String, CodingKey {
        case provider, baseURL, transcriptionModel, polishModel
        case smartPolish, preserveHinglish, fastSinglePass
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .openAI
        baseURL = try values.decodeIfPresent(String.self, forKey: .baseURL) ?? provider.defaultBaseURL
        transcriptionModel = try values.decodeIfPresent(String.self, forKey: .transcriptionModel) ?? provider.defaultTranscriptionModel
        polishModel = try values.decodeIfPresent(String.self, forKey: .polishModel) ?? provider.defaultPolishModel
        smartPolish = try values.decodeIfPresent(Bool.self, forKey: .smartPolish) ?? true
        preserveHinglish = try values.decodeIfPresent(Bool.self, forKey: .preserveHinglish) ?? true
        fastSinglePass = try values.decodeIfPresent(Bool.self, forKey: .fastSinglePass) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(provider, forKey: .provider)
        try values.encode(baseURL, forKey: .baseURL)
        try values.encode(transcriptionModel, forKey: .transcriptionModel)
        try values.encode(polishModel, forKey: .polishModel)
        try values.encode(smartPolish, forKey: .smartPolish)
        try values.encode(preserveHinglish, forKey: .preserveHinglish)
        try values.encode(fastSinglePass, forKey: .fastSinglePass)
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
