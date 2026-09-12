#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/ModelHarness.swift" <<'SWIFT'
import AppKit
import AVFoundation
import Foundation

@main
@MainActor
struct ModelHarness {
    static func main() async throws {
        try await testLocalRegressions()
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

            for literal in ["\"Quoted text\"", "```swift\nlet value = 1\n```", "Intro\n```swift\nlet value = 1\n```\nOutro"] {
                for mode in [OutputMode.verbatim, .technical] {
                    var config = defaults
                    config.outputMode = mode
                    let mock = MockTransport(body: reply(literal))
                    let client = ProviderClient(settings: config, apiKey: "test-credential", transport: { try await mock.send($0) })
                    let output = try await client.process(audioURL: audioURL)
                    precondition(output == literal)
                    let edited = try await client.process(audioURL: audioURL, editing: selected)
                    precondition(edited == literal)
                }
            }

            var verbatim = defaults
            verbatim.outputMode = .verbatim
            precondition(VoiceTextProcessor.process("new line insert quick thanks", settings: verbatim) == "new line insert quick thanks")

            let indented = "    let value = 1\n"
            let literalMock = MockTransport(body: reply(indented))
            let literalClient = ProviderClient(settings: verbatim, apiKey: "test-credential", transport: { try await literalMock.send($0) })
            let literalOutput = try await literalClient.process(audioURL: audioURL)
            precondition(literalOutput == indented)
            let literalEdit = try await literalClient.process(audioURL: audioURL, editing: selected)
            precondition(literalEdit == indented)

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
                MockTransport(body: reply("new line")),
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

            let cost = UsageAnalytics.estimatedCost(durationSeconds: 60, finalText: "Hello world", settings: defaults)
            let promptTokens = Double(UsageAnalytics.wordCount(editor.effectiveProcessingPrompt)) * 1.35
            let expected = (1920 * 0.30 + promptTokens * 0.30 + 2 * 1.35 * 2.50) / 1_000_000
            precondition(abs(cost - expected) < 0.000000001)
            let shortEditCost = UsageAnalytics.estimatedCost(durationSeconds: 0, finalText: "", settings: defaults, selectedText: "One word")
            let longEditCost = UsageAnalytics.estimatedCost(durationSeconds: 0, finalText: "", settings: defaults, selectedText: String(repeating: "word ", count: 1000))
            precondition(longEditCost > shortEditCost)
            let verbatimCost = UsageAnalytics.estimatedCost(durationSeconds: 60, finalText: "Hello world", settings: verbatim)
            precondition(verbatimCost > 1920 * 0.30 / 1_000_000)

        }

