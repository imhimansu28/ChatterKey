import Foundation

nonisolated struct ProviderClient: Sendable {
    let settings: ProviderSettings
    let apiKey: String

    func process(audioURL: URL, editing selectedText: String? = nil) async throws -> String {
        guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey }

        if let selectedText, !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let instruction = try await transcribe(audioURL: audioURL)
            return try await edit(selectedText, instruction: instruction)
        }

        let audio = try Data(contentsOf: audioURL)
        let output: String
        if settings.provider == .openRouter,
           settings.fastSinglePass,
           settings.smartPolish {
            output = try await processOpenRouterSinglePass(audio: audio)
        } else {
            let raw = try await transcribe(audioURL: audioURL)
            output = try await polish(raw)
        }
        return VoiceTextProcessor.process(output, settings: settings)
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey }
        guard let baseURL = URL(string: settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ProviderError.invalidBaseURL
        }
        let endpoint = baseURL.appendingPathComponent("audio/transcriptions")
        let audio = try Data(contentsOf: audioURL)

        if settings.provider == .openRouter {
            return try await transcribeOpenRouter(audio: audio, endpoint: endpoint)
        }
        return try await transcribeMultipart(audio: audio, endpoint: endpoint)
    }

    func polish(_ transcript: String) async throws -> String {
        guard settings.smartPolish, !settings.polishModel.isEmpty else { return transcript }
        return try await complete(system: processingPrompt, user: transcript)
    }

    private func complete(system: String, user: String) async throws -> String {
        guard let baseURL = URL(string: settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ProviderError.invalidBaseURL
        }
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if settings.provider == .openRouter {
            request.setValue("ChatterKey", forHTTPHeaderField: "X-OpenRouter-Title")
        }

        let body = ChatRequest(
            model: settings.polishModel,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user)
            ],
            temperature: 0.1
        )
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let output = decoded.choices.first?.message.content, !output.isEmpty else {
            throw ProviderError.invalidResponse
        }
        return sanitize(output)
    }

    func edit(_ selectedText: String, instruction: String) async throws -> String {
        guard !settings.polishModel.isEmpty else { throw ProviderError.invalidResponse }
        let dictionary = settings.personalDictionary
            .filter { !$0.spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "- \($0.spoken) → \($0.replacement)" }
            .joined(separator: "\n")
        let vocabulary = dictionary.isEmpty ? "" : """

        Preferred vocabulary and exact spellings:
        \(dictionary)
        """
        let system = """
        You edit selected text according to a spoken instruction.
        Preserve the original meaning unless the instruction explicitly requests a change.
        Never add unsupported facts. Preserve names, code, URLs, filenames, and technical terms.
        Return only the replacement text, without quotes, labels, explanations, or code fences.
        \(vocabulary)
        """
        let user = """
        SELECTED TEXT:
        \(selectedText)

        SPOKEN INSTRUCTION:
        \(instruction)
        """
        return try await complete(system: system, user: user)
    }

    func testConnection() async throws {
        guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey }
        guard let baseURL = URL(string: settings.baseURL) else { throw ProviderError.invalidBaseURL }
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    private func processOpenRouterSinglePass(audio: Data) async throws -> String {
        guard let baseURL = URL(string: settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ProviderError.invalidBaseURL
        }
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ChatterKey", forHTTPHeaderField: "X-OpenRouter-Title")

        let prompt = processingPrompt
        let body = AudioChatRequest(
            model: settings.polishModel,
            messages: [.init(role: "user", content: [
                .text(prompt),
                .audio(data: audio.base64EncodedString(), format: "wav")
            ])],
            temperature: 0,
            maxTokens: 700,
            provider: .init(sort: "latency")
        )
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let output = decoded.choices.first?.message.content, !output.isEmpty else {
            throw ProviderError.invalidResponse
        }
        return sanitize(output)
    }

    private func transcribeOpenRouter(audio: Data, endpoint: URL) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ChatterKey", forHTTPHeaderField: "X-OpenRouter-Title")
        let body = OpenRouterTranscriptionRequest(
            model: settings.transcriptionModel,
            inputAudio: .init(data: audio.base64EncodedString(), format: "wav")
        )
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(TranscriptionResponse.self, from: data).text
    }

    private func transcribeMultipart(audio: Data, endpoint: URL) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendFormField(name: "model", value: settings.transcriptionModel, boundary: boundary)
        body.appendFormField(
            name: "prompt",
            value: "Natural Indian Hinglish. Preserve Hindi-English code switching, names, product names and technical terms.",
            boundary: boundary
        )
        body.appendFile(name: "file", filename: "dictation.wav", mimeType: "audio/wav", data: audio, boundary: boundary)
        body.append("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(TranscriptionResponse.self, from: data).text
    }

    private var processingPrompt: String {
        let dictionary = settings.personalDictionary
            .filter { !$0.spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "- \($0.spoken) → \($0.replacement)" }
            .joined(separator: "\n")
        let vocabulary = dictionary.isEmpty ? "" : """

        Preferred vocabulary and exact spellings:
        \(dictionary)
        """
        let snippetCues = settings.voiceSnippets
            .map(\.cue)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "- \($0)" }
            .joined(separator: "\n")
        let snippets = snippetCues.isEmpty ? "" : """

        Voice snippet cues: preserve these cue phrases exactly when spoken so the local app can expand them after transcription:
        \(snippetCues)
        """
        let commands = settings.spokenCommandsEnabled ? """

        Interpret spoken formatting commands such as new line, new paragraph, bullet point, comma, full stop, and question mark. Apply the formatting and do not output the command words literally.
        """ : ""
        return """
        You are the final writing layer for voice dictation.
        \(settings.outputMode.instruction)
        Preserve the exact intent, names, code, URLs, filenames, and technical terms.
        Remove filler words, repetition, and abandoned phrases unless Verbatim mode requires them.
        Respect the speaker's final self-correction. Never add facts or new ideas.
        Return plain text only. Never use code fences, surrounding quotes, labels, or a preface.
        \(vocabulary)
        \(snippets)
        \(commands)
        """
    }

    private func sanitize(_ value: String) -> String {
        var output = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.hasPrefix("```") {
            let lines = output.components(separatedBy: .newlines)
            output = lines.dropFirst().drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                .joined(separator: "\n")
        }
        output = output.replacingOccurrences(of: "```", with: "")
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.count >= 2,
           (output.hasPrefix("\"") && output.hasSuffix("\"") || output.hasPrefix("“") && output.hasSuffix("”")) {
            output.removeFirst()
            output.removeLast()
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw ProviderError.api(apiError?.error.message ?? "Provider error (HTTP \(http.statusCode))")
        }
    }
}

