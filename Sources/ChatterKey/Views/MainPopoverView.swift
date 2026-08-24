import SwiftUI

struct MainPopoverView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)
            VStack(alignment: .leading, spacing: 14) {
                if !appState.setupComplete { setupCard } else { readyCard }
                transcriptSection
            }
            .padding(16)
            Divider().opacity(0.55)
            footer
        }
        .frame(width: 390)
        .onAppear { appState.refreshPermissions() }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.primary)
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ChatterKey").font(.system(size: 15, weight: .semibold))
                    Text("v0.2.1").font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
                Text("Complete setup").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            permissionRow("Microphone", ready: appState.microphoneGranted)
            permissionRow("Accessibility & hotkey", ready: appState.accessibilityGranted && appState.hotkeyReady)
            permissionRow("Provider API key", ready: appState.hasAPIKey)
            HStack {
                Button("Setup Guide") { OnboardingWindowController.shared.show(appState: appState) }
                    .buttonStyle(.borderedProminent)
                Button("Run Diagnostics") { appState.runDiagnostics() }
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.22)))
    }

    private var readyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.phase == .listening ? "Listening…" : "Hold to dictate")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Speak in any app and insert polished text instantly.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(appState.settings.hotkeyShortcut.symbols)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { appState.settings.outputMode },
                    set: { appState.setOutputMode($0) }
                )) {
                    ForEach(OutputMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 165)

                Button {
                    if appState.phase == .listening {
                        appState.finishDictation()
                    } else if appState.canRetry {
                        appState.retryLastDictation()
                    } else {
                        appState.beginDictation()
                    }
                } label: {
                    Label(
                        appState.phase == .listening ? "Stop & Insert" : (appState.canRetry ? "Retry" : "Test Dictation"),
                        systemImage: appState.phase == .listening ? "stop.fill" : (appState.canRetry ? "arrow.clockwise" : "mic.fill")
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.phase == .listening ? .red : .indigo)
                .disabled(appState.phase == .processing)
            }
        }
    }

    @ViewBuilder private var transcriptSection: some View {
        if appState.settings.historyEnabled, !appState.history.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("RECENT DICTATIONS").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                    Spacer()
                    Button("Clear") { appState.clearHistory() }.buttonStyle(.plain).font(.caption)
                }
                ForEach(appState.history.prefix(3)) { item in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.text).font(.system(size: 11)).lineLimit(2)
                            Text(item.outputMode.shortTitle).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { appState.copy(item.text) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless)
                        Button { appState.insert(item) } label: { Image(systemName: "arrow.turn.down.left") }
                            .buttonStyle(.borderless)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        } else if !appState.lastTranscript.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("LAST DICTATION").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                Text(appState.lastTranscript).font(.system(size: 12)).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy transcript") { appState.copyLastTranscript() }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(.indigo)
            }
            .padding(12)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            FooterActionButton(title: "Diagnostics", systemImage: "stethoscope") {
                SettingsWindowController.shared.show(appState: appState)
                appState.runDiagnostics()
            }
            Spacer(minLength: 8)
            FooterActionButton(title: "Settings", systemImage: "gearshape") {
                SettingsWindowController.shared.show(appState: appState)
            }
            FooterActionButton(title: "Quit", systemImage: "power", role: .destructive) {
                DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .contentShape(Rectangle())
    }

    private func permissionRow(_ title: String, ready: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle").foregroundStyle(ready ? .green : .secondary)
            Text(title).font(.system(size: 11, weight: .medium))
            Spacer()
            Text(ready ? "Ready" : "Required").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if !appState.setupComplete { return "Setup needed" }
        return switch appState.phase {
        case .idle: "Ready"
        case .listening: "Listening"
        case .processing: "Processing"
        case .inserted: "Done"
        case .failed: "Needs attention"
        }
    }

    private var statusColor: Color {
        if !appState.setupComplete { return .orange }
        return switch appState.phase {
        case .idle, .inserted: .green
        case .listening: .red
        case .processing: .indigo
        case .failed: .orange
        }
    }
}

private struct FooterActionButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(height: 32)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(isHovering ? Color.primary.opacity(0.08) : .clear)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
