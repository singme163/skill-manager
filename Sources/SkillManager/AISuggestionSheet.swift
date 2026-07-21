import SwiftUI
import SkillManagerCore

/// Preview-and-confirm sheet for AI-generated content. Generated text is
/// never written to disk automatically — the user sees it here, compares
/// with the original, and only an explicit "采用" applies it (which then
/// goes through the snapshot-backed save, so it's reversible via history).
struct AISuggestionSheet: View {
    @EnvironmentObject private var store: SkillStore
    @Environment(\.dismiss) private var dismiss

    let title: String
    /// The current value, shown for comparison (nil hides the "before" pane).
    let original: String?
    /// Async producer of the suggestion.
    let generate: () async throws -> String
    /// Applies the accepted suggestion (e.g. rewrite frontmatter + save).
    let apply: (String) async -> Void

    @State private var suggestion: String?
    @State private var isWorking = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: "sparkles")
                .font(.title3.weight(.semibold))

            if let original, !original.isEmpty {
                labeledBox(L("原内容"), text: original, mono: false, secondary: true)
            }

            Group {
                if isWorking {
                    HStack {
                        Spacer()
                        ProgressView(L("AI 生成中…"))
                        Spacer()
                    }
                    .frame(minHeight: 120)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label(L("生成失败"), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    }
                    .frame(minHeight: 120)
                } else if let suggestion {
                    labeledBox(L("AI 建议"), text: suggestion, mono: suggestion.contains("\n"), secondary: false)
                }
            }

            HStack {
                Button(L("重新生成")) { run() }
                    .disabled(isWorking)
                Spacer()
                Button(L("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("采用")) {
                    guard let suggestion else { return }
                    Task {
                        await apply(suggestion)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || suggestion == nil)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { run() }
    }

    private func labeledBox(_ label: String, text: String, mono: Bool, secondary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            ScrollView {
                Text(text)
                    .font(mono ? .callout.monospaced() : .callout)
                    .foregroundStyle(secondary ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 60, maxHeight: mono ? 260 : 120)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func run() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                suggestion = try await generate()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
