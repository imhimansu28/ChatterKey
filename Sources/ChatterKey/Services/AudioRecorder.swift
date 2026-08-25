@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

@MainActor
final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private(set) var outputURL: URL?

    var speechRecognitionGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func cleanupTemporaryFiles() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatterKey", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    func requestSpeechRecognitionPermission() async -> Bool {
        if speechRecognitionGranted { return true }
        return await withCheckedContinuation { continuation in
            requestSpeechAuthorization(continuation)
        }
    }

    func start(
        liveTranscription: Bool,
        onPartialTranscript: @escaping @MainActor (String) -> Void
    ) throws {
        stopCapture(removeFile: true)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatterKey", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("dictation-\(UUID().uuidString).wav")

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecorderError.couldNotStart
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let request = makeSpeechRequest(enabled: liveTranscription, onPartialTranscript: onPartialTranscript)

        installAudioTap(on: input, format: format, file: file, speechRequest: request)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            speechTask?.cancel()
            speechTask = nil
            speechRequest = nil
            try? FileManager.default.removeItem(at: url)
            throw RecorderError.couldNotStart
        }

        self.engine = engine
        audioFile = file
        outputURL = url
    }

    func stop() -> URL? {
        let url = outputURL
        stopCapture(removeFile: false)
        return url
    }

    func cancel() {
        stopCapture(removeFile: true)
    }

    private func makeSpeechRequest(
        enabled: Bool,
        onPartialTranscript: @escaping @MainActor (String) -> Void
    ) -> SFSpeechAudioBufferRecognitionRequest? {
        guard enabled,
              speechRecognitionGranted,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN")),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else { return nil }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        speechRequest = request
        speechTask = startSpeechRecognition(
            recognizer: recognizer,
            request: request,
            onPartialTranscript: onPartialTranscript
        )
        return request
    }

    private func stopCapture(removeFile: Bool) {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        speechRequest?.endAudio()
        speechTask?.cancel()
        speechTask = nil
        speechRequest = nil
        audioFile = nil
        engine = nil

        if removeFile, let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        if removeFile { outputURL = nil }
    }
}

nonisolated enum RecorderError: LocalizedError {
    case couldNotStart

    var errorDescription: String? { "Microphone recording could not start." }
}

private func installAudioTap(
    on input: AVAudioInputNode,
    format: AVAudioFormat,
    file: AVAudioFile,
    speechRequest: SFSpeechAudioBufferRecognitionRequest?
) {
    input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
        try? file.write(from: buffer)
        speechRequest?.append(buffer)
    }
}

private func requestSpeechAuthorization(_ continuation: CheckedContinuation<Bool, Never>) {
    SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
    }
}

private func startSpeechRecognition(
    recognizer: SFSpeechRecognizer,
    request: SFSpeechAudioBufferRecognitionRequest,
    onPartialTranscript: @escaping @MainActor (String) -> Void
) -> SFSpeechRecognitionTask {
    recognizer.recognitionTask(with: request) { result, _ in
        guard let text = result?.bestTranscription.formattedString, !text.isEmpty else { return }
        Task { @MainActor in onPartialTranscript(text) }
    }
}
