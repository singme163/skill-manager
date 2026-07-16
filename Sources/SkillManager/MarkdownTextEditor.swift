import SwiftUI
import AppKit

/// NSTextView-backed editor with lightweight Markdown + frontmatter
/// highlighting (regex-based, recolored on every change — SKILL.md files
/// are small enough that this stays instant).
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = Self.baseFont
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        Self.applyHighlighting(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let clamped = NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            )
            textView.setSelectedRange(clamped)
            Self.applyHighlighting(to: textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            MarkdownTextEditor.applyHighlighting(to: textView)
        }
    }

    // MARK: - Highlighting

    static let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

    static func applyHighlighting(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let source = textView.string
        let fullRange = NSRange(location: 0, length: (source as NSString).length)

        storage.beginEditing()
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
        ], range: fullRange)

        func color(_ pattern: String, _ options: NSRegularExpression.Options, _ attrs: [NSAttributedString.Key: Any]) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            regex.enumerateMatches(in: source, range: fullRange) { match, _, _ in
                if let range = match?.range {
                    storage.addAttributes(attrs, range: range)
                }
            }
        }

        // Frontmatter block: delimiters + keys.
        if let fmRegex = try? NSRegularExpression(pattern: "\\A---\\n.*?\\n---", options: [.dotMatchesLineSeparators]),
           let fmMatch = fmRegex.firstMatch(in: source, range: fullRange) {
            storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: fmMatch.range)
            if let keyRegex = try? NSRegularExpression(pattern: "^[A-Za-z0-9_-]+(?=:)", options: [.anchorsMatchLines]) {
                keyRegex.enumerateMatches(in: source, range: fmMatch.range) { match, _, _ in
                    if let range = match?.range {
                        storage.addAttributes([
                            .foregroundColor: NSColor.systemPurple,
                            .font: boldFont,
                        ], range: range)
                    }
                }
            }
        }

        // Headings.
        color("^#{1,6} .*$", [.anchorsMatchLines], [
            .foregroundColor: NSColor.controlAccentColor,
            .font: boldFont,
        ])
        // List markers.
        color("^\\s*([-*+]|\\d+\\.) ", [.anchorsMatchLines], [
            .foregroundColor: NSColor.systemBrown,
        ])
        // Inline code + fence lines.
        color("`[^`\\n]+`", [], [.foregroundColor: NSColor.systemOrange])
        color("^```.*$", [.anchorsMatchLines], [.foregroundColor: NSColor.systemOrange])
        // Bold spans.
        color("\\*\\*[^*\\n]+\\*\\*", [], [.font: boldFont])
        // Links: [text](target)
        color("\\[[^\\]\\n]*\\]\\([^)\\n]+\\)", [], [.foregroundColor: NSColor.systemBlue])

        storage.endEditing()
    }
}
