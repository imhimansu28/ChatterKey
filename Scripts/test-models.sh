#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/ModelHarness.swift" <<'SWIFT'
import ChatterKeyCore
import ChatterKeyAndroidBridge
import AppKit
import AVFoundation
import Foundation

@main
@MainActor
struct ModelHarness {
    static func testAudioImports() async throws {
        let noteSource = "## Main ideas\n- **Save water**\n- Repair taps\n\n3. First step\n4. Next step\n\nA [reference](https://example.com)."
        let formatted = AudioImportText.format(noteSource)
        precondition(String(formatted.characters) == "Main ideas\n• Save water\n• Repair taps\n\n3. First step\n4. Next step\n\nA reference.")
        precondition(formatted.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        precondition(formatted.runs.allSatisfy { $0.link == nil }, "Generated Markdown created interactive links")
        let table = "| Name | Value |\n| --- | --- |\n| Price | ₹500 |"
        precondition(String(AudioImportText.format(table).characters) == table, "Unsupported layout lost its structure")
        var settings = ProviderSettings()
        settings.spokenCommandsEnabled = true
        settings.voiceSnippets = [VoiceSnippet(cue: "my email", content: "must-not-expand@example.com")]
        settings.systemPrompt = "IMPORT MUST NOT USE THIS CUSTOM PROMPT"
        let transcript = "my email comma new paragraph — नमस्ते"
        for provider in AIProvider.availableConnections {
            settings.selectProvider(provider)
            for mode in AudioImportMode.allCases {
                for format in AudioImportFormat.allCases {
                    let json = try JSONSerialization.data(withJSONObject: [
                        "transcript": transcript, "context": mode == .rawTranscript ? "" : "A personal voice memo.",
                        "output": mode == .rawTranscript ? "" : "- my email comma new paragraph"
                    ])
                    let mock = MockTransport(body: reply(String(decoding: json, as: UTF8.self)))
                    let client = ProviderClient(settings: settings, apiKey: "test-credential", transport: { try await mock.send($0) })
                    let audio = Data("fixture audio".utf8)
                    let result = try await client.processImportedAudio(audio, format: format, mode: mode)
                    precondition(result.transcript == transcript, "Import changed raw words or expanded commands/snippets")
                    let requests = await mock.requests
                    precondition(requests.count == 1, "Import must not add a transcription/polishing pair")
                    precondition(requests[0].timeoutInterval == 300)
                    let body = try JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: Any]
                    precondition(body["max_tokens"] as? Int == 32_768)
                    precondition((body["response_format"] as? [String: String])?["type"] == "json_object")
                    if provider == .openRouter {
                        precondition((body["provider"] as? [String: Any])?["require_parameters"] == nil,
                                     "Direct import changed provider routing")
                    }
                    let messages = body["messages"] as! [[String: Any]]
                    let prompt = (messages[0]["content"] as! [[String: Any]])[0]["text"] as! String
                    precondition(prompt == mode.prompt)
                    precondition(!prompt.contains(settings.systemPrompt) && !prompt.contains("must-not-expand@example.com"))
                    precondition(messages.count == 2)
                    let input = (messages[1]["content"] as! [[String: Any]])[0]["input_audio"] as! [String: String]
                    precondition(input["format"] == format.rawValue && input["data"] == audio.base64EncodedString())
                    let normal = try client.makeAudioRequest(audio: Data("fixture".utf8))
                    precondition(normal.timeoutInterval == 40, "Import changed the dictation timeout")
                    let normalBody = try JSONSerialization.jsonObject(with: normal.httpBody!) as! [String: Any]
                    precondition(normalBody["response_format"] == nil && normalBody["max_tokens"] as? Int == 16_384)
                }
            }
        }
        // Long chunks request plain transcripts from the start. Quoted/multilingual speech
        // must not be rejected for failing an unrelated JSON/derived-field contract.
        let chunkText = "उन्होंने कहा, \"₹500\" — qualification: \"not guaranteed\".\n" +
            String(repeating: "Example, explanation, names, numbers; my email comma new paragraph.\n", count: 200)
        for provider in AIProvider.availableConnections {
            settings.selectProvider(provider)
            let mock = MockTransport(body: reply(chunkText))
            let client = ProviderClient(settings: settings, apiKey: "test-credential", transport: { try await mock.send($0) })
            let text = try await client.transcribeImportedChunk(Data("fixture audio".utf8))
            precondition(text == chunkText, "Chunk transcription rewrote the source or applied dictation transforms")
            let requests = await mock.requests
            precondition(requests.count == 1 && requests[0].timeoutInterval == 300)
            let body = try JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: Any]
            precondition(body["response_format"] == nil && body["model"] as? String == settings.provider.requestModelID(settings.model))
            let messages = body["messages"] as! [[String: Any]]
            let prompt = (messages[0]["content"] as! [[String: Any]])[0]["text"] as! String
            precondition(prompt == AudioImportMode.chunkTranscriptionPrompt)
            precondition(!prompt.contains(settings.systemPrompt))
            let input = (messages[1]["content"] as! [[String: Any]])[0]["input_audio"] as! [String: String]
            precondition(input["format"] == "wav")
            if provider == .openRouter {
                let routing = body["provider"] as! [String: Any]
                precondition(routing["allow_fallbacks"] as? Bool == false && routing["require_parameters"] == nil)
            }
        }
        let validImport = #"{"transcript":"source","context":"memo","output":"notes"}"#
        let missingFinishReason = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": validImport]]]])
        let blocked = try JSONSerialization.data(withJSONObject: ["choices": [[
            "message": ["content": validImport], "finish_reason": "content_filter", "native_finish_reason": "RECITATION"
        ]]])
        let unknownReason = try JSONSerialization.data(withJSONObject: ["choices": [[
            "message": ["content": validImport], "finish_reason": "PRIVATE_RESPONSE_SENTINEL",
            "native_finish_reason": "PRIVATE_RESPONSE_SENTINEL"
        ]]])
        let failures: [(Data, String, String)] = [
            (reply("not JSON PRIVATE_RESPONSE_SENTINEL"), "malformed JSON", "malformed JSON"),
            (reply("{}"), "missing the transcript field", "missing the context field"),
            (reply(#"{"transcript":42,"context":42,"output":42}"#), "non-string required field", "non-string required field"),
            (reply(#"{"transcript":"source","context":null,"output":"notes"}"#), "contains null", "contains null"),
            (reply(#"{"transcript":"source","context":"","output":"notes"}"#), "empty context", "empty context"),
            (reply(#"{"transcript":"source","context":"memo","output":""}"#), "empty output", "empty output"),
            (missingFinishReason, "finish_reason=missing", "finish_reason=missing"),
            (blocked, "finish_reason=content_filter; native_finish_reason=RECITATION", "finish_reason=content_filter; native_finish_reason=RECITATION"),
            (unknownReason, "finish_reason=unrecognized; native_finish_reason=unrecognized", "finish_reason=unrecognized; native_finish_reason=unrecognized"),
            (reply(""), "no text content", "no text content"),
            (Data("not an envelope".utf8), "JSON envelope", "JSON envelope"),
            (Data(#"{"choices":[]}"#.utf8), "no completion choices", "no completion choices")
        ] + ["length", "content_filter", "tool_calls", "error"].map { reason in
            let expected = reason == "length" ? "cut off" : "finish_reason=\(reason)"
            return (reply(validImport, finishReason: reason), expected, expected)
        }
        for (body, audioFailure, finalFailure) in failures {
            let mock = MockTransport(body: body)
            let client = ProviderClient(settings: settings, apiKey: "test-credential", transport: { try await mock.send($0) })
            do {
                _ = try await client.processImportedAudio(Data("fixture".utf8), mode: .notes)
                preconditionFailure("Incomplete imported result was accepted")
            } catch {
                precondition(error.localizedDescription.contains(audioFailure), "Audio failure did not identify its cause")
                precondition(!error.localizedDescription.contains("PRIVATE_RESPONSE_SENTINEL"), "Diagnostics exposed response text")
            }
            var requests = await mock.requests
            precondition(requests.count == 1, "Failure silently retried or repaired")
            do {
                _ = try await client.processImportedTranscript("Complete source", mode: .notes)
                preconditionFailure("Invalid final output accepted")
            } catch {
                precondition(error.localizedDescription.contains(finalFailure), "Final output failure did not identify its cause")
                precondition(!error.localizedDescription.contains("PRIVATE_RESPONSE_SENTINEL"), "Diagnostics exposed response text")
            }
            requests = await mock.requests
            precondition(requests.count == 2, "Final output failure silently retried")
            if audioFailure.contains("finish_reason=") || ["cut off", "no text content", "JSON envelope", "no completion choices"].contains(audioFailure) {
                do {
                    _ = try await client.transcribeImportedChunk(Data("fixture".utf8))
                    preconditionFailure("Plain transcript path accepted an unconfirmed/incomplete chunk")
                } catch {
                    precondition(error.localizedDescription.contains(audioFailure))
                    precondition(!error.localizedDescription.contains("PRIVATE_RESPONSE_SENTINEL"))
                }
                requests = await mock.requests
                precondition(requests.count == 3, "Chunk failure caused an automatic retry")
            }
        }
        for duration in [1799.0, 1800.0, 1800.001, 2700.0, 3048.0, 14400.0] {
            let plan = try AudioImportPlan(duration: duration)
            precondition(plan.isChunked == (duration > 1800))
            precondition(abs(plan.durations.reduce(0, +) - duration) < 0.00001)
            for mode in AudioImportMode.allCases {
                precondition(plan.requestCount(mode: mode) == plan.durations.count + (duration > 1800 && mode != .rawTranscript ? 1 : 0))
            }
        }
        for duration in [0.0, -1, Double.nan, Double.infinity, 14400.01] {
            do { _ = try AudioImportPlan(duration: duration); preconditionFailure("Unbounded duration accepted") }
            catch AudioImportError.resourceLimit { }
        }
        var checkpoint = AudioImportCheckpoint(plan: try AudioImportPlan(duration: 3048))
        precondition(checkpoint.plan.durations == [900, 900, 900, 348])
        for text in ["पहला 42", "second example", "qualification", "last detail"] {
            do { _ = try checkpoint.mergedTranscript(); preconditionFailure("Incomplete transcript merged") }
            catch AudioImportError.incompleteChunks { }
            try checkpoint.append(text)
        }
        let merged = try checkpoint.mergedTranscript()
        precondition(merged == "पहला 42\n\nsecond example\n\nqualification\n\nlast detail")
        var bounded = AudioImportCheckpoint(plan: checkpoint.plan)
        do { try bounded.append(String(repeating: "a", count: AudioImportPlan.maximumTranscriptBytes + 1)); preconditionFailure("Unbounded transcript accepted") }
        catch AudioImportError.resourceLimit { }
        precondition(bounded.transcripts.isEmpty)
        let unused = MockTransport(body: reply("unused"))
        let client = ProviderClient(settings: settings, apiKey: "test-credential", transport: { try await unused.send($0) })
        do { _ = try await client.processImportedAudio(Data(), mode: .rawTranscript); preconditionFailure("Empty audio accepted") }
        catch AudioImportError.tooLarge { }
        let raw = try await client.processImportedTranscript(merged, mode: .rawTranscript)
        precondition(raw.transcript == merged)
        let requests = await unused.requests
        precondition(requests.isEmpty, "Raw merged transcript made an extra request")
        if let path = ProcessInfo.processInfo.environment["CHATTERKEY_IMPORT_FIXTURE"] {
            let url = URL(fileURLWithPath: path)
            let original = try Data(contentsOf: url)
            let prepared = try await AudioFileImporter.prepare(url)
            let unchanged = try Data(contentsOf: url)
            precondition(unchanged == original, "Import changed the source recording")
            precondition(prepared.duration > 0 && prepared.preparedBytes > 44)
            if prepared.plan.isChunked {
                precondition(prepared.audio.isEmpty && prepared.chunks.count == prepared.plan.durations.count)
                var durations: [Double] = []
                for (index, chunk) in prepared.chunks.enumerated() {
                    let audio = try AVAudioFile(forReading: chunk)
                    let duration = Double(audio.length) / audio.fileFormat.sampleRate
                    precondition(abs(duration - prepared.plan.durations[index]) < 0.01)
                    precondition(audio.fileFormat.sampleRate == 16_000 && audio.fileFormat.channelCount == 1)
                    durations.append(duration)
                }
                print("Optional local chunk durations: \(durations); raw requests: \(prepared.plan.requestCount(mode: .rawTranscript)); notes/summary requests: \(prepared.plan.requestCount(mode: .notes)). No provider request.")
            }
            if prepared.format == .mp3 {
                precondition(prepared.audio == original, "MP3 preparation changed compressed audio")
                precondition(Double(prepared.audio.count) < prepared.duration * 32_000)
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let renamed = directory.appendingPathComponent("renamed.wav")
                try original.write(to: renamed)
                let detected = try await AudioFileImporter.prepare(renamed)
                precondition(detected.format == .mp3 && detected.audio == original, "Import trusted the extension instead of the container")
            }
            print("Optional local import fixture: \(Int(prepared.duration)) seconds, \(prepared.preparedBytes) \(prepared.format.rawValue.uppercased()) bytes. No provider request.")
        }
    }

    static func testChunkedImport(_ url: URL) async throws {
        func wait(_ model: AudioImportModel) async throws {
            for _ in 0..<3000 where model.isBusy { try await Task.sleep(for: .milliseconds(10)) }
            precondition(!model.isBusy, "Import did not finish")
        }
        let chunkReplies = (1...4).map { reply("chunk \($0) detail") }
        let final = reply(#"{"context":"A lecture","output":"Detailed notes\n- All details"}"#)
        let merged = (1...4).map { "chunk \($0) detail" }.joined(separator: "\n\n")
        for provider in AIProvider.availableConnections {
            var settings = ProviderSettings()
            settings.selectProvider(provider)
            for mode in AudioImportMode.allCases {
                let mock = MockTransport(body: final, responses: chunkReplies + [final], retainLargeBodies: false)
                let model = AudioImportModel(transport: { try await mock.send($0) })
                model.select(url)
                try await wait(model)
                precondition(model.error == nil && model.file?.chunks.count == 4)
                precondition(!model.requiresDiscardConfirmation, "Unprocessed selection prompted about lost results")
                let paths = model.file!.chunks
                for (index, path) in paths.enumerated() {
                    let chunk = try AVAudioFile(forReading: path)
                    let sample = AVAudioPCMBuffer(pcmFormat: chunk.processingFormat, frameCapacity: 1)!
                    try chunk.read(into: sample, frameCount: 1)
                    precondition(abs(sample.floatChannelData![0][0] * 32768 - Float((index + 1) * 1000)) < 2, "Chunk seek lost its first sample")
                    chunk.framePosition = chunk.length - 1
                    try chunk.read(into: sample, frameCount: 1)
                    precondition(abs(sample.floatChannelData![0][0] * 32768 - Float((index + 1) * 2000)) < 2, "Chunk range lost its last sample")
                }
                model.mode = mode
                precondition(model.requestDisclosure.contains(mode == .rawTranscript ? "4 requests" : "5 requests"))
                let before = await mock.requests
                precondition(before.isEmpty, "File selection uploaded audio")
                model.generate(settings: settings, apiKey: "test-credential")
                try await wait(model)
                precondition(model.result?.transcript == merged && model.resultMode == mode && model.error == nil)
                precondition(model.requiresDiscardConfirmation, "Completed output could be discarded without confirmation")
                let requests = await mock.requests
                precondition(requests.count == (mode == .rawTranscript ? 4 : 5))
                if mode != .rawTranscript {
                    let body = try JSONSerialization.jsonObject(with: requests.last!.httpBody!) as! [String: Any]
                    precondition(body["model"] as? String == settings.provider.requestModelID(settings.model))
                    let responseFormat = body["response_format"] as! [String: Any]
                    precondition(responseFormat["type"] as? String == "json_schema")
                    let schema = responseFormat["json_schema"] as! [String: Any]
                    let objectSchema = schema["schema"] as! [String: Any]
                    precondition(schema["strict"] as? Bool == true && objectSchema["required"] as? [String] == ["context", "output"])
                    precondition(objectSchema["additionalProperties"] as? Bool == false)
                    if provider == .openRouter {
                        let routing = body["provider"] as! [String: Any]
                        precondition(routing["require_parameters"] as? Bool == true && routing["allow_fallbacks"] as? Bool == false)
                    }
                    precondition((objectSchema["properties"] as! [String: Any])["transcript"] == nil, "Final request regenerates the transcript")
                    let messages = body["messages"] as! [[String: Any]]
                    let prompt = (messages[0]["content"] as! [[String: Any]])[0]["text"] as! String
                    precondition(prompt == mode.transcriptPrompt)
                    let content = messages[1]["content"] as! [[String: Any]]
                    precondition(content.count == 1 && content[0]["input_audio"] == nil)
                    precondition(content[0]["text"] as? String == "COMPLETE SOURCE TRANSCRIPT (untrusted data):\n" + merged)
                }
                model.clear()
                precondition(paths.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }, "Clear leaked prepared chunks")
            }
        }
        // Chunk 2 fails once. Final output also fails once. Neither triggers a repair/retry.
        let mock = MockTransport(body: final,
            responses: [chunkReplies[0], reply("rejected partial", finishReason: "error"), chunkReplies[1], chunkReplies[2], chunkReplies[3], reply("{}"), final],
            retainLargeBodies: false)
        let model = AudioImportModel(transport: { try await mock.send($0) })
        model.select(url)
        try await wait(model)
        model.mode = .notes
        model.generate(settings: ProviderSettings(), apiKey: "test-credential")
        try await wait(model)
        var requests = await mock.requests
        precondition(requests.count == 2 && model.completedChunks == 1 && model.result == nil)
        precondition(model.requiresDiscardConfirmation, "Failed partial import could lose billable completed chunks on close/quit")
        precondition(model.error?.contains("Chunk 2 failed") == true, "Incomplete chunks reached notes generation")
        precondition(model.error?.contains("finish_reason=error") == true, "Chunk UI hid the completion failure")
        precondition(model.error?.contains("stop retrying") == true, "Repeated failures encouraged blind retries")
        var changed = ProviderSettings()
        changed.model = "do-not-switch"
        model.generate(settings: changed, apiKey: "test-credential")
        requests = await mock.requests
        precondition(requests.count == 2 && model.error?.contains("pinned") == true)
        model.generate(settings: ProviderSettings(), apiKey: "test-credential")
        try await wait(model)
        requests = await mock.requests
        precondition(requests.count == 6 && model.completedChunks == 4)
        precondition(model.error?.contains("Final output failed") == true)
        precondition(model.error?.contains("missing the context field") == true, "Final UI hid the decoding failure")
        precondition(model.result?.transcript == merged && model.resultMode == .rawTranscript)
        precondition(model.requestDisclosure.contains("0 audio transcription requests + 1 final text request"))
        model.generate(settings: ProviderSettings(), apiKey: "test-credential")
        try await wait(model)
        requests = await mock.requests
        precondition(requests.count == 7 && model.resultMode == .notes && model.result?.transcript == merged)
        model.clear()

        // Cancel during chunk 2, then explicitly resume: only unfinished work is resent.
        let cancellation = MockTransport(body: final,
            responses: [chunkReplies[0], chunkReplies[1], chunkReplies[1], chunkReplies[2], chunkReplies[3]],
            retainLargeBodies: false, pauseAt: 2)
        let cancelled = AudioImportModel(transport: { try await cancellation.send($0) })
        cancelled.select(url)
        try await wait(cancelled)
        let paths = cancelled.file!.chunks
        cancelled.generate(settings: ProviderSettings(), apiKey: "test-credential")
        for _ in 0..<3000 {
            if await cancellation.requests.count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(cancelled.completedChunks == 1 && cancelled.progress.contains("chunk 2 of 4"))
        precondition(cancelled.requiresDiscardConfirmation, "Active import could be discarded without confirmation")
        cancelled.cancel()
        precondition(cancelled.requiresDiscardConfirmation, "Cancelling removed partial-checkpoint protection")
        cancelled.generate(settings: ProviderSettings(), apiKey: "test-credential")
        try await wait(cancelled)
        requests = await cancellation.requests
        precondition(requests.count == 5 && cancelled.result?.transcript == merged && cancelled.error == nil)
        cancelled.clear()
        precondition(!cancelled.requiresDiscardConfirmation, "Cleared import still blocks close/quit")
        precondition(paths.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        print("Chunked import: both providers/all modes; ordered merge; failed chunk/final retry; pinned model; cancellation and cleanup passed.")
    }

    static func main() async throws {
        try testAndroidBridge()
        try await testLocalRegressions()
        try await testAudioImports()
        try await testEditPreview()
        try await testHandsFreeHotkey()
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
                    let output = try await client.process(audio: audio)
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
            let edited = try await editor.process(audio: audio, editing: selected)
            precondition(edited == "new line insert quick thanks") // No local snippet/command expansion in edits.
            let editRequests = await editMock.requests
            precondition(editRequests.count == 1)
            let editBody = try JSONSerialization.jsonObject(with: editRequests[0].httpBody!) as! [String: Any]
            let editMessages = editBody["messages"] as! [[String: Any]]
            let editContent = editMessages[1]["content"] as! [[String: Any]]
            precondition(editContent.count == 2)
            precondition((editContent[0]["text"] as? String)?.contains(selected) == true)
            precondition(editContent[1]["type"] as? String == "input_audio")
            precondition(ProcessingPrompt.build(settings: defaults, editing: selected).contains("spoken instruction"))
            precondition(!ProcessingPrompt.build(settings: defaults, editing: selected).contains(defaults.outputMode.instruction))
            precondition(ProcessingPrompt.build(settings: defaults, editing: "  ") == ProcessingPrompt.build(settings: defaults))

            for literal in ["\"Quoted text\"", "```swift\nlet value = 1\n```", "Intro\n```swift\nlet value = 1\n```\nOutro"] {
                for mode in [OutputMode.verbatim, .technical] {
                    var config = defaults
                    config.outputMode = mode
                    let mock = MockTransport(body: reply(literal))
                    let client = ProviderClient(settings: config, apiKey: "test-credential", transport: { try await mock.send($0) })
                    let output = try await client.process(audio: audio)
                    precondition(output == literal)
                    let edited = try await client.process(audio: audio, editing: selected)
                    precondition(edited == literal)
                }
            }

            var verbatim = defaults
            verbatim.outputMode = .verbatim
            precondition(VoiceTextProcessor.process("new line insert quick thanks", settings: verbatim) == "new line insert quick thanks")

            let indented = "    let value = 1\n"
            let literalMock = MockTransport(body: reply(indented))
            let literalClient = ProviderClient(settings: verbatim, apiKey: "test-credential", transport: { try await literalMock.send($0) })
            let literalOutput = try await literalClient.process(audio: audio)
            precondition(literalOutput == indented)
            let literalEdit = try await literalClient.process(audio: audio, editing: selected)
            precondition(literalEdit == indented)

            // Imperfect English must never trigger a hidden repair request.
            let hindiMock = MockTransport(body: reply("यह report ready hai."))
            let hindiClient = ProviderClient(settings: defaults, apiKey: "test-credential", transport: { try await hindiMock.send($0) })
            _ = try await hindiClient.process(audio: audio)
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
                    _ = try await client.process(audio: audio)
                    preconditionFailure("Invalid response should not be inserted")
                } catch { }
                let count = await mock.requests.count
                precondition(count == 1)
            }

            let cancelledMock = MockTransport(body: reply("Must not insert"), cancel: true)
            let cancelledClient = ProviderClient(settings: defaults, apiKey: "test-credential", transport: { try await cancelledMock.send($0) })
            do {
                _ = try await cancelledClient.process(audio: audio)
                preconditionFailure("Cancellation should propagate")
            } catch is CancellationError { }
            let cancelledCount = await cancelledMock.requests.count
            precondition(cancelledCount == 1)

            for invalid in [openAI, custom] {
                do {
                    _ = try ProviderClient(settings: invalid, apiKey: "test-credential", transport: { _ in preconditionFailure("Unexpected network request") }).makeAudioRequest(audio: audio)
                    preconditionFailure("Legacy provider credentials must not be sent")
                } catch ProviderError.unsupportedProvider { }
            }
            var emptyModel = defaults
            emptyModel.model = "  "
            do {
                _ = try ProviderClient(settings: emptyModel, apiKey: "test-credential", transport: { _ in preconditionFailure("Unexpected network request") }).makeAudioRequest(audio: audio)
                preconditionFailure("Empty model must be rejected")
            } catch ProviderError.missingProcessingModel { }
            do {
                _ = try ProviderClient(settings: defaults, apiKey: "", transport: { _ in preconditionFailure("Unexpected network request") }).makeAudioRequest(audio: audio)
                preconditionFailure("Empty API key must be rejected")
            } catch ProviderError.missingAPIKey { }

            let cost = UsageAnalytics.estimatedCost(durationSeconds: 60, finalText: "Hello world", settings: defaults)
            let promptTokens = Double(UsageAnalytics.wordCount(ProcessingPrompt.build(settings: defaults))) * 1.35
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

    static func testHandsFreeHotkey() async throws {
        let hotkey = GlobalHotkey()
        var calls: [String] = []
        hotkey.onPress = { [weak hotkey] in
            calls.append("start")
            hotkey?.recordingStarted()
        }
        hotkey.onRelease = { [weak hotkey] in
            calls.append("stop")
            hotkey?.resetRecordingGesture()
        }
        hotkey.onCancel = { [weak hotkey] in
            calls.append("cancel")
            hotkey?.resetRecordingGesture()
        }
        hotkey.onHandsFree = { calls.append("lock") }
        func fn(_ down: Bool, at timestamp: UInt64? = nil) {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 63, keyDown: down)!
            event.timestamp = timestamp ?? UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
            event.flags = down ? .maskSecondaryFn : []
            precondition(hotkey.handleCGEvent(type: .flagsChanged, event: event))
        }
        func key(_ code: CGKeyCode) -> Bool {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
            return hotkey.handleCGEvent(type: .keyDown, event: event)
        }
        func drain() async throws { try await Task.sleep(for: .milliseconds(20)) }
        let settled = GlobalHotkey.functionDoubleTapDelay + .milliseconds(40)

        fn(true)
        try await Task.sleep(for: .milliseconds(300))
        precondition(calls == ["start"])
        fn(false)
        try await drain()
        precondition(calls == ["start", "stop"], "Hold-to-talk must stop without the double-tap delay")

        calls = []
        fn(true); fn(false); fn(true); fn(false)
        try await Task.sleep(for: settled)
        precondition(calls == ["start", "lock"] && hotkey.isHandsFree, "Double-tap must not stop the first recording or start a second one")
        hotkey.configure(.function)
        precondition(hotkey.isHandsFree, "Refreshing an unchanged shortcut must not unlock recording")
        precondition(!key(0), "Ordinary typing should pass through while hands-free")
        fn(true)
        try await drain()
        precondition(calls == ["start", "lock", "stop"] && !hotkey.isHandsFree)
        fn(false)
        try await Task.sleep(for: settled)
        precondition(calls == ["start", "lock", "stop"], "The stop key's release must not restart or stop twice")

        calls = []
        fn(true); fn(false); fn(true); fn(false)
        try await drain()
        precondition(key(53), "Escape must cancel a locked recording with Fn released")
        try await Task.sleep(for: settled)
        precondition(calls == ["start", "lock", "cancel"] && !hotkey.isHandsFree)

        calls = []
        fn(true); fn(false)
        try await Task.sleep(for: settled)
        precondition(calls == ["start", "stop"], "A single short Fn tap must complete once after the grace interval")

        calls = []
        let timestamp = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        fn(true, at: timestamp)
        try await Task.sleep(for: .milliseconds(300))
        fn(false, at: timestamp + 50_000_000)
        fn(true, at: timestamp + 150_000_000)
        fn(false, at: timestamp + 200_000_000)
        try await drain()
        precondition(calls == ["start", "lock"] && hotkey.isHandsFree, "Delayed event delivery must not turn a physical double-tap into a hold")
        precondition(key(53))
        try await drain()

        calls = []
        fn(true, at: timestamp + 1_000_000_000)
        fn(false, at: timestamp + 1_050_000_000)
        fn(true, at: timestamp + 1_600_000_000)
        fn(false, at: timestamp + 1_650_000_000)
        try await Task.sleep(for: settled)
        precondition(calls == ["start", "stop"] && !hotkey.isHandsFree, "An overdue timer must not lock taps whose physical timestamps are too far apart")

        calls = []
        fn(true); fn(false)
        try await drain()
        hotkey.configure(.rightOption)
        try await Task.sleep(for: settled)
        precondition(calls == ["start", "cancel"], "Changing shortcuts must cancel pending tap timers")
        calls = []
        let option = CGEvent(keyboardEventSource: nil, virtualKey: 61, keyDown: true)!
        option.flags = .maskAlternate
        precondition(hotkey.handleCGEvent(type: .flagsChanged, event: option))
        try await drain()
        option.flags = []
        precondition(hotkey.handleCGEvent(type: .flagsChanged, event: option))
        try await drain()
        precondition(calls == ["start", "stop"], "Other modifier shortcuts remain hold-to-talk")
        hotkey.configure(.function)

        calls = []
        fn(true); fn(false); fn(true); fn(false)
        try await drain()
        hotkey.configure(.optionSpace)
        try await drain()
        precondition(calls == ["start", "lock", "cancel"] && !hotkey.isHandsFree)
        hotkey.configure(.function)

        calls = []
        fn(true)
        try await drain()
        precondition(!key(123))
        fn(false)
        try await Task.sleep(for: settled)
        precondition(calls == ["start", "cancel"], "Fn navigation combinations must cancel rather than submit audio")

        calls = []
        fn(true); fn(false); fn(true); fn(false)
        try await drain()
        hotkey.resetRecordingGesture()
        fn(false)
        try await Task.sleep(for: settled)
        precondition(calls == ["start", "lock"] && !hotkey.isHandsFree, "A manual stop must clear the latch without a delayed second completion")

        calls = []
        hotkey.onPress = { [weak hotkey] in
            calls.append("blocked")
            hotkey?.resetRecordingGesture()
        }
        fn(true); fn(false); fn(true); fn(false)
        try await Task.sleep(for: settled)
        precondition(calls == ["blocked"] && !hotkey.isHandsFree, "A failed or busy start must discard the queued hands-free callback")
        hotkey.onPress = { [weak hotkey] in calls.append("start"); hotkey?.recordingStarted() }

        for reason in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            calls = []
            fn(true); fn(false); fn(true); fn(false)
            try await drain()
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 63, keyDown: false)!
            precondition(!hotkey.handleCGEvent(type: reason, event: event))
            try await drain()
            precondition(calls == ["start", "lock", "cancel"] && !hotkey.isHandsFree, "A disabled event tap must not leave recording locked")
        }
        calls = []
        fn(true); fn(false); fn(true); fn(false)
        try await drain()
        hotkey.stop()
        try await Task.sleep(for: settled)
        precondition(calls == ["start", "lock", "cancel"] && !hotkey.isHandsFree)
        print("Fn hands-free: hold, double-tap lock, one-press stop, Escape, shortcut changes, failed starts, manual stop and event-tap recovery passed")
    }

    static func testEditPreview() async throws {
        let original = "  नमस्ते 👋\r\nSend 42 to old@example.com; see https://example.com/v2?a=1.\n"
        let proposed = "  नमस्ते 👋\r\nPlease send 43 to new@example.com; see https://example.com/v3?a=1.\n"
        let preview = EditPreview(original: original, proposed: proposed, outputMode: .verbatim)
        precondition(preview.originalSegments.map(\.text).joined() == original)
        precondition(preview.proposedSegments.map(\.text).joined() == proposed)
        precondition(preview.valueChanges.count == 6)
        precondition(preview.valueChanges.filter { $0.value.kind == .number }.map { $0.value.text } == ["42", "43"])
        precondition(!preview.allowsApply(acknowledgingValueChanges: false))
        precondition(preview.allowsApply(acknowledgingValueChanges: true))
        precondition(preview.outputMode == .verbatim)

        let ordinary = EditPreview(original: "Hello steady middle goodbye", proposed: "Hi steady middle bye", outputMode: .casual)
        precondition(ordinary.valueChanges.isEmpty)
        precondition(ordinary.allowsApply(acknowledgingValueChanges: false))
        precondition(ordinary.originalSegments.contains { !$0.changed && $0.text.contains("steady middle") })
        precondition(ordinary.originalSegments.filter(\.changed).map(\.text).joined() == "Hellogoodbye")
        precondition(ordinary.proposedSegments.filter(\.changed).map(\.text).joined() == "Hibye")
        for (before, after) in [("", ""), ("unchanged", "unchanged"), ("text", " \n\t")] {
            let blocked = EditPreview(original: before, proposed: after, outputMode: .verbatim)
            precondition(!blocked.allowsApply(acknowledgingValueChanges: true))
        }
        for (before, after) in [("", "new"), ("old", ""), ("👩🏽‍💻 café", "👩🏽‍💻 नमस्ते"), ("```\n  a\n```", "```\n  b\n```"), ("a a a", "a a")] {
            let literal = EditPreview(original: before, proposed: after, outputMode: .verbatim)
            precondition(literal.originalSegments.map(\.text).joined() == before)
            precondition(literal.proposedSegments.map(\.text).joined() == after)
        }
        let repeated = EditPreview(original: "42 then 42", proposed: "42", outputMode: .concise)
        precondition(repeated.valueChanges.count == 1)
        precondition(repeated.valueChanges[0].originalCount == 2 && repeated.valueChanges[0].proposedCount == 1)
        let reordered = EditPreview(original: "10 then 20", proposed: "20 then 10", outputMode: .verbatim)
        precondition(reordered.valueChanges.isEmpty, "Value counts do not establish semantic correctness")
        let hindi = EditPreview(original: "कुल ₹१,२०० और -12.5%", proposed: "कुल ₹१,३०० और -12.5%", outputMode: .cleanSameLanguage)
        precondition(hindi.valueChanges.map { $0.value.text } == ["₹१,२००", "₹१,३००"])
        let added = EditPreview(original: "Contact me", proposed: "Contact me at test@example.com", outputMode: .professional)
        precondition(added.valueChanges.count == 1 && added.valueChanges[0].originalCount == 0)
        precondition(EditPreview.protectedValues(in: "See (www.example.com/path), then x+1@example.org.").map(\.text) == ["www.example.com/path),", "x+1@example.org"])
        let punctuation = EditPreview(original: "See https://example.com/path.", proposed: "See https://example.com/path!", outputMode: .casual)
        precondition(punctuation.valueChanges.count == 2, "URL punctuation can be meaningful and must not be silently stripped")
        let signed = EditPreview(original: "-₹12 and ₹-13", proposed: "₹12 and ₹13", outputMode: .verbatim)
        precondition(signed.valueChanges.count == 4)
        precondition(signed.valueChanges.prefix(2).map { $0.value.text } == ["-₹12", "₹-13"])

        let large = String(repeating: "word ", count: 10_000)
        let passage = EditPreview(original: large + "old 👋 end", proposed: large + "new 👋 end", outputMode: .verbatim)
        precondition(passage.usesPassageHighlight)
        precondition(passage.originalSegments.map(\.text).joined() == passage.original)
        precondition(passage.proposedSegments.map(\.text).joined() == passage.proposed)
        precondition(passage.originalSegments.filter(\.changed).map(\.text).joined() == "old")
        let longWord = String(repeating: "a", count: 50_000)
        precondition(EditPreview.protectedValues(in: longWord).isEmpty, "Long non-email text must scan without backtracking across every suffix")
        let unchanged = EditPreview(original: large, proposed: large, outputMode: .verbatim)
        precondition(unchanged.originalSegments.allSatisfy { !$0.changed })

        precondition(DictationPhase.reviewing.isBusy && DictationPhase.processing.isBusy && DictationPhase.listening.isBusy)
        precondition(!DictationPhase.idle.isBusy && !DictationPhase.pasteSent.isBusy && !DictationPhase.failed("fixture").isBusy)
        let missing = TextSelectionReader.Target(processIdentifier: -1, element: nil, range: nil)
        precondition(!missing.supportsVerifiedReplacement)
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        for range in [nil, CFRange(location: 0, length: 0), CFRange(location: -1, length: 3), CFRange(location: 1, length: Int.max)] as [CFRange?] {
            let unknown = TextSelectionReader.Target(processIdentifier: -1, element: element, range: range)
            precondition(!unknown.supportsVerifiedReplacement)
        }
        let stale = TextSelectionReader.Target(processIdentifier: -1, element: element, range: CFRange(location: 0, length: 3))
        precondition(stale.supportsVerifiedReplacement && !stale.isCurrent)
        do {
            try await TextInserter.insert("new", into: stale, replacing: "old")
            preconditionFailure("A stale target must not dispatch a paste")
        } catch InsertError.targetChanged { }
        print("Edit preview: literal diff, bounded long-text comparison, protected-value acknowledgement, Unicode, and stale-target guards passed")
    }

    static func testAndroidBridge() throws {
        func call(_ payload: [String: Any], bytes: Data = Data()) throws -> [String: Any] {
            let input = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
            let output = input.withCString { input in
                bytes.withUnsafeBytes { raw in
                    chatterkeyCall(input, raw.bindMemory(to: UInt8.self).baseAddress, Int32(bytes.count))
                }
            }
            guard let output else { preconditionFailure("Bridge allocation failed") }
            defer { chatterkeyFree(output) }
            return try JSONSerialization.jsonObject(with: Data(String(cString: output).utf8)) as! [String: Any]
        }
        let catalog = try call(["operation": "catalog"])
        precondition(catalog["ok"] as? Bool == true)
        let choices = catalog["value"] as! [String: Any]
        precondition((choices["providers"] as! [[String: Any]]).count == 2)
        precondition((choices["modes"] as! [[String: Any]]).count == OutputMode.allCases.count)
        let selected = "A👋नमस्ते\u{0}Z: order 42, demo@example.test"
        let proposed = "A👋नमस्ते\u{0}Z: order 43, demo@example.test"
        let audio = Data([0, 1, 2, 255])
        for connection in AIProvider.availableConnections {
            for mode in OutputMode.allCases {
                var settings = ProviderSettings()
                settings.selectProvider(connection)
                settings.outputMode = mode
                let config = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))
                var payload: [String: Any] = ["operation": "request", "settings": config, "credential": "test-credential", "selectedText": selected]
                let bridge = try call(payload, bytes: audio)
                precondition(bridge["ok"] as? Bool == true)
                let value = bridge["value"] as! [String: Any]
                let client = ProviderClient(settings: settings, apiKey: "test-credential", transport: { _ in preconditionFailure("No network allowed") })
                let native = try client.makeAudioRequest(audio: audio, editing: selected)
                precondition(value["url"] as? String == native.url?.absoluteString)
                let body = try JSONSerialization.jsonObject(with: Data((value["body"] as! String).utf8)) as! NSDictionary
                let expected = try JSONSerialization.jsonObject(with: native.httpBody!) as! NSDictionary
                precondition(body == expected, "Android and Mac must use identical request semantics")
                payload["operation"] = "response"
                payload["status"] = 200
                payload.removeValue(forKey: "credential")
                let response = try call(payload, bytes: reply(proposed))
                precondition(response["ok"] as? Bool == true)
                precondition((response["value"] as? [String: Any])?["text"] as? String == proposed)
                precondition((response["value"] as? [String: Any])?["wordCount"] as? Int == UsageAnalytics.wordCount(proposed))
                payload["operation"] = "preview"
                payload["proposed"] = proposed
                let preview = try call(payload)
                let review = preview["value"] as! [String: Any]
                precondition((review["warnings"] as! [[String: Any]]).count == 2)
                precondition(review["hasChanges"] as? Bool == true)
                payload["operation"] = "response"
                payload["status"] = 401
                let rejected = try call(payload, bytes: Data(#"{"error":{"message":"fixture denial"}}"#.utf8))
                precondition(rejected["ok"] as? Bool == false)
            }
        }
        let malformed = try call(["operation": "request", "settings": [:]])
        precondition(malformed["ok"] as? Bool == false)
        let unknown = try call(["operation": "unsupported"])
        precondition(unknown["ok"] as? Bool == false)
        print("Android bridge host fixtures: shared provider/mode requests, Unicode/NUL round trips, protected values and error envelopes passed")
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
                _ = Task { @MainActor in
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
                    _ = Task { @MainActor in
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
        try await Task.sleep(for: GlobalHotkey.functionDoubleTapDelay + .milliseconds(40))
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
            let audio = try await AudioRecorder.readPreparedAudio(at: destination)
            let fileBytes = try Data(contentsOf: destination)
            precondition(audio == fileBytes, "The native adapter changed prepared audio bytes")
            let converted = try AVAudioFile(forReading: destination)
            precondition(converted.fileFormat.sampleRate == 16_000)
            precondition(converted.fileFormat.channelCount == 1)
            precondition(converted.fileFormat.commonFormat == .pcmFormatInt16)
            precondition(abs(converted.length - 32_000) < 20)
            let output = AVAudioPCMBuffer(pcmFormat: converted.processingFormat, frameCapacity: 512)!
            try converted.read(into: output)
            precondition(abs(output.floatChannelData![0][100]) > 0.1, "Conversion lost the audio signal")
            let imported = try await AudioFileImporter.prepare(source)
            precondition(abs(imported.duration - 2) < 0.01 && imported.format == .wav && imported.audio.prefix(4) == Data("RIFF".utf8))
            let sourceBytes = try Data(contentsOf: source)
            let boundedRead = try AudioFileImporter.readAudio(at: source)
            precondition(boundedRead == sourceBytes, "Bounded read changed the source bytes")
            do {
                try AudioRecorder.convertToProviderWAV(from: source, to: directory.appendingPathComponent("limited.wav"), maximumFrames: 1)
                preconditionFailure("Conversion exceeded its bounded duration")
            } catch RecorderError.durationLimitExceeded { }
            if sampleRate == 16_000 {
                let readLimit = directory.appendingPathComponent("read-limit.wav")
                try Data().write(to: readLimit)
                let readHandle = try FileHandle(forWritingTo: readLimit)
                defer { try? readHandle.close() }
                for size in [0, ProviderClient.maximumImportedAudioBytes + 1, ProviderClient.maximumImportedAudioBytes] {
                    try readHandle.truncate(atOffset: UInt64(size))
                    do {
                        let bytes = try AudioFileImporter.readAudio(at: readLimit)
                        precondition(size == ProviderClient.maximumImportedAudioBytes && bytes.count == size)
                    } catch AudioImportError.tooLarge {
                        precondition(size != ProviderClient.maximumImportedAudioBytes, "Exact-limit audio was rejected")
                    }
                }
                let cancelledRead = Task {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return try AudioFileImporter.readAudio(at: source)
                }
                do { _ = try await cancelledRead.value; preconditionFailure("Cancelled import read continued") }
                catch is CancellationError { }
                let overLimit = directory.appendingPathComponent("over-limit.wav")
                var header = Data("RIFF".utf8)
                let dataSize = UInt32(3048 * 32_000)
                func append(_ value: UInt32) {
                    var littleEndian = value.littleEndian
                    withUnsafeBytes(of: &littleEndian) { header.append(contentsOf: $0) }
                }
                append(dataSize + 36)
                header.append(Data("WAVEfmt ".utf8))
                append(16); append(0x0001_0001); append(16_000); append(32_000); append(0x0010_0002)
                header.append(Data("data".utf8)); append(dataSize)
                try header.write(to: overLimit)
                let handle = try FileHandle(forWritingTo: overLimit)
                try handle.truncate(atOffset: UInt64(dataSize) + 44)
                for (index, duration) in [900, 900, 900, 348].enumerated() {
                    for (frame, value) in [(index * 900 * 16_000, (index + 1) * 1000),
                                           ((index * 900 + duration) * 16_000 - 1, (index + 1) * 2000)] {
                        try handle.seek(toOffset: UInt64(44 + frame * 2))
                        var sample = Int16(value).littleEndian
                        try withUnsafeBytes(of: &sample) { try handle.write(contentsOf: Data($0)) }
                    }
                }
                try handle.close()
                // Exercise the actual adapter + model pipeline using a sparse local WAV.
                try await testChunkedImport(overLimit)
                for duration in [1800.0, 1800.25] {
                    let boundary = directory.appendingPathComponent("boundary.wav")
                    var boundaryHeader = header
                    var size = UInt32(duration * 32_000).littleEndian
                    var riffSize = (size + 36).littleEndian
                    withUnsafeBytes(of: &riffSize) { boundaryHeader.replaceSubrange(4..<8, with: $0) }
                    withUnsafeBytes(of: &size) { boundaryHeader.replaceSubrange(40..<44, with: $0) }
                    try boundaryHeader.write(to: boundary)
                    let handle = try FileHandle(forWritingTo: boundary)
                    try handle.truncate(atOffset: UInt64(size) + 44)
                    try handle.close()
                    let prepared = try await AudioFileImporter.prepare(boundary)
                    precondition(prepared.plan.isChunked == (duration > 1800))
                    precondition(duration == 1800 ? !prepared.audio.isEmpty : prepared.chunks.count == 3)
                    if duration > 1800 {
                        let last = try AVAudioFile(forReading: prepared.chunks.last!)
                        precondition(last.length == 4000, "Final partial chunk was padded or omitted")
                    }
                }
                let cancelledPreparation = Task { try await AudioFileImporter.prepare(overLimit) }
                cancelledPreparation.cancel()
                do { _ = try await cancelledPreparation.value; preconditionFailure("Cancelled preparation completed") }
                catch is CancellationError { }
                let mock = MockTransport(body: reply(#"{"transcript":"source text","context":"A memo","output":"- Notes"}"#))
                let model = AudioImportModel(transport: { try await mock.send($0) })
                model.select(source)
                for _ in 0..<500 where model.isBusy { try await Task.sleep(for: .milliseconds(10)) }
                precondition(model.file != nil && model.error == nil)
                model.mode = .notes
                model.generate(settings: ProviderSettings(), apiKey: "test-credential")
                for _ in 0..<500 where model.isBusy { try await Task.sleep(for: .milliseconds(10)) }
                precondition(model.result?.transcript == "source text" && model.resultMode == .notes)
                let sent = await mock.requests
                precondition(sent.count == 1)
                let originalConnection = model.connectionDescription
                var alternateSettings = ProviderSettings()
                alternateSettings.model = "another-model"
                model.generate(settings: alternateSettings, apiKey: "test-credential")
                model.cancel()
                try await Task.sleep(for: .milliseconds(50))
                precondition(model.result?.transcript == "source text" && model.resultMode == .notes,
                             "Cancelling a new generation lost the previous result")
                precondition(model.connectionDescription == originalConnection,
                             "An unfinished generation changed the previous result's provider label")
                model.generate(settings: ProviderSettings(), apiKey: "test-credential")
                model.clear()
                try await Task.sleep(for: .milliseconds(50))
                precondition(model.file == nil && model.result == nil && !model.isBusy, "Cancelled completion repopulated results")
                model.select(source)
                model.clear()
                try await Task.sleep(for: .milliseconds(50))
                precondition(model.file == nil && model.result == nil && !model.isBusy, "Cancelled selection reappeared")
            }
        }

        let missingAudio = directory.appendingPathComponent("missing.wav")
        do {
            _ = try await AudioRecorder.readPreparedAudio(at: missingAudio)
            preconditionFailure("A missing recording must not become empty provider audio")
        } catch let error as CocoaError {
            precondition(error.code == .fileReadNoSuchFile)
        }
        let cancelledRead = Task { @MainActor in
            try await AudioRecorder.readPreparedAudio(at: missingAudio)
        }
        cancelledRead.cancel()
        do { _ = try await cancelledRead.value; preconditionFailure("Cancelled audio read proceeded") }
        catch is CancellationError { }
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
    let responses: [Data]
    let retainLargeBodies: Bool
    let pauseAt: Int?

    init(body: Data, status: Int = 200, errorCode: URLError.Code? = nil, cancel: Bool = false, responses: [Data] = [], retainLargeBodies: Bool = true, pauseAt: Int? = nil) {
        self.body = body
        self.status = status
        self.errorCode = errorCode
        self.cancel = cancel
        self.responses = responses
        self.retainLargeBodies = retainLargeBodies
        self.pauseAt = pauseAt
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var recorded = request
        if !retainLargeBodies && (recorded.httpBody?.count ?? 0) > 1_000_000 { recorded.httpBody = nil }
        requests.append(recorded)
        let index = requests.count - 1
        if requests.count == pauseAt { try await Task.sleep(for: .seconds(60)) }
        if cancel { throw CancellationError() }
        if let errorCode { throw URLError(errorCode) }
        return (index < responses.count ? responses[index] : body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
SWIFT
# Compile the core independently so the harness exercises the real module boundary.
swiftc -swift-version 6 -warnings-as-errors -package-name ChatterKey \
  -emit-library -emit-module -module-name ChatterKeyCore \
  core/Sources/ChatterKeyCore/*.swift -o "$TMP/libChatterKeyCore.dylib" \
  -emit-module-path "$TMP/ChatterKeyCore.swiftmodule"
swiftc -swift-version 6 -warnings-as-errors -package-name ChatterKey \
  -emit-library -emit-module -module-name ChatterKeyAndroidBridge \
  -I "$TMP" -L "$TMP" -lChatterKeyCore -Xlinker -rpath -Xlinker "$TMP" \
  apps/android/bridge/AndroidBridge.swift -o "$TMP/libChatterKeyAndroidBridge.dylib" \
  -emit-module-path "$TMP/ChatterKeyAndroidBridge.swiftmodule"
swiftc -swift-version 6 -warnings-as-errors -package-name ChatterKey \
  -I "$TMP" -L "$TMP" -lChatterKeyCore -lChatterKeyAndroidBridge -Xlinker -rpath -Xlinker "$TMP" \
  apps/macos/Sources/Models.swift \
  apps/macos/Sources/Adapters/{TextInserter,HistoryStore,ClipboardTransaction,TextSelectionReader,GlobalHotkey,AudioRecorder,AudioFileImporter,ProviderTransport}.swift \
  apps/macos/Sources/Services/AudioImportModel.swift \
  apps/macos/Sources/Views/AudioImportText.swift \
  "$TMP/ModelHarness.swift" -o "$TMP/model-tests"
"$TMP/model-tests"
