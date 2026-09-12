@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

@MainActor
final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private var captureURL: URL?
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
        let identifier = UUID().uuidString
        let captureURL = directory.appendingPathComponent("capture-\(identifier).caf")
        let outputURL = directory.appendingPathComponent("dictation-\(identifier).wav")

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecorderError.couldNotStart
        }

        let file = try AVAudioFile(forWriting: captureURL, settings: format.settings)
        let request = makeSpeechRequest(enabled: liveTranscription) { [weak self] text in
            guard self?.captureURL == captureURL else { return }
            onPartialTranscript(text)
        }

        installAudioTap(on: input, format: format, file: file, speechRequest: request)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            speechTask?.cancel()
            speechTask = nil
            speechRequest = nil
            try? FileManager.default.removeItem(at: captureURL)
            throw RecorderError.couldNotStart
        }

        self.engine = engine
        audioFile = file
        self.captureURL = captureURL
        self.outputURL = outputURL
    }

    func stop() -> URL? {
        guard let captureURL, let outputURL else { return nil }
        stopCapture(removeFile: false)

        do {
            try Self.convertToProviderWAV(from: captureURL, to: outputURL)
            try? FileManager.default.removeItem(at: captureURL)
            self.captureURL = nil
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: captureURL)
            try? FileManager.default.removeItem(at: outputURL)
            self.captureURL = nil
            self.outputURL = nil
            return nil
        }
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

        if removeFile {
            if let captureURL { try? FileManager.default.removeItem(at: captureURL) }
            if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
            captureURL = nil
            outputURL = nil
        }
    }

    nonisolated static func convertToProviderWAV(from sourceURL: URL, to destinationURL: URL) throws {
        let inputFile = try AVAudioFile(forReading: sourceURL)
        guard inputFile.length > 0,
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFile.processingFormat, to: outputFormat),
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: 8_192),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4_096) else {
            throw RecorderError.conversionFailed
        }
        let outputFile = try AVAudioFile(
            forWriting: destinationURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        let input = AudioConversionInputState(file: inputFile, buffer: inputBuffer)
        while true {
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { count, inputStatus in
                guard input.file.framePosition < input.file.length else {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try input.file.read(into: input.buffer, frameCount: min(count, input.buffer.frameCapacity))
                    inputStatus.pointee = input.buffer.frameLength == 0 ? .endOfStream : .haveData
                    return input.buffer.frameLength == 0 ? nil : input.buffer
                } catch {
                    input.error = error
                    inputStatus.pointee = .endOfStream
                    return nil
                }
            }
            if let error = input.error ?? error { throw error }
            guard status != .error else { throw RecorderError.conversionFailed }
            if outputBuffer.frameLength > 0 { try outputFile.write(from: outputBuffer) }
            if status == .endOfStream { break }
            guard outputBuffer.frameLength > 0 else { throw RecorderError.conversionFailed }
        }
        guard outputFile.length > 0 else { throw RecorderError.conversionFailed }
    }
}

nonisolated enum RecorderError: LocalizedError {
    case couldNotStart
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .couldNotStart: "Microphone recording could not start."
        case .conversionFailed: "The recording could not be prepared for transcription."
        }
    }
}

// AVAudioConverter invokes its input block synchronously; each conversion
// owns these buffers, so they are never shared between concurrent calls.
private final class AudioConversionInputState: @unchecked Sendable {
    let file: AVAudioFile
    let buffer: AVAudioPCMBuffer
    var error: Error?

    init(file: AVAudioFile, buffer: AVAudioPCMBuffer) {
        self.file = file
        self.buffer = buffer
    }
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