private nonisolated struct OpenRouterTranscriptionRequest: Encodable {
    struct InputAudio: Encodable { let data: String; let format: String }
    let model: String
    let inputAudio: InputAudio

    enum CodingKeys: String, CodingKey {
        case model
        case inputAudio = "input_audio"
    }
}

private nonisolated struct AudioChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: [Content]
    }

    enum Content: Encodable {
        case text(String)
        case audio(data: String, format: String)

        enum CodingKeys: String, CodingKey { case type, text, inputAudio = "input_audio" }
        struct InputAudio: Encodable { let data: String; let format: String }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try values.encode("text", forKey: .type)
                try values.encode(text, forKey: .text)
            case .audio(let data, let format):
                try values.encode("input_audio", forKey: .type)
                try values.encode(InputAudio(data: data, format: format), forKey: .inputAudio)
            }
        }
    }

    struct ProviderPreference: Encodable { let sort: String }
    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    let provider: ProviderPreference

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, provider
        case maxTokens = "max_tokens"
    }
}

private nonisolated struct TranscriptionResponse: Decodable { let text: String }

private nonisolated struct ChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let messages: [Message]
    let temperature: Double
}

private nonisolated struct ChatResponse: Decodable {
    struct Choice: Decodable { let message: Message }
    struct Message: Decodable { let content: String }
    let choices: [Choice]
}

private nonisolated struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

nonisolated enum ProviderError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL
    case invalidResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Settings mein provider API key add karein."
        case .invalidBaseURL: "The provider base URL is invalid."
        case .invalidResponse: "The provider returned an invalid response."
        case .api(let message): message
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func appendFile(name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        append("\r\n")
    }
}
