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
    private var retryAudioURL: URL?
    private var selectedTextForEdit: String?
    private var apiKeyCache: [AIProvider: String] = [:]
    private var loadedAPIKeyProviders: Set<AIProvider> = []

    private static let onboardingKey = "onboarding-complete-v2"

    private init() {
        let loadedSettings = ProviderSettings.load()
        settings = loadedSettings
        history = loadedSettings.historyEnabled
            ? HistoryStore.load(retentionDays: loadedSettings.historyRetentionDays)
            : []
        onboardingComplete = UserDefaults.standard.bool(forKey: Self.onboardingKey)

        hotkey.configure(loadedSettings.hotkeyShortcut)
        hotkey.onPress = { [weak self] in self?.beginDictation() }
        hotkey.onRelease = { [weak self] in self?.finishDictation() }
        hotkey.onCancel = { [weak self] in self?.cancel() }
    }

    var hasAPIKey: Bool { !apiKey(for: settings.provider).isEmpty }
    var setupComplete: Bool { accessibilityGranted && microphoneGranted && hotkeyReady && hasAPIKey }
    var canRetry: Bool { retryAudioURL != nil && phase != .processing }

    func apiKey(for provider: AIProvider) -> String {
        if loadedAPIKeyProviders.contains(provider) {
            return apiKeyCache[provider] ?? ""
        }
        let value = KeychainStore.read(account: provider.rawValue)
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
            diagnostics = localDiagnostics() + [result]
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
        removeRetryAudio()
        liveTranscript = ""
        selectedTextForEdit = TextSelectionReader.selectedText()
        magicEditActive = selectedTextForEdit != nil
        do {
            try recorder.start(liveTranscription: settings.liveTranscriptionEnabled) { [weak self] text in
                guard let self, self.phase == .listening else { return }
                self.liveTranscript = text
            }
            phase = .listening
            OverlayController.shared.show(appState: self)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func finishDictation() {
        guard phase == .listening, let url = recorder.stop() else { return }
        retryAudioURL = url
        processAudio(at: url)
    }

    func retryLastDictation() {
        guard let retryAudioURL else { return }
        processAudio(at: retryAudioURL)
    }

    func cancel() {
        processingTask?.cancel()
        recorder.cancel()
        removeRetryAudio()
        phase = .idle
        liveTranscript = ""
        magicEditActive = false
        selectedTextForEdit = nil
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
        do {
            try TextInserter.insert(item.text)
            lastTranscript = item.text
        } catch {
            copy(item.text)
            fail("Automatic paste failed. The transcript was copied to your clipboard.")
        }
    }

    func clearHistory() {
        history = []
        HistoryStore.clear()
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

    private func processAudio(at url: URL) {
        phase = .processing
        OverlayController.shared.show(appState: self)
        let currentSettings = settings
        let key = apiKey(for: currentSettings.provider)
        let editingText = selectedTextForEdit

        processingTask = Task {
            do {
                let final = try await ProviderClient(settings: currentSettings, apiKey: key).process(
                    audioURL: url,
                    editing: editingText
                )
                try Task.checkCancellation()
                lastTranscript = final
                do {
                    try TextInserter.insert(final)
                } catch {
                    copy(final)
                    addHistory(final, mode: currentSettings.outputMode)
                    removeRetryAudio()
                    fail("Automatic paste failed. The transcript was copied to your clipboard.")
                    return
                }
                addHistory(final, mode: currentSettings.outputMode)
                phase = .inserted
                removeRetryAudio()
                try? await Task.sleep(for: .milliseconds(900))
                if phase == .inserted {
                    phase = .idle
                    liveTranscript = ""
                    magicEditActive = false
                    selectedTextForEdit = nil
                    OverlayController.shared.hide()
                }
            } catch is CancellationError {
                removeRetryAudio()
            } catch {
                // Keep the temporary audio for an explicit Retry. It is removed
                // on success, cancellation, a new recording, or next launch.
                fail(error.localizedDescription)
            }
        }
    }

    private func addHistory(_ text: String, mode: OutputMode) {
        guard settings.historyEnabled else { return }
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
    }
}
