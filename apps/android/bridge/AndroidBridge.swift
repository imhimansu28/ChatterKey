import ChatterKeyCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private struct AndroidSettings: Decodable, ProcessingSettings {
    var provider: AIProvider
    var model: String
    var systemPrompt: String
    var outputMode: OutputMode
    var smartPolish: Bool
    var spokenCommandsEnabled: Bool
    var personalDictionary: [DictionaryEntry]
    var voiceSnippets: [VoiceSnippet]
    var costRates: CostRates
    var baseURL: String { provider.defaultBaseURL }
}

// One narrow UTF-8/data boundary. It contains no microphone, storage or network effects.
@_cdecl("chatterkey_call")
public func chatterkeyCall(_ input: UnsafePointer<CChar>?, _ bytes: UnsafePointer<UInt8>?, _ count: Int32) -> UnsafeMutablePointer<CChar>? {
    let result: [String: Any]
    do {
        guard let input, count >= 0, count <= 8_000_000 else { throw ProviderError.invalidResponse }
        let data = Data(String(cString: input).utf8)
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let operation = payload["operation"] as? String else { throw ProviderError.invalidResponse }
        result = ["ok": true, "value": try execute(operation, payload, bytes, Int(count))]
    } catch {
        result = ["ok": false, "error": error.localizedDescription]
    }
    guard let encoded = try? JSONSerialization.data(withJSONObject: result),
          let text = String(data: encoded, encoding: .utf8) else { return nil }
    return strdup(text)
}

@_cdecl("chatterkey_free")
public func chatterkeyFree(_ value: UnsafeMutablePointer<CChar>?) { free(value) }

private func execute(_ operation: String, _ payload: [String: Any], _ bytes: UnsafePointer<UInt8>?, _ count: Int) throws -> [String: Any] {
    if operation == "catalog" {
        return [
            "providers": AIProvider.availableConnections.map { ["id": $0.rawValue, "title": $0.title, "model": $0.defaultModel] },
            "modes": OutputMode.allCases.map { ["id": $0.rawValue, "title": $0.title] },
            "defaultPrompt": ProcessingPrompt.defaultSystemPrompt,
            "defaultRates": ["audioPerMillionTokens": CostRates.geminiFlashLite.audioPerMillionTokens,
                             "inputPerMillionTokens": CostRates.geminiFlashLite.inputPerMillionTokens,
                             "outputPerMillionTokens": CostRates.geminiFlashLite.outputPerMillionTokens]
        ]
    }
    guard let settingsObject = payload["settings"] as? [String: Any] else { throw ProviderError.invalidResponse }
    let settings = try JSONDecoder().decode(AndroidSettings.self, from: JSONSerialization.data(withJSONObject: settingsObject))
    let selected = payload["selectedText"] as? String
    guard (selected?.utf16.count ?? 0) <= 50_000 else { throw ProviderError.invalidResponse }
    if operation == "preview" {
        guard let original = selected, let proposed = payload["proposed"] as? String, proposed.utf16.count <= 100_000 else {
            throw ProviderError.invalidResponse
        }
        let preview = EditPreview(original: original, proposed: proposed, outputMode: settings.outputMode)
        return ["hasChanges": preview.hasChanges,
                "before": preview.originalSegments.map { ["text": $0.text, "changed": $0.changed] },
                "after": preview.proposedSegments.map { ["text": $0.text, "changed": $0.changed] },
                "warnings": preview.valueChanges.map { ["kind": $0.value.kind.rawValue, "value": $0.value.text,
                                                        "beforeCount": $0.originalCount, "afterCount": $0.proposedCount] }]
    }
    let client = ProviderClient(settings: settings, apiKey: payload["credential"] as? String ?? "", transport: { _ in
        throw ProviderError.invalidResponse // Android supplies its own explicit transport.
    })
    if operation == "request" {
        guard let bytes, count > 0 else { throw ProviderError.invalidResponse }
        let request = try client.makeAudioRequest(audio: Data(bytes: bytes, count: count), editing: selected)
        return ["url": request.url!.absoluteString, "headers": request.allHTTPHeaderFields ?? [:],
                "body": String(data: request.httpBody!, encoding: .utf8)!, "timeoutSeconds": request.timeoutInterval]
    }
    if operation == "response" {
        guard let bytes, count > 0, let status = payload["status"] as? Int,
              let response = HTTPURLResponse(url: try ProviderEndpointPolicy.baseURL(for: settings), statusCode: status,
                                             httpVersion: nil, headerFields: nil) else { throw ProviderError.invalidResponse }
        let text = try client.finish(data: Data(bytes: bytes, count: count), response: response, editing: selected)
        return ["text": text, "wordCount": UsageAnalytics.wordCount(text), "estimatedCostUSD": UsageAnalytics.estimatedCost(durationSeconds: payload["durationSeconds"] as? Double ?? 0,
                   finalText: text, settings: settings, selectedText: selected)]
    }
    throw ProviderError.invalidResponse
}
