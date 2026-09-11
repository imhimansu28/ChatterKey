#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/ModelHarness.swift" <<'SWIFT'
import Foundation

@main
struct ModelHarness {
    static func main() async throws {
        let defaults = ProviderSettings()
        precondition(defaults.personalDictionary.contains { $0.replacement == "ChatGPT" })
        precondition(defaults.voiceSnippets.contains { $0.cue == "insert quick thanks" })

        var settings = ProviderSettings()
        settings.outputMode = .technical
        settings.hotkeyShortcut = .optionSpace
        settings.historyEnabled = true
        settings.historyRetentionDays = 30
        settings.personalDictionary = [DictionaryEntry(spoken: "chatter key", replacement: "ChatterKey")]
        settings.voiceSnippets = [VoiceSnippet(cue: "my email", content: "hello@example.com")]
        settings.spokenCommandsEnabled = false
        settings.liveTranscriptionEnabled = false

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ProviderSettings.self, from: data)
        precondition(decoded.outputMode == .technical)
        precondition(decoded.hotkeyShortcut == .optionSpace)
        precondition(decoded.historyEnabled)
        precondition(decoded.historyRetentionDays == 30)
        precondition(decoded.personalDictionary.first?.replacement == "ChatterKey")
        precondition(decoded.voiceSnippets.first?.content == "hello@example.com")
        precondition(!decoded.spokenCommandsEnabled)
        precondition(!decoded.liveTranscriptionEnabled)

