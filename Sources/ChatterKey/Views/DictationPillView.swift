import SwiftUI

struct DictationPillView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.045, green: 0.045, blue: 0.055).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 0.75)
                )

            phaseVisual
                .transition(.scale(scale: 0.72).combined(with: .opacity))
                .id(phaseID)
        }
        .frame(width: 76, height: 44)
        .padding(5)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: phaseID)
    }

    @ViewBuilder private var phaseVisual: some View {
        switch appState.phase {
        case .listening:
            ListeningWaveformView()
        case .processing:
            ProcessingDotsView()
        case .inserted:
            CompletionCheckView()
        case .failed:
            statusIcon("exclamationmark", color: .orange)
        case .idle:
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
        }
    }

    private var phaseID: String {
        switch appState.phase {
        case .idle: "idle"
        case .listening: "listening"
        case .processing: "processing"
        case .inserted: "inserted"
        case .failed: "failed"
        }
    }

    private func statusIcon(_ name: String, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

private struct ListeningWaveformView: View {
    @State private var animate = false
    private let heights: [CGFloat] = [8, 15, 23, 13, 28, 17, 24, 14, 9]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(.white.opacity(0.94))
                    .frame(width: 2.5, height: animate ? height : max(5, height * 0.32))
                    .animation(
                        .easeInOut(duration: 0.36)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.045),
                        value: animate
                    )
            }
        }
        .frame(width: 44, height: 30)
        .onAppear { animate = true }
    }
}

private struct ProcessingDotsView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.indigo.opacity(0.95))
                    .frame(width: 6, height: 6)
                    .offset(y: animate ? -4 : 4)
                    .animation(
                        .easeInOut(duration: 0.42)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: animate
                    )
            }
        }
        .frame(width: 40, height: 28)
        .onAppear { animate = true }
    }
}

private struct CompletionCheckView: View {
    @State private var appeared = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 29, height: 29)
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            )
            .scaleEffect(appeared ? 1 : 0.45)
            .opacity(appeared ? 1 : 0)
            .onAppear { appeared = true }
            .animation(.spring(response: 0.3, dampingFraction: 0.62), value: appeared)
    }
}
