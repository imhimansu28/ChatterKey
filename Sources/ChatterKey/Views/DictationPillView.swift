import SwiftUI

struct DictationPillView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 14) {
            statusVisual
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if case .failed = appState.phase {
                HStack(spacing: 6) {
                    if appState.canRetry {
                        Button("Retry") { appState.retryLastDictation() }
                            .buttonStyle(PillButtonStyle())
                    }
                    Button("Dismiss") { appState.cancel() }
                        .buttonStyle(PillButtonStyle())
                }
            } else if appState.phase == .processing {
                ProgressView().controlSize(.small).tint(.white)
            } else if appState.phase == .listening {
                WaveformView()
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 334, height: 82)
        .background(
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(Color(red: 0.055, green: 0.055, blue: 0.065).opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.42), radius: 28, y: 12)
        .padding(6)
    }

    @ViewBuilder private var statusVisual: some View {
        switch appState.phase {
        case .listening:
            MicPulseView()
        case .processing:
            Circle().fill(Color.indigo)
                .overlay(Image(systemName: "sparkles").font(.system(size: 17, weight: .bold)).foregroundStyle(.white))
        case .inserted:
            Circle().fill(Color.green)
                .overlay(Image(systemName: "checkmark").font(.system(size: 17, weight: .bold)).foregroundStyle(.white))
        case .failed:
            Circle().fill(Color.orange)
                .overlay(Image(systemName: "exclamationmark").font(.system(size: 17, weight: .bold)).foregroundStyle(.white))
        case .idle:
            Circle().fill(Color.white.opacity(0.1))
                .overlay(Image(systemName: "mic.fill").foregroundStyle(.white))
        }
    }

    private var title: String {
        switch appState.phase {
        case .idle: "Ready"
        case .listening: "Listening"
        case .processing: "Making it flow"
        case .inserted: "Inserted"
        case .failed: "Couldn’t transcribe"
        }
    }

    private var subtitle: String {
        switch appState.phase {
        case .idle: "Hold \(appState.settings.hotkeyShortcut.title) to talk"
        case .listening: "Release \(appState.settings.hotkeyShortcut.title) to insert"
        case .processing: "Applying \(appState.settings.outputMode.shortTitle)…"
        case .inserted: "Text is ready"
        case .failed(let message): message
        }
    }
}

private struct MicPulseView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.red.opacity(pulse ? 0.0 : 0.45), lineWidth: 2)
                .scaleEffect(pulse ? 1.45 : 0.82)
            Circle()
                .fill(Color.red.opacity(0.18))
                .scaleEffect(pulse ? 1.12 : 0.92)
            Circle()
                .fill(Color(red: 0.96, green: 0.20, blue: 0.28))
                .frame(width: 36, height: 36)
                .shadow(color: .red.opacity(0.45), radius: 10)
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
        }
        .onAppear { pulse = true }
        .animation(.easeOut(duration: 0.9).repeatForever(autoreverses: false), value: pulse)
    }
}

private struct WaveformView: View {
    @State private var animate = false
    private let heights: [CGFloat] = [11, 21, 31, 17, 26, 13, 22]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(.white.opacity(0.92))
                    .frame(width: 3, height: animate ? height : max(6, height * 0.28))
                    .animation(
                        .easeInOut(duration: 0.42).repeatForever(autoreverses: true).delay(Double(index) * 0.055),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

private struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(configuration.isPressed ? 0.2 : 0.12), in: Capsule())
    }
}