        let legacy = Data(#"{"provider":"openAI","smartPolish":true,"preserveHinglish":true}"#.utf8)
        let migrated = try JSONDecoder().decode(ProviderSettings.self, from: legacy)
        precondition(migrated.outputMode == .translateEnglish)
        precondition(migrated.spokenCommandsEnabled)
        precondition(migrated.liveTranscriptionEnabled)
        precondition(migrated.voiceSnippets.isEmpty)

        var processorSettings = ProviderSettings()
        processorSettings.voiceSnippets = [VoiceSnippet(cue: "my email", content: "hello@example.com")]
        let processed = VoiceTextProcessor.process(
            "Send it to my email new paragraph bullet point done question mark",
            settings: processorSettings
        )
        precondition(processed.contains("hello@example.com"))
        precondition(processed.contains("\n\n• done?"))

        for mode in OutputMode.allCases {
            precondition(!mode.title.isEmpty)
            precondition(mode.instruction.count > 20)
        }

        var openAI = ProviderSettings()
        openAI.provider = .openAI
        openAI.baseURL = "https://attacker.example/v1"
        let pinnedOpenAIURL = try ProviderEndpointPolicy.baseURL(for: openAI)
        precondition(pinnedOpenAIURL.host == "api.openai.com")

        var custom = ProviderSettings()
        custom.provider = .custom
        custom.baseURL = "https://trusted.example/v1/"
        let secureCustomURL = try ProviderEndpointPolicy.baseURL(for: custom)
        precondition(secureCustomURL.absoluteString == "https://trusted.example/v1")
        custom.baseURL = "http://localhost:8080/v1"
        let localCustomURL = try ProviderEndpointPolicy.baseURL(for: custom)
        precondition(localCustomURL.host == "localhost")
        custom.baseURL = "http://provider.example/v1"
        do {
            _ = try ProviderEndpointPolicy.baseURL(for: custom)
            preconditionFailure("Remote HTTP provider should be rejected")
        } catch ProviderEndpointError.insecureURL {
            // Expected.
        }

        precondition(defaults.provider == .google)
        precondition(defaults.model == "gemini-3.5-flash-lite")
        precondition(migrated.provider == .openRouter)
        precondition(migrated.model == AIProvider.openRouter.defaultModel)
        precondition(decoded.model == defaults.model)
        let encodedSettings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(encodedSettings["transcriptionModel"] == nil)
        precondition(encodedSettings["polishModel"] == nil)
        precondition(encodedSettings["fastSinglePass"] == nil)

        let oldRouter = Data(#"{"provider":"openRouter","polishModel":"google/gemini-3.8-flash","transcriptionModel":"openai/whisper-large-v3","fastSinglePass":false,"costRates":{"transcriptionPerMinute":0.003,"inputPerMillionTokens":0.1,"outputPerMillionTokens":0.4}}"#.utf8)
        let migratedRouter = try JSONDecoder().decode(ProviderSettings.self, from: oldRouter)
        precondition(migratedRouter.model == "google/gemini-3.8-flash")
        precondition(migratedRouter.costRates.audioPerMillionTokens == 0.75)
        let oldTextModel = Data(#"{"provider":"openRouter","polishModel":"openai/gpt-oss-120b"}"#.utf8)
        let migratedTextModel = try JSONDecoder().decode(ProviderSettings.self, from: oldTextModel)
        precondition(migratedTextModel.model == AIProvider.openRouter.defaultModel)
        let oldCustom = Data(#"{"provider":"custom","baseURL":"https://custom.example","polishModel":"google/gemini-3.5-flash-lite"}"#.utf8)
        let migratedCustom = try JSONDecoder().decode(ProviderSettings.self, from: oldCustom)
        precondition(migratedCustom.provider == .openRouter)
        precondition(migratedCustom.baseURL == AIProvider.openRouter.defaultBaseURL)

        var future = defaults
        future.model = "google/gemini-future-audio"
        future.costRates = CostRates(audioPerMillionTokens: 1, inputPerMillionTokens: 2, outputPerMillionTokens: 3)
        let futureRoundTrip = try JSONDecoder().decode(ProviderSettings.self, from: JSONEncoder().encode(future))
        precondition(futureRoundTrip.model == future.model)
        precondition(futureRoundTrip.costRates.audioPerMillionTokens == 1)

        let oldUsage = Data(#"{"id":"12345678-1234-1234-1234-123456789012","createdAt":0,"provider":"openAI","transcriptionModel":"gpt-4o-mini-transcribe","polishModel":"gpt-4.1-mini","wordCount":12,"audioDurationSeconds":5,"estimatedCostUSD":0.1,"suggestions":[]}"#.utf8)
        let migratedUsage = try JSONDecoder().decode(UsageRecord.self, from: oldUsage)
        precondition(migratedUsage.model == "gpt-4.1-mini")
        precondition(migratedUsage.estimatedCostUSD == 0.1)
        let usageData = try JSONEncoder().encode(migratedUsage)
        let usageJSON = try JSONSerialization.jsonObject(with: usageData) as! [String: Any]
        precondition(usageJSON["model"] as? String == "gpt-4.1-mini")
        precondition(usageJSON["polishModel"] == nil)
        _ = try JSONDecoder().decode(UsageRecord.self, from: usageData)

        // Existing v4.5 OpenRouter settings and historical model/cost preferences survive upgrades.
        var router = ProviderSettings()
        router.selectProvider(.openRouter)
        router.model = "google/gemini-3.8-flash"
        router.costRates = CostRates(audioPerMillionTokens: 4, inputPerMillionTokens: 5, outputPerMillionTokens: 6)
        let oldSingleModelData = try JSONEncoder().encode(router)
        let oldSingleModel = try JSONDecoder().decode(ProviderSettings.self, from: oldSingleModelData)
        precondition(oldSingleModel.provider == .openRouter)
        precondition(oldSingleModel.model == router.model)
        precondition(oldSingleModel.costRates.audioPerMillionTokens == 4)
        router.selectProvider(.google)
        precondition(router.model == "gemini-3.5-flash-lite")
        precondition(router.baseURL == AIProvider.google.defaultBaseURL)
        router.model = "gemini-3.8-flash"
        router.costRates = CostRates(audioPerMillionTokens: 1, inputPerMillionTokens: 2, outputPerMillionTokens: 3)
        var switched = try JSONDecoder().decode(ProviderSettings.self, from: JSONEncoder().encode(router))
        precondition(switched.provider == .google)
        precondition(switched.model == "gemini-3.8-flash")
        switched.selectProvider(.openRouter)
        precondition(switched.model == "google/gemini-3.8-flash")
        precondition(switched.costRates.inputPerMillionTokens == 5)
        switched.selectProvider(.google)
        precondition(switched.model == "gemini-3.8-flash")
        precondition(switched.costRates.inputPerMillionTokens == 2)
        precondition(switched.personalDictionary.count == router.personalDictionary.count)
        precondition(AIProvider.google.rawValue != AIProvider.openRouter.rawValue)
        precondition(CostRates.migrationRates(for: "gemini-3.5-flash-lite").audioPerMillionTokens == 0.30)
        precondition(CostRates.migrationRates(for: "google/gemini-3.5-flash-lite").outputPerMillionTokens == 2.50)
        precondition(AIProvider.google.requestModelID(" google/gemini-3.5-flash-lite ") == "gemini-3.5-flash-lite")
        precondition(AIProvider.google.requestModelID("models/gemini-3.5-flash-lite") == "gemini-3.5-flash-lite")

        let audio = Data("mock WAV bytes".utf8)
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try audio.write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        for connection in AIProvider.availableConnections {
            var defaults = ProviderSettings()
            defaults.selectProvider(connection)
            // Every writing mode, with and without cleanup, must send exactly one audio request.
            for mode in OutputMode.allCases {
                for cleanup in [true, false] {
                    var config = defaults
                    config.outputMode = mode
                    config.smartPolish = cleanup
                    config.baseURL = "https://attacker.example/v1"
                    let mock = MockTransport(body: reply("Final text"))
                    let client = ProviderClient(settings: config, apiKey: "test-credential", transport: { try await mock.send($0) })
                    let output = try await client.process(audioURL: audioURL)
                    precondition(output == "Final text")
                    let requests = await mock.requests
                    precondition(requests.count == 1)
                    let request = requests[0]
                    precondition(request.url?.absoluteString == connection.defaultBaseURL + "/chat/completions")
                    precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-credential")
                    precondition(request.httpMethod == "POST")
                    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                    precondition(body["model"] as? String == defaults.model)
                    precondition(body["temperature"] == nil)
                    precondition((body["max_tokens"] as? Int ?? 0) > 700)
                    if connection == .google {
                        precondition(body["provider"] == nil)
                        precondition(body["reasoning"] == nil)
                        precondition(body["reasoning_effort"] as? String == "low")
                        precondition(request.value(forHTTPHeaderField: "X-OpenRouter-Title") == nil)
                    } else {
                        precondition((body["provider"] as? [String: Any])?["allow_fallbacks"] as? Bool == false)
                        precondition((body["reasoning"] as? [String: Any])?["effort"] as? String == "low")
                        precondition(body["reasoning_effort"] == nil)
                        precondition(request.value(forHTTPHeaderField: "X-OpenRouter-Title") == "ChatterKey")
                    }
                    let messages = body["messages"] as! [[String: Any]]
                    precondition(messages.count == 2)
                    precondition(messages[0]["role"] as? String == "system")
                    let prompt = (messages[0]["content"] as! [[String: Any]])[0]["text"] as! String
                    precondition(prompt.contains(mode.instruction))
                    precondition(prompt.contains("chat gpt"))
                    let content = messages[1]["content"] as! [[String: Any]]
                    precondition(content.count == 1)
                    precondition(content[0]["type"] as? String == "input_audio")
                    let input = content[0]["input_audio"] as! [String: Any]
                    precondition(input["data"] as? String == audio.base64EncodedString())
                    precondition(input["format"] as? String == "wav")
                }
            }

            let connectionMock = MockTransport(body: Data(#"{"data":[]}"#.utf8))
            let connectionClient = ProviderClient(settings: defaults, apiKey: "test-credential", transport: { try await connectionMock.send($0) })
            try await connectionClient.testConnection()
            let connectionRequests = await connectionMock.requests
            precondition(connectionRequests.count == 1)
            precondition(connectionRequests[0].url?.absoluteString == connection.defaultBaseURL + "/models")
            precondition(connectionRequests[0].httpMethod == "GET")
            precondition(connectionRequests[0].httpBody == nil)
            precondition(connectionRequests[0].value(forHTTPHeaderField: "Authorization") == "Bearer test-credential")

            let selected = "Original document with a URL and code."
            let editMock = MockTransport(body: reply("new line insert quick thanks"))
            let editor = ProviderClient(settings: defaults, apiKey: "test-credential", transport: { try await editMock.send($0) })
            let edited = try await editor.process(audioURL: audioURL, editing: selected)
            precondition(edited == "new line insert quick thanks") // No local snippet/command expansion in edits.
            let editRequests = await editMock.requests
            precondition(editRequests.count == 1)
            let editBody = try JSONSerialization.jsonObject(with: editRequests[0].httpBody!) as! [String: Any]
            let editMessages = editBody["messages"] as! [[String: Any]]
            let editContent = editMessages[1]["content"] as! [[String: Any]]
            precondition(editContent.count == 2)
            precondition((editContent[0]["text"] as? String)?.contains(selected) == true)
            precondition(editContent[1]["type"] as? String == "input_audio")
            precondition(editor.processingPrompt(editing: selected).contains("spoken instruction"))
            precondition(!editor.processingPrompt(editing: selected).contains(defaults.outputMode.instruction))
            precondition(editor.processingPrompt(editing: "  ") == editor.effectiveProcessingPrompt)

            var verbatim = defaults
            verbatim.outputMode = .verbatim
            precondition(VoiceTextProcessor.process("new line insert quick thanks", settings: verbatim) == "new line insert quick thanks")

            // Imperfect English must never trigger a hidden repair request.
            let hindiMock = MockTransport(body: reply("यह report ready hai."))
            let hindiClient = ProviderClient(settings: defaults, apiKey: "test-credential", transport: { try await hindiMock.send($0) })
            _ = try await hindiClient.process(audioURL: audioURL)
            let hindiCount = await hindiMock.requests.count
            precondition(hindiCount == 1)

            // Provider/network failures, blocked and truncated results never retry or fall back.
            for mock in [
                MockTransport(body: Data(#"{"error":{"message":"Unavailable"}}"#.utf8), status: 503),
                MockTransport(body: Data(#"{"error":{"code":401,"message":"Invalid key","status":"UNAUTHENTICATED"}}"#.utf8), status: 401),
                MockTransport(body: Data(#"{"error":{"code":429,"message":"Quota exhausted","status":"RESOURCE_EXHAUSTED"}}"#.utf8), status: 429),
                MockTransport(body: Data(), errorCode: .timedOut),
                MockTransport(body: Data(), errorCode: .networkConnectionLost),
                MockTransport(body: Data("malformed".utf8)),
                MockTransport(body: reply("   ")),
                MockTransport(body: reply("partial text", finishReason: "length")),
                MockTransport(body: reply("blocked", finishReason: "content_filter")),
                MockTransport(body: Data(#"{"choices":[{"message":{"content":null}}]}"#.utf8))
            ] {
                let client = ProviderClient(settings: defaults, apiKey: "test-credential", transport: { try await mock.send($0) })
                do {
                    _ = try await client.process(audioURL: audioURL)
                    preconditionFailure("Invalid response should not be inserted")
                } catch { }
                let count = await mock.requests.count
                precondition(count == 1)
            }

            let cancelledMock = MockTransport(body: reply("Must not insert"), cancel: true)
            let cancelledClient = ProviderClient(settings: defaults, apiKey: "test-credential", transport: { try await cancelledMock.send($0) })
            do {
                _ = try await cancelledClient.process(audioURL: audioURL)
                preconditionFailure("Cancellation should propagate")
            } catch is CancellationError { }
            let cancelledCount = await cancelledMock.requests.count
            precondition(cancelledCount == 1)

            for invalid in [openAI, custom] {
                do {
                    _ = try ProviderClient(settings: invalid, apiKey: "test-credential").makeAudioRequest(audio: audio)
                    preconditionFailure("Legacy provider credentials must not be sent")
                } catch ProviderError.unsupportedProvider { }
            }
            var emptyModel = defaults
            emptyModel.model = "  "
            do {
                _ = try ProviderClient(settings: emptyModel, apiKey: "test-credential").makeAudioRequest(audio: audio)
                preconditionFailure("Empty model must be rejected")
            } catch ProviderError.missingProcessingModel { }
            do {
                _ = try ProviderClient(settings: defaults, apiKey: "").makeAudioRequest(audio: audio)
                preconditionFailure("Empty API key must be rejected")
            } catch ProviderError.missingAPIKey { }

            let cost = UsageAnalytics.estimatedCost(durationSeconds: 60, spokenText: "ignored live preview", finalText: "Hello world", settings: defaults)
            let promptTokens = Double(UsageAnalytics.wordCount(editor.effectiveProcessingPrompt)) * 1.35
            let expected = (1920 * 0.30 + promptTokens * 0.30 + 2 * 1.35 * 2.50) / 1_000_000
            precondition(abs(cost - expected) < 0.000000001)
            let differentPreviewCost = UsageAnalytics.estimatedCost(durationSeconds: 60, spokenText: "", finalText: "Hello world", settings: defaults)
            precondition(cost == differentPreviewCost)
            let shortEditCost = UsageAnalytics.estimatedCost(durationSeconds: 0, spokenText: "", finalText: "", settings: defaults, selectedText: "One word")
            let longEditCost = UsageAnalytics.estimatedCost(durationSeconds: 0, spokenText: "", finalText: "", settings: defaults, selectedText: String(repeating: "word ", count: 1000))
            precondition(longEditCost > shortEditCost)
            let verbatimCost = UsageAnalytics.estimatedCost(durationSeconds: 60, spokenText: "", finalText: "Hello world", settings: verbatim)
            precondition(verbatimCost > 1920 * 0.30 / 1_000_000)

        }

        print("Google Direct/OpenRouter: migration, isolated connection settings, all writing modes, single-request edits, failure handling and cost tests passed")
    }
}

func reply(_ text: String, finishReason: String = "stop") -> Data {
    try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": text], "finish_reason": finishReason]]])
}

actor MockTransport {
    private(set) var requests: [URLRequest] = []
    let body: Data
    let status: Int
    let errorCode: URLError.Code?
    let cancel: Bool

    init(body: Data, status: Int = 200, errorCode: URLError.Code? = nil, cancel: Bool = false) {
        self.body = body
        self.status = status
        self.errorCode = errorCode
        self.cancel = cancel
    }

    func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        if cancel { throw CancellationError() }
        if let errorCode { throw URLError(errorCode) }
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
SWIFT
swiftc -swift-version 6 Sources/ChatterKey/Models.swift Sources/ChatterKey/Services/VoiceTextProcessor.swift Sources/ChatterKey/Services/ProviderEndpointPolicy.swift Sources/ChatterKey/Services/ProviderClient.swift Sources/ChatterKey/Services/UsageAnalytics.swift "$TMP/ModelHarness.swift" -o "$TMP/model-tests"
"$TMP/model-tests"
