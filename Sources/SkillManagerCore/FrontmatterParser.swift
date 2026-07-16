import Foundation

public struct SkillMetadata: Equatable, Sendable {
    public var name: String?
    public var description: String?

    public init(name: String? = nil, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

/// Minimal YAML frontmatter reader — extracts top-level scalar keys from the
/// leading `---` block of a SKILL.md. Handles plain, quoted, and folded (`>`
/// / `|`) values, which covers the frontmatter Claude Code and Codex emit.
public enum FrontmatterParser {
    /// Returns nil when the document has no (or an unterminated) frontmatter block.
    public static func parseKeys(markdown: String) -> [String: String]? {
        var lines = markdown.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }
        lines.removeFirst()

        var keys: [String: String] = [:]
        var terminated = false
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                terminated = true
                break
            }
            // Only top-level `key: value` pairs (no leading indentation).
            if !line.hasPrefix(" "), !line.hasPrefix("\t"),
               let colon = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty, !key.hasPrefix("#") {
                    if value.isEmpty || value == ">" || value == "|" || value == ">-" || value == "|-" {
                        // Folded / literal block: gather following indented lines.
                        var parts: [String] = []
                        var lookahead = index + 1
                        while lookahead < lines.count {
                            let next = lines[lookahead]
                            let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                            if nextTrimmed == "---" { break }
                            if next.hasPrefix(" ") || next.hasPrefix("\t") || nextTrimmed.isEmpty {
                                if !nextTrimmed.isEmpty { parts.append(nextTrimmed) }
                                lookahead += 1
                            } else {
                                break
                            }
                        }
                        index = lookahead - 1
                        value = parts.joined(separator: " ")
                    } else {
                        value = stripQuotes(value)
                    }
                    if !value.isEmpty { keys[key] = value }
                }
            }
            index += 1
        }

        return terminated ? keys : nil
    }

    public static func parse(markdown: String) -> SkillMetadata? {
        guard let keys = parseKeys(markdown: markdown) else { return nil }
        return SkillMetadata(name: keys["name"], description: keys["description"])
    }

    private static func stripQuotes(_ value: String) -> String {
        for quote in ["\"", "'"] where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    /// Generates a spec-compliant SKILL.md skeleton for a new blank skill.
    public static func templateSkillMarkdown(name: String, description: String) -> String {
        """
        ---
        name: \(name)
        description: \(description)
        ---

        # \(name)

        ## Overview

        Describe what this skill does and when it should be used.

        ## Instructions

        1. Step one.
        2. Step two.

        ## Resources

        List any bundled references, scripts, or assets here.
        """
    }

    /// Validates a skill folder name: lowercase letters/digits, hyphen separated.
    public static func isValidSkillName(_ name: String) -> Bool {
        let pattern = /^[a-z0-9]+(-[a-z0-9]+)*$/
        return name.wholeMatch(of: pattern) != nil
    }
}
