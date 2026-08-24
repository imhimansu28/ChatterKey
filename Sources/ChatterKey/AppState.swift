import AppKit
import AVFoundation
import Foundation

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: DictationPhase = .idle
    @Published var lastTranscript = ""
    @Published var settings = ProviderSettings.load()
    @Published var accessibilityGranted = false
    @Published var microphoneGranted = false
    @Published var hotkeyReady = false

    let recorder = AudioRecorder()
    let hotkey = GlobalHotkey()
    private var processingTask: Task<Void, Never>?

    private init() {
        hotkey.onPress = { [weak self] in self?.beginDictation() }
        hotkey.onRelease = { [weak self] in self?.finishDictation() }
        hotkey.onCancel = { [weak self] in self?.cancel() }
    }

    var hasAPIKey: Bool {
        !KeychainStore.read(account: settings.provider.rawValue).isEmpty
    }

    var setupComplete: Bool {
        accessibilityGranted && microphoneGranted && hotkeyReady && hasAPIKey
    }

    func start() {
        recorder.cleanupTemporaryFiles()
        refreshPermissions()
    }

    func refreshPermissions() {
        accessibilityGranted = hotkey.isAccessibilityGranted
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        // Install both the event tap and NSEvent fallback. Accessibility is
        // still required for reliable global capture and automatic paste.
        hotkeyReady = hotkey.start()
    }

    func requestPermissions() {
        hotkey.requestAccessibility()
        Task {
            _ = await recorder.requestPermission()
            for _ in 0..<30 {
                refreshPermissions()
                if accessibilityGranted && microphoneGranted { break }
                try? await Task.sleep(for: .seconds(1))
            }
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
        do {
            try recorder.start()
            phase = .listening
            OverlayController.shared.show(appState: self)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func finishDictation() {
        guard phase == .listening, let url = recorder.stop() else { return }
        phase = .processing
        let settings = self.settings
        let key = KeychainStore.read(account: settings.provider.rawValue)

        processingTask = Task {
            do {
                let client = ProviderClient(settings: settings, apiKey: key)
                let final = try await client.process(audioURL: url)
                try Task.checkCancellation()
                lastTranscript = final
                try TextInserter.insert(final)
                phase = .inserted
                try? FileManager.default.removeItem(at: url)
                try? await Task.sleep(for: .milliseconds(900))
                if phase == .inserted {
                    phase = .idle
                    OverlayController.shared.hide()
                }
            } catch is CancellationError {
                recorder.cancel()
            } catch {
                try? FileManager.default.removeItem(at: url)
                fail(error.localizedDescription)
            }
        }
    }

    func cancel() {
        processingTask?.cancel()
        recorder.cancel()
        phase = .idle
        OverlayController.shared.hide()
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
    }

    func saveSettings(_ newValue: ProviderSettings, apiKey: String) throws {
        settings = newValue
        settings.save()
        if apiKey.isEmpty {
            KeychainStore.delete(account: newValue.provider.rawValue)
        } else {
            try KeychainStore.save(apiKey, account: newValue.provider.rawValue)
        }
        refreshPermissions()
    }

    private func fail(_ message: String) {
        phase = .failed(message)
        OverlayController.shared.show(appState: self)
    }
}
