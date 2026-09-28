import ChatterKeyCore
import SwiftUI

struct MainPopoverView: View {
    @EnvironmentObject private var appState: AppState
    @State private var importIsBusy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if appState.setupComplete { recordingControls } else { setupCard }
            if case .failed(let message) = appState.phase {
                ScrollView {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 64)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
            if appState.phase == .reviewing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review your voice edit before replacing anything.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Review Edit") { appState.showEditPreview() }
                        .modifier(PopoverGlassButton())
                }
            }
            if appState.editPreview == nil { transcriptSection }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .modifier(PopoverGlassSurface())
        .onReceive(appState.audioImport.$phase) { importIsBusy = $0 != .idle }
        .onAppear {
            appState.refreshPermissions()
            appState.refreshHistory()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            Text("ChatterKey").font(.system(size: 13, weight: .semibold))
                .help("ChatterKey \(appVersion)")
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 5, height: 5)
                Text(statusText).font(.system(size: 11, weight: .medium))
            }
            .accessibilityElement(children: .combine)
        }
        .frame(minHeight: 22)
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Complete setup").font(.system(size: 13, weight: .semibold))
            permissionRow("Microphone", ready: appState.microphoneGranted)
            permissionRow("Accessibility & hotkey", ready: appState.accessibilityGranted && appState.hotkeyReady)
            permissionRow("Provider API key", ready: appState.hasAPIKey)
            HStack(spacing: 10) {
                Button("Setup Guide") { OnboardingWindowController.shared.show(appState: appState) }
                    .modifier(PopoverGlassButton())
                Button("Run Diagnostics") { appState.runDiagnostics() }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var recordingIsDisabled: Bool {
        importIsBusy || appState.phase == .processing || appState.phase == .reviewing
    }

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "textformat").font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Menu(appState.settings.outputMode.title) {
                    Picker("Writing mode", selection: Binding(
                        get: { appState.settings.outputMode },
                        set: { appState.setOutputMode($0) }
                    )) {
                        ForEach(OutputMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                .menuStyle(.borderlessButton)
                .font(.system(size: 12, weight: .medium))
                .fixedSize()
                .accessibilityLabel("Writing mode").accessibilityValue(appState.settings.outputMode.title)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 24)

            Button {
                if appState.phase == .listening {
                    appState.finishDictation()
                } else if appState.canRetry {
                    appState.retryLastDictation()
                } else {
                    appState.beginDictation()
                }
            } label: {
                HStack(spacing: 8) {
                    if appState.phase == .processing {
                        ProgressView().controlSize(.small)
                        Text("Processing…")
                    } else {
                        Label(
                            appState.phase == .listening ? "Stop & Process" : (appState.canRetry ? "Retry dictation" : "Start dictation"),
                            systemImage: appState.phase == .listening ? "stop.fill" : (appState.canRetry ? "arrow.clockwise" : "mic.fill")
                        )
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(recordingIsDisabled ? .secondary : .primary)
                .frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .modifier(PopoverGlassButton())
            .tint(appState.phase == .listening ? .red : .accentColor)
            .disabled(recordingIsDisabled)

            HStack(alignment: .top, spacing: 8) {
                Text(appState.settings.hotkeyShortcut.symbols)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                Text(recordingInstructions)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .help(appState.settings.hotkeyShortcut.recordingInstructions)
        }
    }

    private var recordingInstructions: String {
        if importIsBusy { return "Finish or cancel the audio import to start dictation." }
        return switch appState.phase {
        case .processing: "Processing your recording. No automatic retries."
        case .reviewing: "Nothing is replaced until you approve the edit."
        case .failed:
            appState.canRetry ? "Retry saved audio, or start a new dictation." : "Start a new dictation when you’re ready."
        case .listening:
            appState.handsFreeRecording ? "Hands-free · press Fn to stop. Esc cancels." : "Release to process · Esc cancels."
        default:
            appState.settings.hotkeyShortcut == .function
                ? "Hold to talk · double-tap for hands-free.\nFn stops · Esc cancels."
                : "Hold to talk · release to process.\nEsc cancels."
        }
    }

    @ViewBuilder private var transcriptSection: some View {
        if appState.settings.historyEnabled, let item = appState.history.first {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Recent · \(item.outputMode.shortTitle)")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("History") {
                        SettingsWindowController.shared.show(appState: appState, section: .history)
                    }
                    .font(.system(size: 11))
                    Button { appState.copy(item.text) } label: { Image(systemName: "doc.on.doc") }
                        .help("Copy recent dictation").accessibilityLabel("Copy recent dictation")
                }
                .buttonStyle(.borderless)
                Text(item.text).font(.system(size: 12)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if !appState.lastTranscript.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Last dictation").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button { appState.copyLastTranscript() } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Copy last dictation").accessibilityLabel("Copy last dictation")
                }
                Text(appState.lastTranscript).font(.system(size: 12)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                AudioImportWindowController.shared.show(appState: appState)
            } label: {
                Label("Import audio", systemImage: "waveform.badge.plus")
            }
            .help("Import a recording for a transcript, notes or summary")
            .disabled(appState.phase.isBusy)
            Spacer(minLength: 8)
            Button {
                SettingsWindowController.shared.show(appState: appState)
            } label: { Image(systemName: "gearshape") }
                .help("Settings").accessibilityLabel("Settings")
            Menu {
                Button("Diagnostics", systemImage: "stethoscope") {
                    SettingsWindowController.shared.show(appState: appState, section: .diagnostics)
                }
                Divider()
                Button("Quit ChatterKey", systemImage: "power", role: .destructive) {
                    DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Diagnostics and quit").accessibilityLabel("More options")
        }
        .buttonStyle(.borderless).font(.system(size: 12, weight: .medium))
        .frame(minHeight: 24)
    }

    private func permissionRow(_ title: String, ready: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle").foregroundStyle(ready ? .green : .secondary)
            Text(title).font(.system(size: 12))
            Spacer()
            Text(ready ? "Ready" : "Required").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    private var statusText: String {
        if !appState.setupComplete { return "Setup needed" }
        if importIsBusy { return "Import in progress" }
        return switch appState.phase {
        case .idle: "Ready"
        case .listening: appState.handsFreeRecording ? "Hands-free" : "Listening"
        case .processing: "Processing"
        case .reviewing: "Review edit"
        case .pasteSent: "Paste sent"
        case .failed: "Needs attention"
        }
    }

    private var statusColor: Color {
        if !appState.setupComplete { return .orange }
        if importIsBusy { return .accentColor }
        return switch appState.phase {
        case .idle: .green
        case .pasteSent: .accentColor
        case .listening: .red
        case .processing, .reviewing: .accentColor
        case .failed: .orange
        }
    }
}

private struct PopoverGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            // One clear glass surface, not a material sheet underneath several opaque cards.
            content
                .glassEffect(contrast == .increased ? .regular : .clear, in: .rect(cornerRadius: 20))
                .containerBackground(.clear, for: .window)
        } else {
            content.background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.ultraThinMaterial))
        }
    }
}

private struct PopoverGlassButton: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content.buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.regular)
        } else {
            content.buttonStyle(.borderedProminent).controlSize(.regular)
        }
    }
}
