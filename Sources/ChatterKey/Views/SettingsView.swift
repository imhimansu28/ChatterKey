import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case dashboard
    case history
    case provider
    case instructions
    case vocabulary
    case snippets
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .dashboard: "Dashboard"
        case .history: "History"
        case .provider: "AI Provider"
        case .instructions: "AI Instructions"
        case .vocabulary: "Vocabulary"
        case .snippets: "Voice Snippets"
        case .diagnostics: "Diagnostics"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Writing, shortcut, and local preferences"
        case .dashboard: "Usage, estimated cost, and speaking insights"
        case .history: "Recent dictations stored locally on this Mac"
        case .provider: "Connection, API key, and model selection"
        case .instructions: "Review and customize how AI prepares your text"
        case .vocabulary: "Names and terms ChatterKey should spell exactly"
        case .snippets: "Reusable text expanded from short voice cues"
        case .diagnostics: "Permissions, shortcut, Keychain, and provider checks"
        }
    }

    var icon: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .dashboard: "chart.xyaxis.line"
        case .history: "clock.arrow.circlepath"
        case .provider: "sparkles"
        case .instructions: "text.bubble"
        case .vocabulary: "character.book.closed"
        case .snippets: "text.badge.plus"
        case .diagnostics: "waveform.path.ecg"
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var selectedSection: SettingsSection = .general
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var navigation = SettingsNavigation.shared
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
                detailFooter
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
                            navigation.selectedSection = section
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
                        .foregroundStyle(navigation.selectedSection == section ? Color.primary : Color.secondary)
                        .padding(.horizontal, 11)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(navigation.selectedSection == section ? Color.accentColor.opacity(0.14) : .clear)
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
            Image(systemName: navigation.selectedSection.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(navigation.selectedSection.title)
                    .font(.system(size: 20, weight: .semibold))
                Text(navigation.selectedSection.subtitle)
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
                switch navigation.selectedSection {
                case .general: generalContent
                case .dashboard: DashboardView(embedded: true)
                case .history: HistoryView(embedded: true)
                case .provider: providerContent
                case .instructions: instructionsContent
                case .vocabulary: vocabularyContent
                case .snippets: snippetsContent
                case .diagnostics: diagnosticsContent
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.visible)
        .animation(nil, value: navigation.selectedSection)
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
                    "Live transcription preview",
                    detail: "Show rough on-device words while speaking. The provider still creates the final result.",
                    isOn: $draft.liveTranscriptionEnabled
                )
                if draft.liveTranscriptionEnabled && !appState.speechRecognitionGranted {
                    HStack {
                        Label("Speech Recognition permission is required for the live preview.", systemImage: "waveform.badge.mic")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Allow") { appState.requestSpeechRecognitionPermission() }
                            .controlSize(.small)
                    }
                    .padding(.top, 8)
                }
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
                        draft.costRates = provider.defaultCostRates
                        apiKey = appState.apiKey(for: provider)
                        status = ""
                    }
                }
                cardDivider
                if draft.provider == .custom {
                    fieldRow("Base URL", placeholder: "https://api.example.com/v1", text: $draft.baseURL)
                } else {
                    settingRow("Base URL", detail: "Fixed to protect your provider API key") {
                        Text(draft.provider.defaultBaseURL)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
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

            settingsCard("Cost estimation", icon: "dollarsign.circle") {
                Text("Dashboard costs are local estimates. Update these rates whenever your provider or model pricing changes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                cardDivider
                numberFieldRow("Transcription", detail: "USD per audio minute", value: $draft.costRates.transcriptionPerMinute)
                cardDivider
                numberFieldRow("Input tokens", detail: "USD per 1 million tokens", value: $draft.costRates.inputPerMillionTokens)
                cardDivider
                numberFieldRow("Output tokens", detail: "USD per 1 million tokens", value: $draft.costRates.outputPerMillionTokens)
                cardDivider
                HStack {
                    Text("Use provider defaults")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Rates") { draft.costRates = draft.provider.defaultCostRates }
                        .controlSize(.small)
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

    private var instructionsContent: some View {
        VStack(spacing: 16) {
            settingsCard("Custom system prompt", icon: "text.bubble") {
                Text("Edit the core instruction used for normal dictation and fast single-pass processing. Writing mode, vocabulary, snippets, and output safeguards are added automatically.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $draft.systemPrompt)
                    .font(.system(size: 11.5, design: .monospaced))
                    .frame(minHeight: 160)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.7)
                    )

                HStack {
                    Text("Stored locally with your app settings.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Default") {
                        draft.systemPrompt = ProviderSettings.defaultSystemPrompt
                    }
                    .controlSize(.small)
                }
            }

            settingsCard("What is always added", icon: "eye") {
                transparencyRow("Selected writing mode", detail: "The active mode adds its exact style and language instruction.")
                cardDivider
                transparencyRow("Your vocabulary and snippet cues", detail: "Saved terms and cue phrases are included so the provider can preserve them.")
                cardDivider
                transparencyRow("Output safeguards", detail: "ChatterKey requests plain text, preserves intent, and blocks invented facts or extra commentary.")
            }

            settingsCard("Exact provider prompt", icon: "doc.text.magnifyingglass") {
                Text("This is the complete writing prompt generated from the current draft settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(ProviderClient(settings: draft, apiKey: "").effectiveProcessingPrompt)
                        .font(.system(size: 10.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(10)
                }
                .frame(height: 150)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.7)
                )
            }

            settingsCard("Magic Voice Edit", icon: "wand.and.stars") {
                Text("Magic Voice Edit uses a separate task-specific instruction so selected text is changed only according to what you say. Your vocabulary is included automatically.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    @ViewBuilder private var detailFooter: some View {
        switch navigation.selectedSection {
        case .dashboard:
            localOnlyFooter("Usage totals and speaking insights stay on this Mac.")
        case .history:
            localOnlyFooter("Transcript history stays on this Mac and follows your retention setting.")
        default:
            footer
        }
    }

    private func localOnlyFooter(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(.green)
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        .background(.bar)
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

    private func transparencyRow(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
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

    private func numberFieldRow(_ title: String, detail: String, value: Binding<Double>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...6)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 120)
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
            if draft.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.systemPrompt = ProviderSettings.defaultSystemPrompt
            }
            if draft.provider != .custom {
                draft.baseURL = draft.provider.defaultBaseURL
            }
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
