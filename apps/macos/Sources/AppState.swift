import ChatterKeyCore
import AppKit
import AVFoundation
import Foundation

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: DictationPhase = .idle
    @Published private(set) var editPreview: EditPreview?
    @Published private(set) var editPreviewMessage: String?
    @Published var lastTranscript = ""
    @Published var liveTranscript = ""
    @Published var magicEditActive = false
    @Published private(set) var handsFreeRecording = false
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
        hotkey.onPress = { [weak self] in
            guard let self else { return }
            if self.phase == .listening { self.finishDictation() } else { self.beginDictation() }
        }
        hotkey.onRelease = { [weak self] in self?.finishDictation() }
        hotkey.onCancel = { [weak self] in self?.cancel() }
        hotkey.onHandsFree = { [weak self] in
            guard let self else { return }
            guard self.phase == .listening else {
                self.hotkey.resetRecordingGesture()
                return
            }
            self.handsFreeRecording = true
        }
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
                    try await ProviderClient(settings: currentSettings, apiKey: key, transport: ProviderTransport.send).testConnection()
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
        guard !phase.isBusy else {
            hotkey.resetRecordingGesture()
            return
        }
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
            handsFreeRecording = false
            hotkey.recordingStarted()
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
        hotkey.resetRecordingGesture()
        handsFreeRecording = false
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

    var canApplyEditPreview: Bool {
        phase == .reviewing && editPreview != nil && insertionTarget?.supportsVerifiedReplacement == true
    }

    func showEditPreview() {
        guard phase == .reviewing else { return }
        EditPreviewWindowController.shared.show(appState: self)
    }

    func discardEditPreview() {
        guard phase == .reviewing, editPreview != nil else { return }
        cancel()
    }

    func copyEditPreview() {
        guard phase == .reviewing, let preview = editPreview else { return }
        guard copy(preview.proposed) else {
            editPreviewMessage = "The clipboard could not be updated. Your edit is still here. Try Copy & Close again, or select and copy the proposed text manually."
            showEditPreview()
            return
        }
        lastTranscript = preview.proposed
        addHistory(preview.proposed, mode: preview.outputMode)
        cancel()
    }

    func applyEditPreview(acknowledgingValueChanges: Bool) {
        guard canApplyEditPreview, let preview = editPreview, let target = insertionTarget,
              preview.allowsApply(acknowledgingValueChanges: acknowledgingValueChanges) else { return }
        phase = .processing
        EditPreviewWindowController.shared.hide()
        processingTask?.cancel()
        processingTask = Task {
            do {
                try Task.checkCancellation()
                guard let app = NSRunningApplication(processIdentifier: target.processIdentifier),
                      !app.isTerminated, app != NSRunningApplication.current,
                      app.activate(options: [.activateAllWindows]) else { throw InsertError.targetChanged }
                // Activation is asynchronous. Never take a new target after review;
                // the original AX field, range, and text must still match.
                try await Task.sleep(for: .milliseconds(200))
                try await TextInserter.insert(preview.proposed, into: target, replacing: preview.original)
                try Task.checkCancellation()
                editPreview = nil
                editPreviewMessage = nil
                try await finishPaste(preview.proposed, mode: preview.outputMode)
            } catch {
                guard !Task.isCancelled else { return }
                insertionTarget = nil
                editPreviewMessage = "\(error.localizedDescription) Your edit has not been applied. Use Copy & Close, then select the intended text and paste manually. No new model request is needed."
                phase = .reviewing
                showEditPreview()
            }
        }
    }

    func cancel() {
        hotkey.resetRecordingGesture()
        handsFreeRecording = false
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
        editPreview = nil
        editPreviewMessage = nil
        EditPreviewWindowController.shared.hide()
        OverlayController.shared.hide()
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        copy(lastTranscript)
    }

    @discardableResult
    func copy(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }

    func insert(_ item: DictationHistoryItem) {
        guard !phase.isBusy else { return }
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
                let audio = try await AudioRecorder.readPreparedAudio(at: url)
                let final = try await ProviderClient(settings: currentSettings, apiKey: key, transport: ProviderTransport.send).process(
                    audio: audio,
                    editing: editingText
                )
                try Task.checkCancellation()
                addUsage(
                    finalText: final,
                    spokenText: spokenDraft,
                    audioURL: url,
                    settings: currentSettings,
                    selectedText: editingText
                )
                if let editingText {
                    let preview = await Task.detached(priority: .userInitiated) {
                        EditPreview(original: editingText, proposed: final, outputMode: currentSettings.outputMode)
                    }.value
                    try Task.checkCancellation()
                    editPreview = preview
                    if let target, target.supportsVerifiedReplacement {
                        editPreviewMessage = target.isCurrent ? nil
                            : "Focus moved while processing. Apply will return to the original app and recheck the selected text before replacing it. If the selection changed, use Copy & Close."
                    } else {
                        insertionTarget = nil
                        editPreviewMessage = "The selected text was captured, but its editable selection range could not be verified through Accessibility. This does not mean you changed the selection. Use Copy & Close and paste into the intended selection manually."
                    }
                    removeRetryAudio()
                    self.selectionTask = nil
                    liveTranscript = ""
                    phase = .reviewing
                    OverlayController.shared.hide()
                    showEditPreview()
                    return
                }
                lastTranscript = final
                do {
                    guard let target else { throw InsertError.targetChanged }
                    try await TextInserter.insert(final, into: target)
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
                try await finishPaste(final, mode: currentSettings.outputMode)
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

    private func finishPaste(_ text: String, mode: OutputMode) async throws {
        lastTranscript = text
        addHistory(text, mode: mode)
        removeRetryAudio()
        selectionTask = nil
        insertionTarget = nil
        liveTranscript = ""
        magicEditActive = false
        phase = .pasteSent
        OverlayController.shared.show(appState: self)
        try await Task.sleep(for: .milliseconds(900))
        if phase == .pasteSent {
            phase = .idle
            OverlayController.shared.hide()
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
                title: "Recording shortcut",
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
        hotkey.resetRecordingGesture()
        handsFreeRecording = false
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
