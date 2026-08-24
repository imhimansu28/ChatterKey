import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft = ProviderSettings.load()
    @State private var apiKey = ""
    @State private var status = ""
    @State private var isTesting = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TabView {
                generalTab
                    .tabItem { Label("General", systemImage: "slider.horizontal.3") }
                providerTab
                    .tabItem { Label("Provider", systemImage: "network") }
                vocabularyTab
                    .tabItem { Label("Vocabulary", systemImage: "text.book.closed") }
                diagnosticsTab
                    .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            }
            .padding(.horizontal, 14)
            Divider()
            footer
        }
        .frame(width: 650, height: 680)
        .onAppear {
            draft = appState.settings
            apiKey = appState.apiKey(for: draft.provider)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.primary)
                .frame(width: 42, height: 42)
                .overlay(Image(systemName: "waveform").foregroundStyle(Color(nsColor: .windowBackgroundColor)))
            VStack(alignment: .leading, spacing: 2) {
                Text("ChatterKey Settings").font(.title3.weight(.semibold))
                Text("Version 0.2 · Voice typing that fits your workflow")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(22)
    }

    private var generalTab: some View {
        Form {
            Section("Writing") {
                Picker("Output mode", selection: $draft.outputMode) {
                    ForEach(OutputMode.allCases) { Text($0.title).tag($0) }
                }
                Text(draft.outputMode.instruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Smart cleanup and punctuation", isOn: $draft.smartPolish)
                Toggle("Fast single-pass audio processing", isOn: $draft.fastSinglePass)
                    .disabled(draft.provider != .openRouter)
            }

            Section("Push to talk") {
                Picker("Shortcut", selection: $draft.hotkeyShortcut) {
                    ForEach(HotkeyShortcut.allCases) { shortcut in
                        Text("\(shortcut.title)  ·  \(shortcut.symbols)").tag(shortcut)
                    }
                }
                Text("Hold the shortcut to speak, then release to process and insert text.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("History") {
                Toggle("Save transcript history locally", isOn: $draft.historyEnabled)
                if draft.historyEnabled {
                    Picker("Keep history", selection: $draft.historyRetentionDays) {
                        Text("1 day").tag(1)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }
                    Button("Clear History", role: .destructive) { appState.clearHistory() }
                }
                Text("History is off by default. Audio is never added to history.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Onboarding") {
                Button("Show Setup Guide Again") { appState.resetOnboarding() }
            }
        }
        .formStyle(.grouped)
    }

    private var providerTab: some View {
        Form {
            Section("Connection") {
                Picker("Provider", selection: $draft.provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .onChange(of: draft.provider) { _, provider in
                    draft.baseURL = provider.defaultBaseURL
                    draft.transcriptionModel = provider.defaultTranscriptionModel
                    draft.polishModel = provider.defaultPolishModel
                    apiKey = appState.apiKey(for: provider)
                    status = ""
                }
                TextField("Base URL", text: $draft.baseURL).textFieldStyle(.roundedBorder)
                SecureField("API key", text: $apiKey).textFieldStyle(.roundedBorder)
            }

            Section("Models") {
                TextField("Transcription model", text: $draft.transcriptionModel).textFieldStyle(.roundedBorder)
                TextField("Audio / polishing model", text: $draft.polishModel).textFieldStyle(.roundedBorder)
                if draft.fastSinglePass && draft.provider == .openRouter {
                    Text("Fast mode requires an audio-capable model. Recommended: google/gemini-3.5-flash-lite")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Privacy") {
                Text("Audio is sent directly to the provider you select. API keys stay in macOS Keychain. ChatterKey has no analytics or project-operated backend.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var vocabularyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Teach ChatterKey exact names, products, acronyms, and technical spellings.")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach($draft.personalDictionary) { $entry in
                        HStack(spacing: 8) {
                            TextField("What you say", text: $entry.spoken)
                                .textFieldStyle(.roundedBorder)
                            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                            TextField("Preferred output", text: $entry.replacement)
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                draft.personalDictionary.removeAll { $0.id == entry.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(12)
            }

            HStack {
                Button {
                    draft.personalDictionary.append(DictionaryEntry(spoken: "", replacement: ""))
                } label: {
                    Label("Add Word", systemImage: "plus")
                }
                Spacer()
                Text("\(draft.personalDictionary.count) entries")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .padding(.top, 16)
    }

    private var diagnosticsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("System Diagnostics").font(.headline)
                    Text("Check permissions, shortcut availability, Keychain, and provider connectivity.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(appState.diagnosticsRunning ? "Checking…" : "Run Diagnostics") {
                    appState.runDiagnostics()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.diagnosticsRunning)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(appState.diagnostics) { item in
                        HStack(spacing: 12) {
                            diagnosticIcon(item.state)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.system(size: 13, weight: .semibold))
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        if item.id != appState.diagnostics.last?.id { Divider() }
                    }
                }
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack {
                Button("Allow Permissions") { appState.requestPermissions() }
                Button("Refresh Permissions") { appState.refreshPermissions() }
                Spacer()
            }
        }
        .padding(22)
        .onAppear { appState.runDiagnostics() }
    }

    private var footer: some View {
        HStack {
            Text(status)
                .font(.caption)
                .foregroundStyle(status.hasPrefix("Connected") || status.hasPrefix("Saved") ? .green : .secondary)
            Spacer()
            Button("Test Connection") { testConnection() }
                .disabled(isTesting || apiKey.isEmpty)
            Button("Save Changes") { save() }
                .buttonStyle(.borderedProminent)
        }
        .padding(18)
    }

    private func save() {
        do {
            draft.personalDictionary = draft.personalDictionary.filter {
                !$0.spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !$0.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
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

    @ViewBuilder private func diagnosticIcon(_ state: DiagnosticState) -> some View {
        switch state {
        case .checking: ProgressView().controlSize(.small).frame(width: 20)
        case .passed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).frame(width: 20)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red).frame(width: 20)
        }
    }
}
