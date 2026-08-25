import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var step = 0
    @State private var draft = ProviderSettings.load()
    @State private var apiKey = ""
    @State private var status = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.indigo : Color.secondary.opacity(0.18))
                        .frame(height: 5)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)

            Group {
                switch step {
                case 0: welcome
                case 1: providerSetup
                case 2: permissions
                default: diagnostics
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                Text(status).font(.caption).foregroundStyle(.secondary)
                if step < 3 {
                    Button("Continue") { continueFlow() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Start using ChatterKey") {
                        appState.completeOnboarding()
                        OnboardingWindowController.shared.close()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.setupComplete)
                }
            }
            .padding(20)
        }
        .frame(width: 640, height: 560)
        .onAppear {
            draft = appState.settings
            apiKey = appState.apiKey(for: draft.provider)
        }
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(Color.indigo.opacity(0.12)).frame(width: 108, height: 108)
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.indigo)
            }
            Text("Your voice, typed anywhere")
                .font(.system(size: 28, weight: .bold))
            Text("Hold a shortcut, speak naturally, and release. ChatterKey turns your voice into polished text in the focused app.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 22) {
                benefit("mic.fill", "Push to talk")
                benefit("character.cursor.ibeam", "Insert anywhere")
                benefit("key.fill", "Bring your own key")
            }
        }
        .padding(36)
    }

    private var providerSetup: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect your provider").font(.title2.bold())
            Text("Your API key is stored in macOS Keychain and is sent only to the provider you choose.")
                .foregroundStyle(.secondary)
            Form {
                Picker("Provider", selection: $draft.provider) {
                    ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: draft.provider) { _, provider in
                    draft.baseURL = provider.defaultBaseURL
                    draft.transcriptionModel = provider.defaultTranscriptionModel
                    draft.polishModel = provider.defaultPolishModel
                    apiKey = appState.apiKey(for: provider)
                }
                TextField("Base URL", text: $draft.baseURL)
                SecureField("API key", text: $apiKey)
                Picker("Default output", selection: $draft.outputMode) {
                    ForEach(OutputMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Push-to-talk", selection: $draft.hotkeyShortcut) {
                    ForEach(HotkeyShortcut.allCases) { Text($0.title).tag($0) }
                }
            }
            .formStyle(.grouped)
        }
        .padding(34)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Allow required permissions").font(.title2.bold())
            Text("ChatterKey records only while push-to-talk is active and uses Accessibility for the global shortcut and automatic paste.")
                .foregroundStyle(.secondary)
            permissionCard(
                icon: "mic.fill",
                title: "Microphone",
                detail: "Record your dictation",
                ready: appState.microphoneGranted
            )
            permissionCard(
                icon: "accessibility",
                title: "Accessibility",
                detail: "Detect the shortcut, read selected text, and paste replacements",
                ready: appState.accessibilityGranted
            )
            if draft.liveTranscriptionEnabled {
                permissionCard(
                    icon: "waveform.badge.mic",
                    title: "Speech Recognition",
                    detail: "Show an on-device live transcript preview",
                    ready: appState.speechRecognitionGranted
                )
            }
            HStack {
                Button("Allow Permissions") { appState.requestPermissions() }
                    .buttonStyle(.borderedProminent)
                Button("Refresh Status") { appState.refreshPermissions() }
            }
        }
        .padding(34)
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Run a final check").font(.title2.bold())
            Text("Everything should be green before your first dictation.")
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(appState.diagnostics) { item in
                    HStack(spacing: 12) {
                        diagnosticIcon(item.state)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                            Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(12)
                    if item.id != appState.diagnostics.last?.id { Divider() }
                }
            }
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            Button(appState.diagnosticsRunning ? "Checking…" : "Run Diagnostics") {
                appState.runDiagnostics()
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.diagnosticsRunning)
        }
        .padding(34)
        .onAppear { appState.runDiagnostics() }
    }

    private func continueFlow() {
        status = ""
        if step == 1 {
            do {
                try appState.saveSettings(draft, apiKey: apiKey)
            } catch {
                status = error.localizedDescription
                return
            }
        }
        if step == 2 { appState.refreshPermissions() }
        step += 1
    }

    private func benefit(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(.indigo)
            Text(title).font(.caption.weight(.semibold))
        }
        .frame(width: 112, height: 74)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func permissionCard(icon: String, title: String, detail: String, ready: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).frame(width: 32).foregroundStyle(ready ? .green : .indigo)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label(ready ? "Ready" : "Required", systemImage: ready ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ready ? .green : .secondary)
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private func diagnosticIcon(_ state: DiagnosticState) -> some View {
        switch state {
        case .checking: ProgressView().controlSize(.small).frame(width: 20)
        case .passed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).frame(width: 20)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red).frame(width: 20)
        }
    }
}
