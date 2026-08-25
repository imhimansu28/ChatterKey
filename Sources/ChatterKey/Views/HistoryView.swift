import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    var embedded = false

    @ViewBuilder var body: some View {
        if embedded {
            embeddedContent
        } else {
            VStack(spacing: 0) {
                header
                Divider()
                content
            }
            .frame(minWidth: 560, idealWidth: 620, minHeight: 460, idealHeight: 560)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text("Dictation History")
                    .font(.system(size: 20, weight: .semibold))
                Text(historySubtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !appState.history.isEmpty {
                Button("Clear All", role: .destructive) { appState.clearHistory() }
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 78)
    }

    @ViewBuilder private var embeddedContent: some View {
        if !appState.settings.historyEnabled {
            emptyState(
                icon: "clock.badge.xmark",
                title: "History is turned off",
                detail: "Enable local transcript history in General settings to keep recent dictations on this Mac.",
                actionTitle: "Open General"
            ) {
                SettingsNavigation.shared.selectedSection = .general
            }
            .frame(minHeight: 360)
        } else if appState.history.isEmpty {
            emptyState(
                icon: "text.badge.checkmark",
                title: "No dictations yet",
                detail: "Your recent dictations will appear here after you use ChatterKey.",
                actionTitle: nil,
                action: nil
            )
            .frame(minHeight: 360)
        } else {
            HStack {
                Text("\(appState.history.count) locally stored dictation\(appState.history.count == 1 ? "" : "s")")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All", role: .destructive) { appState.clearHistory() }
            }
            LazyVStack(spacing: 10) {
                ForEach(appState.history) { item in
                    historyRow(item)
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if !appState.settings.historyEnabled {
            emptyState(
                icon: "clock.badge.xmark",
                title: "History is turned off",
                detail: "Enable local transcript history in Settings to keep recent dictations on this Mac.",
                actionTitle: "Open Settings"
            ) {
                SettingsWindowController.shared.show(appState: appState)
            }
        } else if appState.history.isEmpty {
            emptyState(
                icon: "text.badge.checkmark",
                title: "No dictations yet",
                detail: "Your recent dictations will appear here after you use ChatterKey.",
                actionTitle: nil,
                action: nil
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(appState.history) { item in
                        historyRow(item)
                    }
                }
                .padding(20)
            }
        }
    }

    private func historyRow(_ item: DictationHistoryItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.text)
                    .font(.system(size: 12.5))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 7) {
                    Text(item.outputMode.shortTitle)
                    Text("•")
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            }
            Button { appState.copy(item.text) } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy")
            Button { SettingsWindowController.shared.insert(item, appState: appState) } label: {
                Image(systemName: "arrow.turn.down.left")
            }
            .help("Insert in the focused app")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.7)
        )
    }

    private func emptyState(
        icon: String,
        title: String,
        detail: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var historySubtitle: String {
        guard appState.settings.historyEnabled else { return "Stored locally only when enabled" }
        return "\(appState.history.count) recent dictation\(appState.history.count == 1 ? "" : "s") stored locally"
    }
}
