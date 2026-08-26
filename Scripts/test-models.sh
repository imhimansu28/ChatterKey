#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/ModelHarness.swift" <<'SWIFT'
import Foundation

@main
struct ModelHarness {
    static func main() throws {
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

        var translateWithoutCleanup = ProviderSettings()
        translateWithoutCleanup.outputMode = .translateEnglish
        translateWithoutCleanup.smartPolish = false
        precondition(translateWithoutCleanup.requiresLanguageModelProcessing)

        var literalWithoutCleanup = ProviderSettings()
        literalWithoutCleanup.outputMode = .verbatim
        literalWithoutCleanup.smartPolish = false
        precondition(!literalWithoutCleanup.requiresLanguageModelProcessing)

        precondition(TranslationCompliance.containsUntranslatedHindi("Mujhe this report tomorrow chahiye."))
        precondition(TranslationCompliance.containsUntranslatedHindi("The report is ready hai."))
        precondition(TranslationCompliance.containsUntranslatedHindi("यह report tomorrow चाहिए."))
        precondition(!TranslationCompliance.containsUntranslatedHindi("The MATLAB report is ready."))
        precondition(!TranslationCompliance.containsUntranslatedHindi("The report is ready for review."))

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

        print("model and endpoint safety tests passed")
    }
}
SWIFT
swiftc Sources/ChatterKey/Models.swift Sources/ChatterKey/Services/VoiceTextProcessor.swift Sources/ChatterKey/Services/ProviderEndpointPolicy.swift Sources/ChatterKey/Services/TranslationCompliance.swift "$TMP/ModelHarness.swift" -o "$TMP/model-tests"
"$TMP/model-tests"
