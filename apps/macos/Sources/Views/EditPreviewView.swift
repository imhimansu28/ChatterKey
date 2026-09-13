import ChatterKeyCore
import SwiftUI

struct EditPreviewView: View {
    let preview: EditPreview
    let recoveryMessage: String?
    let canApplyToTarget: Bool
    let apply: (Bool) -> Void
    let copy: () -> Void
    let discard: () -> Void
    @State private var acknowledgedValues = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review voice edit").font(.title2.bold())
            Text("Nothing has been replaced. Review the changes before applying them.")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let recoveryMessage {
                        Label(recoveryMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if !preview.hasChanges {
                        Text("The model returned the original text unchanged. You can copy it or discard this review.")
                    }
                    HStack(alignment: .top, spacing: 12) {
                        comparison("Original — removals struck through", segments: preview.originalSegments, removal: true)
                        comparison("Proposed — additions underlined", segments: preview.proposedSegments, removal: false)
                    }
                    .frame(height: 280)
                    if preview.usesPassageHighlight {
                        Text("Long text: the changed passage is highlighted instead of individual words.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !preview.valueChanges.isEmpty {
                        Text("Protected values changed").font(.headline).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(preview.valueChanges) { change in
                                Text("\(change.value.kind.rawValue): \(change.value.text) — occurrences \(change.originalCount) → \(change.proposedCount)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .textSelection(.enabled)
                    }
                    Text("Checks compare detected numbers, email addresses, and HTTP(S)/www URLs—not meaning or factual accuracy. Review the full text, even when no warning appears.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            if !preview.valueChanges.isEmpty {
                Toggle("I reviewed the \(preview.valueChanges.count) protected-value changes and want to apply them.", isOn: $acknowledgedValues)
            }
            HStack {
                Button("Discard", role: .cancel, action: discard).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Copy & Close", action: copy)
                Button("Apply to Original", action: { apply(acknowledgedValues) })
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApplyToTarget || !preview.allowsApply(acknowledgingValueChanges: acknowledgedValues))
            }
            Text("Apply rechecks the original field and selection. If that fails, use Copy and paste manually. No extra model request.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(minWidth: 660, minHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func comparison(_ title: String, segments: [EditPreview.Segment], removal: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            ScrollView {
                Text(highlighted(segments, removal: removal))
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func highlighted(_ segments: [EditPreview.Segment], removal: Bool) -> AttributedString {
        segments.reduce(into: AttributedString()) { result, segment in
            var part = AttributedString(segment.text)
            if segment.changed {
                part.backgroundColor = removal ? Color.red.opacity(0.15) : Color.green.opacity(0.15)
                if removal { part.strikethroughStyle = .single } else { part.underlineStyle = .single }
            }
            result.append(part)
        }
    }
}
