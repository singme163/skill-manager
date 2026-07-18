import Foundation

/// Structure-preserving translation plan for a markdown document: splits it
/// into fixed lines (code, blanks, lines already in the target language)
/// and translatable text segments with their markdown prefixes (heading
/// markers, list bullets, quote markers) kept aside, so the translated
/// document reassembles with formatting intact.
public struct MarkdownTranslationPlan: Sendable {
    public enum Line: Equatable, Sendable {
        case fixed(String)
        case translatable(prefix: String, segmentIndex: Int)
    }

    public let lines: [Line]
    /// The texts to hand to the translator, in order.
    public let segments: [String]
    /// True when the character budget cut translation short.
    public let truncated: Bool

    public init(lines: [Line], segments: [String], truncated: Bool) {
        self.lines = lines
        self.segments = segments
        self.truncated = truncated
    }

    public static func make(
        markdown: String,
        targetIsChinese: Bool,
        characterBudget: Int = 30000
    ) -> MarkdownTranslationPlan {
        var lines: [Line] = []
        var segments: [String] = []
        var inCode = false
        var used = 0
        var truncated = false

        for raw in markdown.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                inCode.toggle()
                lines.append(.fixed(raw))
                continue
            }
            if inCode || trimmed.isEmpty {
                lines.append(.fixed(raw))
                continue
            }

            let prefix = markdownPrefix(of: raw)
            let text = String(raw.dropFirst(prefix.count))
            let hasWords = text.contains { $0.isLetter }
            let alreadyTarget = targetIsChinese
                ? TextLanguage.isDominantlyCJK(text)
                : !TextLanguage.isDominantlyCJK(text)

            if !hasWords || alreadyTarget {
                lines.append(.fixed(raw))
                continue
            }
            if used + text.count > characterBudget {
                truncated = true
                lines.append(.fixed(raw))
                continue
            }
            used += text.count
            lines.append(.translatable(prefix: prefix, segmentIndex: segments.count))
            segments.append(text)
        }

        return MarkdownTranslationPlan(lines: lines, segments: segments, truncated: truncated)
    }

    /// Leading markdown structure marker to keep verbatim: heading hashes,
    /// list bullets, ordered-list numbers, blockquote markers.
    static func markdownPrefix(of line: String) -> String {
        guard let match = line.prefixMatch(of: /^(\s*(?:#{1,6}\s+|[-*+]\s+|\d+[.)]\s+|>\s*)?)/) else {
            return ""
        }
        return String(match.1)
    }

    public func reassembled(with translations: [String]) -> String {
        lines.map { line in
            switch line {
            case .fixed(let text):
                return text
            case .translatable(let prefix, let index):
                return prefix + (index < translations.count ? translations[index] : "")
            }
        }.joined(separator: "\n")
    }
}