        print("Local clipboard, hotkey, audio, history, settings and text regression tests passed")
        print("Google Direct/OpenRouter: migration, isolated connection settings, all writing modes, single-request edits, failure handling and cost tests passed")
    }

    static func testLocalRegressions() async throws {
        let suite = "ChatterKey-Regression-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let unreadable = Data("unreadable settings".utf8)
        defaults.set(unreadable, forKey: ProviderSettings.storageKey)
        _ = ProviderSettings.load(defaults: defaults)
        precondition(defaults.data(forKey: ProviderSettings.storageKey) == unreadable)

        let now = Date()
        let old = DictationHistoryItem(text: "expired fixture", createdAt: now.addingTimeInterval(-10 * 86_400), outputMode: .verbatim)
        let recent = DictationHistoryItem(text: "recent fixture", createdAt: now, outputMode: .verbatim)
        HistoryStore.save([recent, old], defaults: defaults)
        let retained = HistoryStore.load(retentionDays: 1, defaults: defaults)
        precondition(retained.count == 1 && retained[0].id == recent.id)
        let stored = try JSONDecoder().decode([DictationHistoryItem].self, from: defaults.data(forKey: "dictation-history-v1")!)
        precondition(stored.count == 1 && stored[0].id == recent.id)

        for rate in [-1.0, Double.infinity, Double.nan] {
            var settings = ProviderSettings()
            settings.costRates.audioPerMillionTokens = rate
            do { try settings.validate(); preconditionFailure("Invalid cost rate accepted") }
            catch ProviderError.invalidCostRates { }
        }
        var settings = ProviderSettings()
        settings.model = "  gemini-test  "
        try settings.validate()
        precondition(settings.model == "gemini-test")
        settings.voiceSnippets = [
            VoiceSnippet(cue: "long cue", content: "short cue $1"),
            VoiceSnippet(cue: "short cue", content: "must not expand recursively")
        ]
        let expanded = VoiceTextProcessor.process("LONG CUE", settings: settings)
        precondition(expanded == "short cue $1")
        let suggestions = UsageAnalytics.suggestions(for: "SecretProject SecretClient starts soon. SecretProject SecretClient starts soon.")
        precondition(!suggestions.joined().contains("secretproject"))

        let empty = try TextSelectionReader.usableSelection("")
        precondition(empty == nil)
        let selection = "नमस्ते 👋\nSecond line"
        let valid = try TextSelectionReader.usableSelection(selection)
        precondition(valid == selection)
        do {
            _ = try TextSelectionReader.usableSelection(String(repeating: "x", count: 50_001))
            preconditionFailure("Oversized selection accepted")
        } catch SelectionError.tooLong { }
        precondition(TextSelectionReader.text(in: "A👋B", range: CFRange(location: 1, length: 2)) == "👋")
        for range in [CFRange(location: -1, length: 2), CFRange(location: 1, length: Int.max), CFRange(location: 9, length: 1)] {
            precondition(TextSelectionReader.text(in: "abc", range: range) == nil)
        }

        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        board.setData(Data("original rich text".utf8), forType: .rtf)
        let copied = try await ClipboardTransaction.perform {
            try await TextSelectionReader.copiedText(from: board, copy: {
                Task { @MainActor in
                    try await Task.sleep(for: .milliseconds(150))
                    board.clearContents()
                    board.setString(selection, forType: .string)
                }
            }, isCurrent: { true })
        }
        precondition(copied == selection)
        precondition(board.string(forType: .string) == "original")
        precondition(board.data(forType: .rtf) == Data("original rich text".utf8))
        let absent = try await TextSelectionReader.copiedText(from: board, copy: {}, isCurrent: { true })
        precondition(absent == nil && board.string(forType: .string) == "original")
        let snapshot = ClipboardSnapshot(board)
        let previousCount = board.changeCount
        board.clearContents()
        board.setString("user's newer copy", forType: .string)
        snapshot.restore(to: board, ifUnchangedSince: previousCount)
        precondition(board.string(forType: .string) == "user's newer copy")

        let cancelled = Task { @MainActor in
            try await ClipboardTransaction.perform {
                try await TextSelectionReader.copiedText(from: board, copy: {
                    Task { @MainActor in
                        try await Task.sleep(for: .milliseconds(100))
                        board.clearContents()
                        board.setString("delayed copy", forType: .string)
                    }
                }, isCurrent: { true })
            }
        }
        try await Task.sleep(for: .milliseconds(30))
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Cancellation lost") }
        catch is CancellationError { }
        precondition(board.string(forType: .string) == "user's newer copy")

        var order: [Int] = []
        let first = Task { @MainActor in
            try await ClipboardTransaction.perform {
                order.append(1)
                try await Task.sleep(for: .milliseconds(40))
                order.append(2)
            }
        }
        try await Task.sleep(for: .milliseconds(10))
        try await ClipboardTransaction.perform { order.append(3) }
        try await first.value
        precondition(order == [1, 2, 3])

        for shortcut in [HotkeyShortcut.optionSpace, .commandShiftSpace] {
            let hotkey = GlobalHotkey()
            hotkey.configure(shortcut)
            var presses = 0, releases = 0
            hotkey.onPress = { presses += 1 }
            hotkey.onRelease = { releases += 1 }
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!
            down.flags = shortcut == .optionSpace ? .maskAlternate : [.maskCommand, .maskShift]
            precondition(hotkey.handleCGEvent(type: .keyDown, event: down))
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: false)!
            up.flags = []
            precondition(hotkey.handleCGEvent(type: .keyUp, event: up))
            try await Task.sleep(for: .milliseconds(20))
            precondition(presses == 1 && releases == 1)
            _ = hotkey.handleCGEvent(type: .keyDown, event: down)
            try await Task.sleep(for: .milliseconds(20))
            _ = hotkey.handleCGEvent(type: .keyUp, event: up)
            hotkey.configure(.function)
            try await Task.sleep(for: .milliseconds(20))
            precondition(presses == 2 && releases == 2, "Reconfiguration dropped a pending release")
            hotkey.stop()
        }
        let hotkey = GlobalHotkey()
        hotkey.configure(.optionSpace)
        var presses = 0
        hotkey.onPress = { presses += 1 }
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!
        down.flags = .maskAlternate
        _ = hotkey.handleCGEvent(type: .keyDown, event: down)
        hotkey.configure(.function)
        try await Task.sleep(for: .milliseconds(20))
        precondition(presses == 0, "Stale queued press started a recording")
        hotkey.stop()

        var releases = 0, cancels = 0
        hotkey.onRelease = { releases += 1 }
        hotkey.onCancel = { cancels += 1 }
        let modifier = CGEvent(keyboardEventSource: nil, virtualKey: 63, keyDown: true)!
        let paste = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true)!
        paste.setIntegerValueField(.eventSourceUserData, value: TextSelectionReader.syntheticTextEventTag)
        modifier.flags = .maskSecondaryFn
        _ = hotkey.handleCGEvent(type: .flagsChanged, event: modifier)
        precondition(!hotkey.handleCGEvent(type: .keyDown, event: paste))
        modifier.flags = []
        _ = hotkey.handleCGEvent(type: .flagsChanged, event: modifier)
        try await Task.sleep(for: .milliseconds(20))
        precondition(releases == 1 && cancels == 0)
        hotkey.stop()

        do {
            _ = try await ClipboardTransaction.perform {
                try await TextSelectionReader.copiedText(from: board, copy: {
                    board.clearContents()
                    board.setString("new focus copy", forType: .string)
                }, isCurrent: { false })
            }
            preconditionFailure("Changed focus was accepted")
        } catch SelectionError.focusChanged { }
        precondition(board.string(forType: .string) == "new focus copy")
        let unlocked = try await ClipboardTransaction.perform { 42 }
        precondition(unlocked == 42, "Failed clipboard operation retained the lock")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for sampleRate in [16_000.0, 44_100.0, 48_000.0] {
            let source = directory.appendingPathComponent("capture-\(sampleRate).caf")
            let destination = directory.appendingPathComponent("output-\(sampleRate).wav")
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
            let frames = AVAudioFrameCount(sampleRate * 2)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            for channel in 0..<2 {
                for index in 0..<Int(frames) { buffer.floatChannelData![channel][index] = 0.25 }
            }
            do {
                var fileSettings = format.settings
                fileSettings[AVLinearPCMIsNonInterleaved] = false
                let file = try AVAudioFile(forWriting: source, settings: fileSettings)
                try file.write(from: buffer)
            }
            try AudioRecorder.convertToProviderWAV(from: source, to: destination)
            let converted = try AVAudioFile(forReading: destination)
            precondition(converted.fileFormat.sampleRate == 16_000)
            precondition(converted.fileFormat.channelCount == 1)
            precondition(converted.fileFormat.commonFormat == .pcmFormatInt16)
            precondition(abs(converted.length - 32_000) < 20)
            let output = AVAudioPCMBuffer(pcmFormat: converted.processingFormat, frameCapacity: 512)!
            try converted.read(into: output)
            precondition(abs(output.floatChannelData![0][100]) > 0.1, "Conversion lost the audio signal")
        }
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
swiftc -swift-version 6 Sources/ChatterKey/Models.swift Sources/ChatterKey/Services/VoiceTextProcessor.swift Sources/ChatterKey/Services/ProviderEndpointPolicy.swift Sources/ChatterKey/Services/ProviderClient.swift Sources/ChatterKey/Services/UsageAnalytics.swift Sources/ChatterKey/Services/HistoryStore.swift Sources/ChatterKey/Services/ClipboardTransaction.swift Sources/ChatterKey/Services/TextSelectionReader.swift Sources/ChatterKey/Services/GlobalHotkey.swift Sources/ChatterKey/Services/AudioRecorder.swift "$TMP/ModelHarness.swift" -o "$TMP/model-tests"
"$TMP/model-tests"
