import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case provider
    case vocabulary
    case snippets
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .provider: "AI Provider"
        case .vocabulary: "Vocabulary"
        case .snippets: "Voice Snippets"
        case .diagnostics: "Diagnostics"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Writing, shortcut, and local history"
        case .provider: "Connection, API key, and model selection"
        case .vocabulary: "Names and terms ChatterKey should spell exactly"
        case .snippets: "Reusable text expanded from short voice cues"
        case .diagnostics: "Permissions, shortcut, Keychain, and provider checks"
        }
    }

    var icon: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .provider: "sparkles"
        case .vocabulary: "character.book.closed"
        case .snippets: "text.badge.plus"
        case .diagnostics: "waveform.path.ecg"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSection: SettingsSection = .general
    @State private var draft = ProviderSettings.load()
    @State private var apiKey = ""
    @State private var status = ""
    @State private var isTesting = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                detailHeader
                Divider()
                detailContent
                Divider()
                footer
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 800, idealWidth: 840, minHeight: 620, idealHeight: 660)
        .onAppear {
            draft = appState.settings
            apiKey = appState.apiKey(for: draft.provider)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "waveform")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("ChatterKey")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Version \(appVersion)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 18)

            VStack(spacing: 4) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            selectedSection = section
                        }
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: section.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 20)
                            Text(section.title)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(selectedSection == section ? Color.primary : Color.secondary)
                        .padding(.horizontal, 11)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedSection == section ? Color.accentColor.opacity(0.14) : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            HStack(spacing: 9) {
                Circle()
                    .fill(appState.setupComplete ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(appState.setupComplete ? "Ready to dictate" : "Setup needs attention")
                        .font(.system(size: 11, weight: .semibold))
                    Text(appState.settings.hotkeyShortcut.symbols)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .padding(12)
        }
        .frame(width: 190)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var detailHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: selectedSection.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedSection.title)
                    .font(.system(size: 20, weight: .semibold))
                Text(selectedSection.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(height: 78)
    }

    @ViewBuilder private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch selectedSection {
                case .general: generalContent
                case .provider: providerContent
                case .vocabulary: vocabularyContent
                case .snippets: snippetsContent
                case .diagnostics: diagnosticsContent
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.visible)
        .animation(nil, value: selectedSection)
    }

    private var generalContent: some View {
        VStack(spacing: 16) {
            settingsCard("Writing", icon: "text.cursor") {
                settingRow("Output mode", detail: draft.outputMode.shortTitle) {
                    Picker("", selection: $draft.outputMode) {
                        ForEach(OutputMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }
                cardDivider
                Text(draft.outputMode.instruction)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                cardDivider
                toggleRow(
                    "Smart cleanup and punctuation",
                    detail: "Remove filler words and polish the final transcript.",
                    isOn: $draft.smartPolish
                )
                cardDivider
                toggleRow(
                    "Spoken formatting commands",
                    detail: "Use new line, paragraph, bullet, and punctuation commands in English or Hinglish.",
                    isOn: $draft.spokenCommandsEnabled
                )
                cardDivider
                toggleRow(
                    "Fast single-pass processing",
                    detail: draft.provider == .openRouter ? "Use one audio-capable model for lower latency." : "Available with OpenRouter audio-capable models.",
                    isOn: $draft.fastSinglePass
                )
                .disabled(draft.provider != .openRouter)
            }

            settingsCard("Push to talk", icon: "keyboard") {
                settingRow("Shortcut", detail: "Hold to record, release to insert") {
                    Picker("", selection: $draft.hotkeyShortcut) {
                        ForEach(HotkeyShortcut.allCases) { shortcut in
                            Text("\(shortcut.title)  ·  \(shortcut.symbols)").tag(shortcut)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }
            }

            settingsCard("Local history", icon: "clock.arrow.circlepath") {
                toggleRow(
                    "Save transcript history",
                    detail: "Off by default. Audio is never saved in history.",
                    isOn: $draft.historyEnabled
                )
                if draft.historyEnabled {
                    cardDivider
                    settingRow("Retention", detail: "Automatically remove older entries") {
                        Picker("", selection: $draft.historyRetentionDays) {
                            Text("1 day").tag(1)
                            Text("7 days").tag(7)
                            Text("30 days").tag(30)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                    cardDivider
                    Button("Clear transcript history", role: .destructive) { appState.clearHistory() }
                        .buttonStyle(.link)
                }
            }

            settingsCard("Setup", icon: "wand.and.stars") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("First-run setup guide").font(.system(size: 13, weight: .medium))
                        Text("Review provider and permission setup again.")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Setup Guide") { appState.resetOnboarding() }
                }
            }
        }
    }

    private var providerContent: some View {
        VStack(spacing: 16) {
            settingsCard("Connection", icon: "network") {
                settingRow("Provider", detail: "Choose where audio and text are processed") {
                    Picker("", selection: $draft.provider) {
                        ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .onChange(of: draft.provider) { _, provider in
                        draft.baseURL = provider.defaultBaseURL
                        draft.transcriptionModel = provider.defaultTranscriptionModel
                        draft.polishModel = provider.defaultPolishModel
                        apiKey = appState.apiKey(for: provider)
                        status = ""
                    }
                }
                cardDivider
                fieldRow("Base URL", placeholder: "https://api.example.com/v1", text: $draft.baseURL)
                cardDivider
                secureFieldRow("API key", placeholder: "Stored securely in macOS Keychain", text: $apiKey)
            }

            settingsCard("Models", icon: "cpu") {
                fieldRow("Transcription", placeholder: "Transcription model ID", text: $draft.transcriptionModel)
                cardDivider
                fieldRow("Audio / polishing", placeholder: "Writing model ID", text: $draft.polishModel)
                if draft.fastSinglePass && draft.provider == .openRouter {
                    cardDivider
                    Label("Fast mode needs an audio-capable model.", systemImage: "bolt.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            settingsCard("Privacy", icon: "lock.shield") {
                Label {
                    Text("Audio goes directly to your selected provider. API keys remain in macOS Keychain. ChatterKey has no analytics or project-operated transcription server.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                }
            }
        }
    }

    private var vocabularyContent: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Add names, products, acronyms, and technical terms that need exact spelling.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    draft.personalDictionary.append(DictionaryEntry(spoken: "", replacement: ""))
                } label: {
                    Label("Add Word", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if draft.personalDictionary.isEmpty {
                emptyState(
                    icon: "character.book.closed",
                    title: "No vocabulary yet",
                    detail: "Add the words ChatterKey should always spell correctly."
                )
            } else {
                ForEach($draft.personalDictionary) { $entry in
                    settingsCard(nil, icon: nil) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("WHEN YOU SAY").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                                TextField("chatter key", text: $entry.spoken).textFieldStyle(.roundedBorder)
                            }
                            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("WRITE").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                                TextField("ChatterKey", text: $entry.replacement).textFieldStyle(.roundedBorder)
                            }
                            Button(role: .destructive) {
                                draft.personalDictionary.removeAll { $0.id == entry.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    private var snippetsContent: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Snippet content is expanded locally after transcription.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    draft.voiceSnippets.append(VoiceSnippet(cue: "", content: ""))
                } label: {
                    Label("Add Snippet", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if draft.voiceSnippets.isEmpty {
                emptyState(
                    icon: "text.badge.plus",
                    title: "No voice snippets yet",
                    detail: "Create a cue such as “my email” and the exact text it should insert."
                )
            } else {
                ForEach($draft.voiceSnippets) { $snippet in
                    settingsCard(nil, icon: nil) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("VOICE CUE").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                                TextField("my email", text: $snippet.cue).textFieldStyle(.roundedBorder)
                                Text("EXACT OUTPUT").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                                TextEditor(text: $snippet.content)
                                    .font(.system(size: 12))
                                    .frame(minHeight: 58, maxHeight: 90)
                                    .padding(6)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.separator.opacity(0.6)))
                            }
                            Button(role: .destructive) {
                                draft.voiceSnippets.removeAll { $0.id == snippet.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    private var diagnosticsContent: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Run a complete check when dictation or insertion is not working.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Button(appState.diagnosticsRunning ? "Checking…" : "Run Diagnostics") {
                    appState.runDiagnostics()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.diagnosticsRunning)
            }

            settingsCard("System status", icon: "checkmark.shield") {
                ForEach(Array(appState.diagnostics.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        diagnosticIcon(item.state)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 12.5, weight: .medium))
                            Text(item.detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                    }
                    if index < appState.diagnostics.count - 1 { cardDivider }
                }
            }

            HStack {
                Button("Allow Permissions") { appState.requestPermissions() }
                Button("Refresh Status") { appState.refreshPermissions() }
                Spacer()
            }
        }
        .onAppear { appState.runDiagnostics() }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if isTesting {
                ProgressView().controlSize(.small)
            } else if !status.isEmpty {
                Image(systemName: status.hasPrefix("Connected") || status.hasPrefix("Saved") ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(status.hasPrefix("Connected") || status.hasPrefix("Saved") ? .green : .secondary)
            }
            Text(status)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Test Connection") { testConnection() }
                .disabled(isTesting || apiKey.isEmpty)
            Button("Save Changes") { save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
        .background(.bar)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    private var cardDivider: some View {
        Divider().opacity(0.65)
    }

    private func settingsCard<Content: View>(
        _ title: String?,
        icon: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            content()
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.7)
        )
    }

    private func settingRow<Control: View>(
        _ title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            control()
        }
    }

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }

    private func fieldRow(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func secureFieldRow(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            SecureField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color(nsColor: .separatorColor).opacity(0.4), style: StrokeStyle(lineWidth: 0.7, dash: [4]))
        )
    }

    private func save() {
        do {
            draft.personalDictionary = draft.personalDictionary.filter {
                !$0.spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !$0.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            draft.voiceSnippets = draft.voiceSnippets.filter {
                !$0.cue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !$0.content.isEmpty
            }
            try appState.saveSettings(draft, apiKey: apiKey)
            status = "Saved securely"
        } catch {
            status = error.localizedDescription
        }
    }

    private func testConnection() {
        isTesting = true
        status = "Testing connection…"
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
