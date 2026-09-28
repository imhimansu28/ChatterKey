import ChatterKeyCore
import Combine
import Foundation

@MainActor
final class AudioImportModel: ObservableObject {
    enum Phase { case idle, preparing, processing }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var file: ImportedAudioFile?
    @Published private(set) var result: AudioImportResult?
    @Published private(set) var resultMode: AudioImportMode?
    @Published private(set) var error: String?
    @Published private(set) var connectionDescription = ""
    @Published private(set) var progress = ""
    @Published private(set) var completedChunks = 0
    @Published var mode: AudioImportMode = .rawTranscript

    private var task: Task<Void, Never>?
    private var attempt = UUID()
    private var checkpoint: AudioImportCheckpoint?
    private var chunkSettings: ProviderSettings?
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await ProviderTransport.send($0, maximumResponseBytes: AudioImportPlan.maximumResponseBytes) }) {
        self.transport = transport
    }

    var isBusy: Bool { phase != .idle }
    var requiresDiscardConfirmation: Bool { isBusy || result != nil || completedChunks > 0 }

    var requestDisclosure: String {
        guard let file else { return "Generate sends audio to your provider. Fees apply." }
        guard file.plan.isChunked else { return "1 audio request per Generate/Retry. Provider fees apply." }
        let remaining = file.plan.durations.count - completedChunks
        let extra = mode == .rawTranscript ? 0 : 1
        return "\(remaining) audio transcription requests + \(extra) final text request = \(remaining + extra) requests. \(completedChunks)/\(file.plan.durations.count) chunks retained. Same model/provider; fees apply."
    }

    func select(_ url: URL) {
        clear()
        let token = attempt
        phase = .preparing
        progress = "Preparing audio locally; nothing is being uploaded."
        let previous = task
        task = Task { [weak self] in
            do {
                await previous?.value
                try Task.checkCancellation()
                let file = try await AudioFileImporter.prepare(url)
                try Task.checkCancellation()
                guard let self, self.attempt == token else { return }
                self.file = file
                self.checkpoint = file.plan.isChunked ? AudioImportCheckpoint(plan: file.plan) : nil
                self.progress = ""
                self.phase = .idle
                self.task = nil
            } catch {
                self?.completeFailure(error, attempt: token)
            }
        }
    }

    func generate(settings: ProviderSettings, apiKey: String) {
        guard !isBusy, let file else { return }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "Add your provider API key in Settings before generating. No audio was sent."
            return
        }
        if file.plan.isChunked, let saved = chunkSettings,
           saved.provider != settings.provider || saved.model != settings.model || saved.baseURL != settings.baseURL {
            error = "This import is pinned to \(saved.provider.title) · \(saved.model). Restore that connection to resume, or Clear and select the file again to start with a different model. No request was sent."
            return
        }
        if file.plan.isChunked && chunkSettings == nil { chunkSettings = settings }
        error = nil
        phase = .processing
        let token = UUID()
        attempt = token
        let selectedMode = mode
        let connection = "\(settings.provider.title) · \(settings.model)"
        let client = ProviderClient(settings: chunkSettings ?? settings, apiKey: apiKey, transport: transport)
        let previous = task
        progress = "Processing one audio request…"
        task = Task { [weak self] in
            do {
                await previous?.value
                try Task.checkCancellation()
                let result: AudioImportResult
                if file.plan.isChunked {
                    guard let self, self.attempt == token else { return }
                    while self.completedChunks < file.chunks.count {
                        try Task.checkCancellation()
                        let index = self.completedChunks
                        self.progress = "Transcribing chunk \(index + 1) of \(file.chunks.count) · \(index) completed"
                        let chunk = try await Self.runWorker {
                            let audio = try AudioFileImporter.readAudio(at: file.chunks[index])
                            return try await client.transcribeImportedChunk(audio)
                        }
                        try Task.checkCancellation()
                        guard self.attempt == token else { return }
                        try self.checkpoint?.append(chunk)
                        self.completedChunks = self.checkpoint?.transcripts.count ?? 0
                    }
                    guard let checkpoint = self.checkpoint else { throw AudioImportError.incompleteChunks }
                    let transcript = try checkpoint.mergedTranscript()
                    // Expose the complete source even if the final notes/summary request fails.
                    let raw = AudioImportResult(transcript: transcript, context: "", output: "")
                    if self.result?.transcript != transcript {
                        self.result = raw
                        self.resultMode = .rawTranscript
                        self.connectionDescription = connection
                    }
                    if selectedMode == .rawTranscript {
                        result = raw
                    } else {
                        self.progress = "All \(file.chunks.count) chunks complete · Generating \(selectedMode.title.lowercased()) from the full transcript"
                        result = try await Self.runWorker {
                            try await client.processImportedTranscript(transcript, mode: selectedMode)
                        }
                    }
                } else {
                    result = try await Self.runWorker {
                        try await client.processImportedAudio(file.audio, format: file.format, mode: selectedMode)
                    }
                }
                try Task.checkCancellation()
                guard let self, self.attempt == token else { return }
                self.result = result
                self.resultMode = selectedMode
                self.connectionDescription = connection
                self.progress = ""
                self.phase = .idle
                self.task = nil
            } catch {
                self?.completeFailure(error, attempt: token)
            }
        }
    }

    func cancel() {
        attempt = UUID()
        task?.cancel()
        // Keep the cancelled task until its worker has drained. A new action waits for it,
        // so repeated Cancel/Generate cannot accumulate audio buffers or conversions.
        phase = .idle
        progress = "Cancelled. Completed chunks are retained; resume explicitly. Audio already sent cannot be recalled."
    }

    func clear() {
        cancel()
        file = nil
        checkpoint = nil
        chunkSettings = nil
        completedChunks = 0
        progress = ""
        result = nil
        resultMode = nil
        error = nil
        connectionDescription = ""
    }

    nonisolated private static func runWorker<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let worker = Task.detached(priority: .userInitiated, operation: operation)
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private func completeFailure(_ error: Error, attempt: UUID) {
        guard self.attempt == attempt else { return }
        let wasProcessing = phase == .processing
        phase = .idle
        task = nil
        if error is CancellationError {
            progress = "Cancelled. Resume explicitly; completed chunks are retained."
        } else {
            let position = file?.plan.isChunked == true
                ? (completedChunks < (file?.chunks.count ?? 0)
                    ? "Chunk \(completedChunks + 1) failed; \(completedChunks) completed chunk\(completedChunks == 1 ? "" : "s") retained. "
                    : "Final output failed; the complete transcript is available. ")
                : ""
            self.progress = ""
            self.error = position + error.localizedDescription + (wasProcessing
                ? " No automatic retry was made. Explicit Retry retains completed chunks. If this repeats, stop retrying to avoid further charges and report this error."
                : " No audio was sent.")
        }
    }
}
