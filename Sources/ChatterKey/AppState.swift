import AppKit
import AVFoundation
import Foundation

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: DictationPhase = .idle
    @Published var lastTranscript = ""
    @Published var liveTranscript = ""
    @Published var magicEditActive = false
    @Published var settings: ProviderSettings
    @Published var history: [DictationHistoryItem]
    @Published var usageRecords: [UsageRecord]
    @Published var diagnostics: [DiagnosticItem] = []
    @Published var diagnosticsRunning = false
    @Published var accessibilityGranted = false
    @Published var microphoneGranted = false
    @Published var speechRecognitionGranted = false
    @Published var hotkeyReady = false
    @Published var onboardingComplete: Bool

    let recorder = AudioRecorder()
    let hotkey = GlobalHotkey()
    private var processingTask: Task<Void, Never>?
    private var failureDismissTask: Task<Void, Never>?
    private var retryAudioURL: URL?
    private var selectionTask: Task<String?, Error>?
    private var insertionTarget: TextSelectionReader.Target?
    private var apiKeyCache: [AIProvider: String] = [:]
    private var loadedAPIKeyProviders: Set<AIProvider> = []

    private static let onboardingKey = "onboarding-complete-v2"

    private init() {
        let loadedSettings = ProviderSettings.load()
        settings = loadedSettings
        history = loadedSettings.historyEnabled
            ? HistoryStore.load(retentionDays: loadedSettings.historyRetentionDays)
            : []
        usageRecords = UsageStore.load()
        onboardingComplete = UserDefaults.standard.bool(forKey: Self.onboardingKey)

        hotkey.configure(loadedSettings.hotkeyShortcut)
        hotkey.onPress = { [weak self] in self?.beginDictation() }
        hotkey.onRelease = { [weak self] in self?.finishDictation() }
        hotkey.onCancel = { [weak self] in self?.cancel() }
    }

    var hasAPIKey: Bool { !apiKey(for: settings.provider).isEmpty }
    var setupComplete: Bool { accessibilityGranted && microphoneGranted && hotkeyReady && hasAPIKey }
    var canRetry: Bool {
        if case .failed = phase { return retryAudioURL != nil }
        return false
    }

    func apiKey(for provider: AIProvider) -> String {
        if loadedAPIKeyProviders.contains(provider) {
            return apiKeyCache[provider] ?? ""
        }
        let value = KeychainStore.read(account: provider.rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
        loadedAPIKeyProviders.insert(provider)
        apiKeyCache[provider] = value
        return value
    }

    func start() {
        recorder.cleanupTemporaryFiles()
        hotkey.configure(settings.hotkeyShortcut)
        refreshPermissions()
        if settings.liveTranscriptionEnabled && !speechRecognitionGranted {
            requestSpeechRecognitionPermission()
        }
    }

    func refreshPermissions() {
        accessibilityGranted = hotkey.isAccessibilityGranted
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechRecognitionGranted = recorder.speechRecognitionGranted
        hotkeyReady = hotkey.start()
    }

    func requestPermissions() {
        hotkey.requestAccessibility()
        Task {
            _ = await recorder.requestPermission()
            if settings.liveTranscriptionEnabled {
                _ = await recorder.requestSpeechRecognitionPermission()
            }
            for _ in 0..<30 {
                refreshPermissions()
                if accessibilityGranted && microphoneGranted { break }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func requestSpeechRecognitionPermission() {
        Task {
            _ = await recorder.requestSpeechRecognitionPermission()
            refreshPermissions()
        }
    }

    func runDiagnostics() {
        guard !diagnosticsRunning else { return }
        diagnosticsRunning = true
        refreshPermissions()
        diagnostics = localDiagnostics() + [
            DiagnosticItem(id: "provider", title: "Provider connection", state: .checking, detail: "Testing…")
        ]

        let currentSettings = settings
        let key = apiKey(for: currentSettings.provider)
        Task {
            let result: DiagnosticItem
            if key.isEmpty {
                result = DiagnosticItem(id: "provider", title: "Provider connection", state: .failed, detail: "API key is missing")
            } else {
                do {
                    try await ProviderClient(settings: currentSettings, apiKey: key).testConnection()
                    result = DiagnosticItem(id: "provider", title: "Provider connection", state: .passed, detail: "Connected")
                } catch {
                    result = DiagnosticItem(id: "provider", title: "Provider connection", state: .failed, detail: error.localizedDescription)
                }
            }
            if settings.provider == currentSettings.provider && apiKey(for: currentSettings.provider) == key {
                diagnostics = localDiagnostics() + [result]
            } else {
                diagnostics = localDiagnostics() + [
                    DiagnosticItem(id: "provider", title: "Provider connection", state: .failed, detail: "Connection changed. Run diagnostics again.")
                ]
            }
            diagnosticsRunning = false
        }
    }

    func beginDictation() {
        guard phase != .listening && phase != .processing else { return }
        refreshPermissions()
        guard accessibilityGranted else {
            requestPermissions()
            fail("Enable Accessibility access, then press Refresh.")
            return
        }
        guard microphoneGranted else {
            requestPermissions()
            fail("Allow microphone access, then try again.")
            return
        }
        guard hasAPIKey else {
            fail("Add a provider API key in Settings.")
            return
        }

        processingTask?.cancel()
        failureDismissTask?.cancel()
        selectionTask?.cancel()
        removeRetryAudio()
        liveTranscript = ""
        magicEditActive = false
        insertionTarget = TextSelectionReader.target()
        do {
            try recorder.start(liveTranscription: settings.liveTranscriptionEnabled) { [weak self] text in
                guard let self, self.phase == .listening else { return }
                self.liveTranscript = text
            }
            phase = .listening
            let target = insertionTarget
            selectionTask = Task { [weak self] in
                guard let target else { return nil }
                let text = try await TextSelectionReader.selectedText(in: target)
                try Task.checkCancellation()
                self?.magicEditActive = text != nil
                return text
            }
            OverlayController.shared.show(appState: self)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func finishDictation() {
        guard phase == .listening else { return }
        guard let url = recorder.stop() else {
            selectionTask?.cancel()
            fail("The recording could not be prepared for transcription. Please retry.")
            return
        }
        retryAudioURL = url
        processAudio(at: url, spokenDraft: liveTranscript)
    }

    func retryLastDictation() {
        guard canRetry, let retryAudioURL else { return }
        processAudio(at: retryAudioURL, spokenDraft: liveTranscript)
    }

    func cancel() {
        processingTask?.cancel()
        failureDismissTask?.cancel()
        selectionTask?.cancel()
        selectionTask = nil
        recorder.cancel()
        removeRetryAudio()
        phase = .idle
        liveTranscript = ""
        magicEditActive = false
        insertionTarget = nil
        OverlayController.shared.hide()
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        copy(lastTranscript)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func insert(_ item: DictationHistoryItem) {
        guard phase != .listening && phase != .processing else { return }
        guard let target = TextSelectionReader.target() else {
            copy(item.text)
            fail("No target app is focused. The transcript was copied to your clipboard.")
            return
        }
        processingTask?.cancel()
        selectionTask?.cancel()
        selectionTask = nil
        insertionTarget = nil
        removeRetryAudio()
        phase = .processing
        processingTask = Task {
            do {
                try await TextInserter.insert(item.text, into: target)
                try Task.checkCancellation()
                lastTranscript = item.text
                phase = .idle
            } catch {
                guard !Task.isCancelled else { return }
                copy(item.text)
                fail("\(error.localizedDescription) The transcript was copied to your clipboard.")
            }
        }
    }

    func refreshHistory() {
        history = settings.historyEnabled
            ? HistoryStore.load(retentionDays: settings.historyRetentionDays)
            : []
    }

    func clearHistory() {
        history = []
        HistoryStore.clear()
    }

    func clearUsage() {
        usageRecords = []
        UsageStore.clear()
    }

    func setOutputMode(_ mode: OutputMode) {
        settings.outputMode = mode
        settings.save()
    }

    func completeOnboarding() {
        onboardingComplete = true
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
    }

    func resetOnboarding() {
        onboardingComplete = false
        UserDefaults.standard.set(false, forKey: Self.onboardingKey)
        OnboardingWindowController.shared.show(appState: self)
    }

    func saveSettings(_ newValue: ProviderSettings, apiKey: String) throws {
        var newValue = newValue
        try newValue.validate()
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = newValue.provider
        let previousValue = self.apiKey(for: provider)
        if apiKey.isEmpty {
            if !previousValue.isEmpty { try KeychainStore.delete(account: provider.rawValue) }
        } else if apiKey != previousValue {
            try KeychainStore.save(apiKey, account: provider.rawValue)
        }

        loadedAPIKeyProviders.insert(provider)
        apiKeyCache[provider] = apiKey
        settings = newValue
        settings.save()
        hotkey.configure(newValue.hotkeyShortcut)

        if newValue.historyEnabled {
            history = HistoryStore.load(retentionDays: newValue.historyRetentionDays)
        } else {
            clearHistory()
        }
        refreshPermissions()
        if newValue.liveTranscriptionEnabled && !speechRecognitionGranted {
            requestSpeechRecognitionPermission()
        }
    }

    private func processAudio(at url: URL, spokenDraft: String) {
        phase = .processing
        OverlayController.shared.show(appState: self)
        let currentSettings = settings
        let key = apiKey(for: currentSettings.provider)
        let selectionTask = selectionTask
        let target = insertionTarget
        processingTask?.cancel()
        processingTask = Task {
            do {
                let editingText = try await selectionTask?.value
                try Task.checkCancellation()
                let final = try await ProviderClient(settings: currentSettings, apiKey: key).process(
                    audioURL: url,
                    editing: editingText
                )
                try Task.checkCancellation()
                lastTranscript = final
                addUsage(
                    finalText: final,
                    spokenText: spokenDraft,
                    audioURL: url,
                    settings: currentSettings,
                    selectedText: editingText
                )
                do {
                    guard let target else { throw InsertError.targetChanged }
                    try await TextInserter.insert(final, into: target, replacing: editingText)
                    try Task.checkCancellation()
                } catch {
                    guard !Task.isCancelled else { return }
                    copy(final)
                    addHistory(final, mode: currentSettings.outputMode)
                    removeRetryAudio()
                    self.selectionTask = nil
                    magicEditActive = false
                    fail("\(error.localizedDescription) The transcript was copied to your clipboard.")
                    return
                }
                addHistory(final, mode: currentSettings.outputMode)
                phase = .pasteSent
                removeRetryAudio()
                try await Task.sleep(for: .milliseconds(900))
                if phase == .pasteSent {
                    phase = .idle
                    liveTranscript = ""
                    magicEditActive = false
                    self.selectionTask = nil
                    insertionTarget = nil
                    OverlayController.shared.hide()
                }
            } catch {
                // Cancellation cleanup belongs to cancel/new-recording, not an
                // old task that could otherwise delete the next attempt's audio.
                guard !Task.isCancelled else { return }
                if error is SelectionError { removeRetryAudio() }
                // Provider failures retain audio for explicit Retry; local
                // selection failures require a new recording and selection.
                fail(error.localizedDescription)
            }
        }
    }

    private func addUsage(
        finalText: String,
        spokenText: String,
        audioURL: URL,
        settings: ProviderSettings,
        selectedText: String?
    ) {
        let source = spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? finalText : spokenText
        let duration: Double
        if let file = try? AVAudioFile(forReading: audioURL), file.processingFormat.sampleRate > 0 {
            duration = Double(file.length) / file.processingFormat.sampleRate
        } else {
            duration = 0
        }
        let record = UsageRecord(
            createdAt: Date(),
            provider: settings.provider,
            model: settings.model,
            wordCount: UsageAnalytics.wordCount(source),
            audioDurationSeconds: duration,
            estimatedCostUSD: UsageAnalytics.estimatedCost(
                durationSeconds: duration,
                finalText: finalText,
                settings: settings,
                selectedText: selectedText
            ),
            suggestions: UsageAnalytics.suggestions(for: source)
        )
        usageRecords.insert(record, at: 0)
        usageRecords = Array(usageRecords.prefix(1_000))
        UsageStore.save(usageRecords)
    }

    private func addHistory(_ text: String, mode: OutputMode) {
        guard settings.historyEnabled else { return }
        history = HistoryStore.pruned(history, retentionDays: settings.historyRetentionDays)
        history.insert(DictationHistoryItem(text: text, createdAt: Date(), outputMode: mode), at: 0)
        history = Array(history.prefix(50))
        HistoryStore.save(history)
    }

    private func removeRetryAudio() {
        if let retryAudioURL { try? FileManager.default.removeItem(at: retryAudioURL) }
        retryAudioURL = nil
    }

    private func localDiagnostics() -> [DiagnosticItem] {
        [
            DiagnosticItem(
                id: "microphone",
                title: "Microphone",
                state: microphoneGranted ? .passed : .failed,
                detail: microphoneGranted ? "Allowed" : "Permission required"
            ),
            DiagnosticItem(
                id: "accessibility",
                title: "Accessibility",
                state: accessibilityGranted ? .passed : .failed,
                detail: accessibilityGranted ? "Allowed" : "Permission required"
            ),
            DiagnosticItem(
                id: "hotkey",
                title: "Push-to-talk shortcut",
                state: hotkeyReady ? .passed : .failed,
                detail: hotkeyReady ? settings.hotkeyShortcut.title : "Unavailable"
            ),
            DiagnosticItem(
                id: "key",
                title: "Provider API key",
                state: hasAPIKey ? .passed : .failed,
                detail: hasAPIKey ? "Stored in Keychain" : "Missing"
            )
        ] + (settings.liveTranscriptionEnabled ? [
            DiagnosticItem(
                id: "speech",
                title: "Live transcription preview",
                state: speechRecognitionGranted ? .passed : .failed,
                detail: speechRecognitionGranted ? "On-device preview allowed" : "Speech Recognition permission required"
            )
        ] : [])
    }

    private func fail(_ message: String) {
        phase = .failed(message)
        OverlayController.shared.show(appState: self)

        failureDismissTask?.cancel()
        failureDismissTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, self.phase == .failed(message) else { return }
            OverlayController.shared.hide()
        }
    }
}
