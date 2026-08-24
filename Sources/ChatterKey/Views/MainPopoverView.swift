import SwiftUI

struct MainPopoverView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.primary)
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    }
                    .frame(width: 30, height: 30)
                    Text("ChatterKey").font(.system(size: 15, weight: .semibold))
                }
                Spacer()
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider().opacity(0.55)

            VStack(alignment: .leading, spacing: 14) {
                if !appState.setupComplete {
                    setupCard
                } else {
                    readyCard
                }

                if !appState.lastTranscript.isEmpty {
                    lastTranscriptCard
                }
            }
            .padding(16)

            Divider().opacity(0.55)

            HStack(spacing: 8) {
                FooterActionButton(title: "Refresh", systemImage: "arrow.clockwise") {
                    appState.refreshPermissions()
                }
                Spacer(minLength: 12)
                FooterActionButton(title: "Settings", systemImage: "gearshape") {
                    SettingsWindowController.shared.show(appState: appState)
                }
                FooterActionButton(title: "Quit", systemImage: "power", role: .destructive) {
                    DispatchQueue.main.async {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .frame(width: 370)
        .onAppear { appState.refreshPermissions() }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                Text("Complete setup")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            permissionRow("Microphone", ready: appState.microphoneGranted)
            permissionRow("Accessibility & hotkey", ready: appState.accessibilityGranted && appState.hotkeyReady)
            permissionRow("Provider API key", ready: appState.hasAPIKey)

            HStack {
                Button("Allow Permissions") { appState.requestPermissions() }
                    .buttonStyle(.borderedProminent)
                Button("Provider Settings") { SettingsWindowController.shared.show(appState: appState) }
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
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Fn")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            Button {
                if appState.phase == .listening {
                    appState.finishDictation()
                } else {
                    appState.beginDictation()
                }
            } label: {
                Label(
                    appState.phase == .listening ? "Stop & Insert" : "Test Dictation Now",
                    systemImage: appState.phase == .listening ? "stop.fill" : "mic.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(appState.phase == .listening ? .red : .indigo)
            .disabled(appState.phase == .processing)
        }
    }

    private var lastTranscriptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAST DICTATION")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
            Text(appState.lastTranscript)
                .font(.system(size: 12))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Copy transcript") { appState.copyLastTranscript() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.indigo)
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    private func permissionRow(_ title: String, ready: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? .green : .secondary)
            Text(title).font(.system(size: 11, weight: .medium))
            Spacer()
            Text(ready ? "Ready" : "Required")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
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
        case .idle, .inserted: Color.green
        case .listening: Color.red
        case .processing: Color.indigo
        case .failed: Color.orange
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
                .padding(.horizontal, 11)
                .frame(height: 32)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
