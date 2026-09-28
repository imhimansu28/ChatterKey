import ChatterKeyCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AudioImportView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var model: AudioImportModel
    @State private var showTranscript = false
    @State private var exportError: String?
    @State private var showPrivacy = false
    @State private var copied = false

    private var displayedText: String {
        guard let result = model.result else { return "" }
        return showTranscript || model.resultMode == .rawTranscript ? result.transcript : result.output
    }

    private var exportText: String {
        guard let result = model.result, model.resultMode != .rawTranscript, !showTranscript else { return displayedText }
        return "\(result.context)\n\n\(result.output)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ChatterKey").font(.system(size: 15, weight: .semibold))
                    Text("Audio import").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Label("Your audio. Your words.", systemImage: "waveform.path")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22).frame(height: 68)
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                workspace
            }
            Divider()
            HStack(spacing: 8) {
                Label("Nothing is pasted automatically. Copy or save before closing.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { showPrivacy.toggle() } label: {
                    Label("Privacy & limits", systemImage: "info.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPrivacy) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your recording, your choice").font(.headline)
                        Text("Choosing a file only prepares it on this Mac. Generate sends the full prepared recording to your selected provider; its fees and limits apply. Cancel cannot recall audio already sent.")
                        Text("Up to 4 hours / 256 MiB; at most 16 chunks. MP3, M4A, WAV, AIFF and CAF, when supported by macOS. Provider/model limits may be lower.")
                        Text("For recordings up to 30 minutes, smaller MP3 files are sent unchanged, including embedded tags. Longer recordings are split locally into 15-minute WAV chunks. A smaller upload does not reduce model audio-token usage or guarantee a complete transcript.")
                        Text("Up to 30 minutes: one request. Longer recordings: one transcription request per chunk; Notes/Summary add one request using the complete merged transcript. Explicit Retry reuses successful chunks. The same model/provider is used throughout. Notes can omit details; review the full source transcript. Dictation prompts, snippets and commands do not apply. Results stay out of History and usage counters.")
                    }
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                    .padding(20).frame(width: 360)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .frame(minWidth: 800, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .buttonStyle(AudioImportButtonStyle())
        .onChange(of: model.resultMode) { _, _ in showTranscript = false }
        .onChange(of: exportText) { _, _ in copied = false }
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copied = false
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("01", title: "Recording")
                        if let file = model.file {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 18, weight: .medium)).foregroundStyle(Color.accentColor)
                                    .frame(width: 36, height: 42)
                                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(file.name).font(.system(size: 13, weight: .semibold))
                                        .lineLimit(2).truncationMode(.middle).help(file.name)
                                    Text("\(Int(file.duration) / 60)m \(Int(file.duration) % 60)s · audio ready")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text("Audio: \(ByteCountFormatter.string(fromByteCount: Int64(file.preparedBytes), countStyle: .file)) · \(file.format.rawValue.uppercased())")
                                .font(.caption).foregroundStyle(.secondary)
                            if file.plan.isChunked {
                                Text("\(file.plan.durations.count) local chunks, up to 15 minutes each. Transcripts are merged in order without summarising. Notes/Summary use the complete transcript, not chunk summaries.")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            HStack {
                                Button("Change…", action: chooseFile)
                                    .disabled(model.isBusy || appState.phase.isBusy)
                                Spacer()
                                Button("Clear") { exportError = nil; model.clear() }
                                    .disabled(model.isBusy)
                            }
                            .controlSize(.small)
                        } else {
                            Button(action: chooseFile) {
                                HStack(spacing: 10) {
                                    Image(systemName: "waveform.badge.plus")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 36, height: 40)
                                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Choose recording").font(.system(size: 12, weight: .semibold))
                                        Text("MP3, M4A, WAV, AIFF, CAF")
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.3)))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isBusy || appState.phase.isBusy)
                        }
                        Text("Up to 4 hours · 256 MiB · 16 chunks")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("02", title: "Output format")
                        ForEach(AudioImportMode.allCases) { mode in
                            modeButton(mode)
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Label("CONNECTION", systemImage: "network")
                    .font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.settings.provider.title).font(.system(size: 12, weight: .medium))
                    Text(appState.settings.model).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        .help(appState.settings.model)
                }
                if model.isBusy {
                    Button(action: model.cancel) {
                        Label("Cancel", systemImage: "xmark").frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button {
                        exportError = nil
                        model.generate(settings: appState.settings, apiKey: appState.apiKey(for: appState.settings.provider))
                    } label: {
                        Label(model.error == nil && model.completedChunks == 0 ? "Generate \(model.mode == .rawTranscript ? "transcript" : model.mode.title.lowercased())" : "Resume / Generate", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AudioImportButtonStyle(prominent: true))
                    .disabled(model.file == nil || appState.phase.isBusy)
                }
                if !model.progress.isEmpty {
                    Text(model.progress).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(model.isBusy ? "Cancel cannot recall audio already sent." : model.requestDisclosure)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .controlSize(.large).padding(20)
        }
        .frame(width: 260)
        .background {
            Color(nsColor: .windowBackgroundColor)
                .overlay {
                    LinearGradient(colors: [Color.accentColor.opacity(0.035), .clear], startPoint: .top, endPoint: .bottom)
                }
        }
    }

    private func modeButton(_ mode: AudioImportMode) -> some View {
        let icon: String
        let detail: String
        switch mode {
        case .rawTranscript:
            icon = "text.alignleft"
            detail = "Full source transcript"
        case .notes:
            icon = "list.bullet.rectangle"
            detail = "Detailed notes"
        case .summary:
            icon = "text.quote"
            detail = "A short overview"
        }
        return Button { model.mode = mode } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(model.mode == mode ? Color.accentColor : .secondary)
                    .frame(width: 32, height: 34)
                    .background(model.mode == mode ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if model.mode == mode {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.accentColor)
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(model.mode == mode ? Color(nsColor: .controlBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(model.mode == mode ? Color.accentColor.opacity(0.45) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain).disabled(model.isBusy)
        .accessibilityLabel(mode.title).accessibilityValue(model.mode == mode ? "Selected" : "Not selected")
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.phase.isBusy || model.error != nil || exportError != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let exportError {
                            Label(exportError, systemImage: "exclamationmark.triangle")
                                .textSelection(.enabled)
                        }
                        if appState.phase.isBusy {
                            Label("Finish or cancel your dictation/edit to continue.", systemImage: "pause.circle")
                        }
                        if let error = model.error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .textSelection(.enabled)
                        }
                    }
                    .font(.callout).foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                .frame(height: 64)
                .background(Color.orange.opacity(0.10))
            }
            if let result = model.result, let resultMode = model.resultMode {
                HStack(spacing: 16) {
                    if resultMode == .rawTranscript {
                        Text("Transcript").font(.system(size: 13, weight: .semibold))
                    } else {
                        resultTab(resultMode.title, transcript: false)
                        resultTab("Transcript", transcript: true)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        Button {
                            NSPasteboard.general.clearContents()
                            copied = NSPasteboard.general.setString(exportText, forType: .string)
                        } label: {
                            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        .help("Copy text")
                        Button(action: saveText) { Label("Save", systemImage: "square.and.arrow.down") }
                            .help("Save text…")
                    }
                }
                .padding(.horizontal, 24).frame(height: 56)
                Divider()
                if model.isBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(model.progress)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 10)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let file = model.file {
                            Text(URL(fileURLWithPath: file.name).deletingPathExtension().lastPathComponent)
                                .font(.system(size: 21, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if resultMode != .rawTranscript && !showTranscript {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("RECORDING CONTEXT").font(.system(size: 10, weight: .semibold))
                                    .tracking(0.8).foregroundStyle(.secondary)
                                Text(result.context).font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                            .padding(.leading, 12)
                            .overlay(alignment: .leading) { Rectangle().fill(Color.accentColor.opacity(0.6)).frame(width: 2) }
                        }
                        Group {
                            if resultMode != .rawTranscript && !showTranscript {
                                AudioImportText(text: displayedText).id(displayedText)
                            } else {
                                Text(displayedText)
                            }
                        }
                        .font(.system(size: 14)).lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .textSelection(.enabled)
                    .padding(28)
                    .frame(maxWidth: 680, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5)))
                    .frame(maxWidth: .infinity, alignment: .center).padding(24)
                }
                .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generated with \(model.connectionDescription)").lineLimit(2)
                    Text("Review important details against the recording. AI can mishear or omit content.")
                }
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
            } else {
                welcomeWorkspace
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionLabel(_ number: String, title: String) -> some View {
        HStack(spacing: 8) {
            Text(number).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
            Text(title).font(.system(size: 12, weight: .semibold))
        }
        .padding(.bottom, 4)
    }

    private var welcomeWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform").foregroundStyle(Color.accentColor)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    Text(model.mode.title).foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 12) {
                    Text(emptyTitle).font(.system(size: 29, weight: .semibold))
                        .tracking(-0.5)
                    Text(emptyDetail).font(.system(size: 13)).foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
                .fixedSize(horizontal: false, vertical: true)

                if model.isBusy {
                    ProgressView().controlSize(.regular)
                        .accessibilityLabel(model.progress)
                } else if model.file == nil && model.error == nil {
                    exampleDocument
                    Label("Choose a recording on the left to get started.", systemImage: "arrow.left")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else if let file = model.file {
                    Label("\(file.plan.isChunked ? "Chunked transcription" : "Direct transcription") · \(model.mode == .rawTranscript ? "Transcript only" : "Source transcript included")", systemImage: "doc.text")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 500, alignment: .leading)
            .padding(36)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .topLeading) {
            LinearGradient(colors: [Color.accentColor.opacity(0.055), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private var exampleDocument: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("EXAMPLE · \(model.mode.title.uppercased())", systemImage: "doc.text")
                .font(.system(size: 9, weight: .semibold)).tracking(0.6)
                .foregroundStyle(Color.accentColor)
            Text("Planning a small workshop")
                .font(.system(size: 18, weight: .semibold))
            Group {
                switch model.mode {
                case .rawTranscript:
                    Text("“Let’s keep the workshop small, around twelve people. Start with a short demonstration, then give everyone time to practise. We haven’t chosen a date yet.”")
                case .notes:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Format & group size").fontWeight(.semibold)
                        Text("• Around 12 participants\n• A short demonstration, followed by practice")
                        Text("Still to decide").fontWeight(.semibold)
                        Text("The workshop date has not been chosen.")
                    }
                case .summary:
                    Text("A small workshop for around 12 people, combining a short demonstration with hands-on practice. The date is still undecided.")
                }
            }
            .font(.system(size: 12)).lineSpacing(4)
            .foregroundStyle(.secondary)
            Divider()
            Text("Illustrative example — not your recording.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(24)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
        .shadow(color: .black.opacity(0.035), radius: 12, x: 0, y: 5)
    }

    private func resultTab(_ title: String, transcript: Bool) -> some View {
        Button { showTranscript = transcript } label: {
            Text(title).font(.system(size: 13, weight: showTranscript == transcript ? .semibold : .regular))
                .foregroundStyle(showTranscript == transcript ? Color.primary : .secondary)
                .frame(height: 56)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(showTranscript == transcript ? Color.accentColor : .clear).frame(height: 2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityValue(showTranscript == transcript ? "Selected" : "Not selected")
    }

    private var emptyTitle: String {
        if model.error != nil { return "Let’s resolve this first." }
        return switch model.phase {
        case .preparing: "Preparing your recording."
        case .processing: "Creating your \(model.mode.title.lowercased())."
        case .idle: model.file == nil ? "Recordings, ready to read." : "Ready to create \(model.mode == .rawTranscript ? "a transcript" : model.mode.title.lowercased())."
        }
    }

    private var emptyDetail: String {
        if model.error != nil { return "Read the error above before trying again. Requests are never retried automatically." }
        return switch model.phase {
        case .preparing: "Preparing audio on your Mac. Nothing is being uploaded."
        case .processing: model.progress
        case .idle: model.file == nil
            ? "Turn a lecture, conversation or voice memo into \(model.mode == .rawTranscript ? "a readable transcript" : model.mode == .notes ? "organised notes, with the full source transcript alongside" : "a concise overview, with the full source transcript alongside")."
            : "Your audio is prepared. Select Generate when you’re ready to send it to your chosen provider."
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an existing recording. Choosing a file only prepares it locally."
        panel.begin { response in
            guard response == .OK, let url = panel.url, !appState.phase.isBusy, !model.isBusy else { return }
            exportError = nil
            model.select(url)
        }
    }

    private func saveText() {
        let text = exportText
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let name = model.file.map { URL(fileURLWithPath: $0.name).deletingPathExtension().lastPathComponent } ?? "recording"
        let suffix = showTranscript ? "transcript" : model.resultMode?.rawValue ?? "result"
        panel.nameFieldStringValue = "\(name)-\(suffix).txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                exportError = nil
            } catch { exportError = "Could not save the result: \(error.localizedDescription)" }
        }
    }
}

private struct AudioImportButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 11).padding(.vertical, prominent ? 10 : 7)
            .foregroundStyle(isEnabled ? (prominent ? Color.white : .primary) : .secondary)
            .background(prominent ? (isEnabled ? Color.accentColor : Color.primary.opacity(0.06)) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(prominent ? .clear : Color(nsColor: .separatorColor)))
            .opacity(configuration.isPressed && isEnabled ? 0.75 : 1)
    }
}
