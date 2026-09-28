import ChatterKeyCore
import AudioToolbox
import AVFoundation
import Foundation

nonisolated struct ImportedAudioFile: Sendable {
    let name: String
    let duration: TimeInterval
    let audio: Data
    let format: AudioImportFormat
    let plan: AudioImportPlan
    let chunks: [URL]
    let preparedBytes: Int
    // Shared ownership keeps files alive until cancelled workers have released them.
    let storage: ImportedAudioStorage?
}

nonisolated final class ImportedAudioStorage: Sendable {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

nonisolated enum AudioFileImporter {
    static let maximumSourceBytes = 256 * 1_024 * 1_024

    static func prepare(_ url: URL) async throws -> ImportedAudioFile {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) { try prepareLocally(url) }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func prepareLocally(_ url: URL) throws -> ImportedAudioFile {
        try Task.checkCancellation()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard url.isFileURL, values.isRegularFile == true,
              let size = values.fileSize, size > 0, size <= maximumSourceBytes else {
            throw AudioFileImportError.unsupportedFile
        }
        let source = try AVAudioFile(forReading: url)
        // Bound converter buffer sizes/work for unusual but decodable source formats.
        guard source.processingFormat.channelCount <= 32,
              source.processingFormat.sampleRate <= 384_000 else { throw AudioFileImportError.unsupportedFile }
        let duration = Double(source.length) / source.processingFormat.sampleRate
        guard duration.isFinite, duration > 0 else { throw AudioFileImportError.unsupportedFile }
        let plan = try AudioImportPlan(duration: duration)
        // Keep compressed MPEG audio only when it is smaller than the prepared PCM payload.
        // Check the actual container, not a potentially misleading filename extension.
        if !plan.isChunked, isMP3File(url),
           Double(size) < duration * 16_000 * 2, size <= ProviderClient.maximumImportedAudioBytes {
            let data = try readAudio(at: url)
            return ImportedAudioFile(name: url.lastPathComponent, duration: duration, audio: data, format: .mp3, plan: plan, chunks: [], preparedBytes: data.count, storage: nil)
        }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ChatterKey", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let directory = base.appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let storage = ImportedAudioStorage(directory: directory)
        if plan.isChunked {
            var chunks: [URL] = []
            var bytes = 0
            for (index, length) in plan.durations.enumerated() {
                try Task.checkCancellation()
                let start = Double(index) * AudioImportPlan.chunkDuration
                let wav = directory.appendingPathComponent("chunk-\(index + 1).wav")
                try AudioRecorder.convertToProviderWAV(from: url, to: wav,
                    maximumFrames: AVAudioFramePosition(ceil(length * 16_000)) + 32,
                    sourceRange: start..<(start + length))
                let prepared = try AVAudioFile(forReading: wav)
                guard abs(Double(prepared.length) / 16_000 - length) < 0.01 else { throw RecorderError.conversionFailed }
                bytes += try wav.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                chunks.append(wav)
            }
            try Task.checkCancellation()
            return ImportedAudioFile(name: url.lastPathComponent, duration: duration, audio: Data(),
                format: .wav, plan: plan, chunks: chunks, preparedBytes: bytes, storage: storage)
        }
        defer { withExtendedLifetime(storage) {} }
        let wav = directory.appendingPathComponent("audio.wav")
        try AudioRecorder.convertToProviderWAV(from: url, to: wav, maximumFrames: AVAudioFramePosition(AudioImportPlan.directDuration * 16_000) + 32)
        try Task.checkCancellation()
        let prepared = try AVAudioFile(forReading: wav)
        let preparedDuration = Double(prepared.length) / prepared.fileFormat.sampleRate
        let data = try readAudio(at: wav)
        return ImportedAudioFile(name: url.lastPathComponent, duration: preparedDuration, audio: data, format: .wav, plan: plan, chunks: [], preparedBytes: data.count, storage: nil)
    }

    static func readAudio(at url: URL) throws -> Data {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // Bound the read itself: source metadata can change after selection.
        let data = try handle.read(upToCount: ProviderClient.maximumImportedAudioBytes + 1) ?? Data()
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= ProviderClient.maximumImportedAudioBytes else {
            throw AudioImportError.tooLarge
        }
        return data
    }

    private static func isMP3File(_ url: URL) -> Bool {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr,
              let file else { return false }
        defer { AudioFileClose(file) }
        var type: AudioFileTypeID = 0
        var size = UInt32(MemoryLayout.size(ofValue: type))
        return AudioFileGetProperty(file, kAudioFilePropertyFileFormat, &size, &type) == noErr
            && type == kAudioFileMP3Type
    }
}

nonisolated enum AudioFileImportError: LocalizedError {
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            "Choose a non-empty audio file up to 256 MiB. MP3, M4A, WAV, AIFF and CAF are supported when decodable by macOS (up to 32 channels / 384 kHz)."
        }
    }
}
