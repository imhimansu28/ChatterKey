import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = ProviderSettings.load()
    @State private var apiKey = ""
    @State private var status = ""
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.primary)
                    .frame(width: 42, height: 42)
                    .overlay(Image(systemName: "waveform").foregroundStyle(Color(nsColor: .windowBackgroundColor)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ChatterKey Settings").font(.title3.weight(.semibold))
                    Text("Configure providers, models, and language behavior.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)

            Divider()

            Form {
                Section("Provider") {
                    Picker("Provider", selection: $draft.provider) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .onChange(of: draft.provider) { _, provider in
                        draft.baseURL = provider.defaultBaseURL
                        draft.transcriptionModel = provider.defaultTranscriptionModel
                        draft.polishModel = provider.defaultPolishModel
                        apiKey = KeychainStore.read(account: provider.rawValue)
                        status = ""
                    }

                    TextField("Base URL", text: $draft.baseURL)
                        .textFieldStyle(.roundedBorder)
                    SecureField("API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Models") {
                    TextField("Transcription model", text: $draft.transcriptionModel)
                        .textFieldStyle(.roundedBorder)
                    TextField("Polishing model", text: $draft.polishModel)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Smart cleanup and punctuation", isOn: $draft.smartPolish)
                    Toggle("Translate Hindi/Hinglish into polished English", isOn: $draft.preserveHinglish)
                    Toggle("Fast single-pass audio processing", isOn: $draft.fastSinglePass)
                        .disabled(draft.provider != .openRouter)
                    if draft.fastSinglePass && draft.provider == .openRouter {
                        Text("Fast mode requires an audio-capable model. Recommended: google/gemini-3.5-flash-lite")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Shortcut") {
                    LabeledContent("Push to talk") {
                        Text("Fn")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                    }
                    Text("Hold the shortcut to speak, then release to insert text into the focused app.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Text("Audio is sent directly to the provider you select. API keys stay in macOS Keychain. ChatterKey has no analytics or project-operated backend.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(status.hasPrefix("Connected") ? .green : .secondary)
                Spacer()
                Button("Test Connection") { testConnection() }
                    .disabled(isTesting || apiKey.isEmpty)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(18)
        }
        .frame(width: 560, height: 590)
        .onAppear {
            draft = appState.settings
            apiKey = KeychainStore.read(account: draft.provider.rawValue)
        }
    }

    private func save() {
        do {
            try appState.saveSettings(draft, apiKey: apiKey)
            status = "Saved securely"
        } catch {
            status = error.localizedDescription
        }
    }

    private func testConnection() {
        isTesting = true
        status = "Testing…"
        Task {
            do {
                try await ProviderClient(settings: draft, apiKey: apiKey).testConnection()
                status = "Connected successfully"
            } catch {
                status = error.localizedDescription
            }
            isTesting = false
        }
    }
}
