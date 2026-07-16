import SwiftUI

/// Lightweight block-level Markdown renderer — enough for SKILL.md preview
/// (headings, paragraphs, fenced code, lists, quotes) without dependencies.
/// Inline styling (bold/italic/code/links) is delegated to AttributedString.
struct SimpleMarkdownView: View {
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    render(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .textSelection(.enabled)
        }
    }

    // MARK: - Blocks

    enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case code(String)
        case list(items: [String], ordered: Bool)
        case quote(String)
        case rule
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var listItems: [String] = []
        var listOrdered = false
        var quoteLines: [String] = []
        var inCode = false

        func flushParagraph() {
            if !paragraph.isEmpty {
                result.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }
        func flushList() {
            if !listItems.isEmpty {
                result.append(.list(items: listItems, ordered: listOrdered))
                listItems = []
            }
        }
        func flushQuote() {
            if !quoteLines.isEmpty {
                result.append(.quote(quoteLines.joined(separator: " ")))
                quoteLines = []
            }
        }
        func flushAll() {
            flushParagraph()
            flushList()
            flushQuote()
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCode {
                    result.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []
                    inCode = false
                } else {
                    flushAll()
                    inCode = true
                }
                continue
            }
            if inCode {
                codeLines.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushAll()
                continue
            }

            if line.hasPrefix("#") {
                flushAll()
                let level = line.prefix(while: { $0 == "#" }).count
                let heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                result.append(.heading(level: min(level, 4), text: heading))
                continue
            }
            if line == "---" || line == "***" || line == "___" {
                flushAll()
                result.append(.rule)
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushParagraph()
                flushQuote()
                if !listItems.isEmpty && listOrdered { flushList() }
                listOrdered = false
                listItems.append(String(line.dropFirst(2)))
                continue
            }
            if let match = line.firstMatch(of: /^(\d+)[.)]\s+(.*)$/) {
                flushParagraph()
                flushQuote()
                if !listItems.isEmpty && !listOrdered { flushList() }
                listOrdered = true
                listItems.append(String(match.2))
                continue
            }
            if line.hasPrefix(">") {
                flushParagraph()
                flushList()
                quoteLines.append(line.drop(while: { $0 == ">" }).trimmingCharacters(in: .whitespaces))
                continue
            }

            flushList()
            flushQuote()
            paragraph.append(line)
        }

        if inCode, !codeLines.isEmpty {
            result.append(.code(codeLines.joined(separator: "\n")))
        }
        flushAll()
        return result
    }

    // MARK: - Rendering

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            inlineText(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        case .code(let code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(.callout.monospaced())
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            .background(.quaternary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .foregroundStyle(.secondary)
                        inlineText(item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .quote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 3)
                inlineText(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .rule:
            Divider()
        }
    }

    private func inlineText(_ source: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(source)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title.weight(.bold)
        case 2: return .title2.weight(.semibold)
        case 3: return .title3.weight(.semibold)
        default: return .headline
        }
    }
}
