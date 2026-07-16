import Foundation

public struct LintIssue: Identifiable, Hashable, Sendable {
    public enum Severity: Int, Comparable, Sendable {
        case info = 0
        case warning = 1
        case error = 2

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let severity: Severity
    public let ruleID: String
    public let message: String

    public var id: String { "\(ruleID):\(message)" }

    public init(severity: Severity, ruleID: String, message: String) {
        self.severity = severity
        self.ruleID = ruleID
        self.message = message
    }
}

/// Static quality checks for a SKILL.md — helps users write skills that
/// tools can recognize and reliably auto-trigger.
public enum SkillLinter {
    /// Description length guidance (characters).
    static let minDescriptionLength = 20
    static let maxDescriptionLength = 1024

    public static func lint(copy: SkillCopy) -> [LintIssue] {
        guard let markdown = try? String(contentsOf: copy.skillFileURL, encoding: .utf8) else {
            return [LintIssue(
                severity: .error,
                ruleID: "skill-file-missing",
                message: L("缺少 SKILL.md 文件")
            )]
        }
        return lint(markdown: markdown, folderName: copy.directoryURL.lastPathComponent, directory: copy.directoryURL)
    }

    /// Lints markdown content. `directory` enables relative-link existence
    /// checks; pass nil to skip them (e.g. unsaved buffers).
    public static func lint(markdown: String, folderName: String, directory: URL?) -> [LintIssue] {
        var issues: [LintIssue] = []

        let keys = FrontmatterParser.parseKeys(markdown: markdown)
        guard let keys else {
            issues.append(LintIssue(
                severity: .error,
                ruleID: "frontmatter-missing",
                message: L("缺少合法的 frontmatter（文件需以 --- 包裹的元数据块开头）")
            ))
            return issues + lintBody(markdown: markdown, directory: directory)
        }

        // name
        if let name = keys["name"], !name.isEmpty {
            if name != folderName {
                issues.append(LintIssue(
                    severity: .warning,
                    ruleID: "name-mismatch",
                    message: L("name「\(name)」与目录名「\(folderName)」不一致，工具可能无法识别")
                ))
            }
            if !FrontmatterParser.isValidSkillName(name) {
                issues.append(LintIssue(
                    severity: .warning,
                    ruleID: "name-format",
                    message: L("name「\(name)」格式不规范（建议小写字母、数字、连字符）")
                ))
            }
        } else {
            issues.append(LintIssue(
                severity: .error,
                ruleID: "name-missing",
                message: L("frontmatter 缺少 name 字段")
            ))
        }

        // description
        if let description = keys["description"], !description.isEmpty {
            if description.count < minDescriptionLength {
                issues.append(LintIssue(
                    severity: .warning,
                    ruleID: "description-short",
                    message: L("description 过短（\(description.count) 字符），触发关键词太少，自动触发容易失灵")
                ))
            }
            if description.count > maxDescriptionLength {
                issues.append(LintIssue(
                    severity: .warning,
                    ruleID: "description-long",
                    message: L("description 过长（\(description.count) 字符），建议精简到 1024 字符以内")
                ))
            }
            if !containsTriggerHint(description) {
                issues.append(LintIssue(
                    severity: .info,
                    ruleID: "trigger-hint",
                    message: L("description 未说明使用场景，建议包含「Use when …」或「用于/当…时使用」等触发提示")
                ))
            }
        } else {
            issues.append(LintIssue(
                severity: .error,
                ruleID: "description-missing",
                message: L("frontmatter 缺少 description 字段，无法自动触发")
            ))
        }

        return issues + lintBody(markdown: markdown, directory: directory)
    }

    static func containsTriggerHint(_ description: String) -> Bool {
        let lowered = description.lowercased()
        let englishHints = ["use when", "use this", "use it when", "trigger", "use for", "when the user", "when asked"]
        if englishHints.contains(where: { lowered.contains($0) }) { return true }
        let chineseHints = ["用于", "当用户", "使用场景", "时使用", "需要", "适用"]
        return chineseHints.contains(where: { description.contains($0) })
    }

    private static func lintBody(markdown: String, directory: URL?) -> [LintIssue] {
        var issues: [LintIssue] = []

        let body = stripFrontmatter(markdown).trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            issues.append(LintIssue(
                severity: .warning,
                ruleID: "body-empty",
                message: L("正文为空，建议补充说明与步骤")
            ))
        }

        if let directory {
            for path in relativeLinkTargets(in: markdown)
            where !FileManager.default.fileExists(atPath: directory.appending(path: path).path) {
                issues.append(LintIssue(
                    severity: .error,
                    ruleID: "broken-link",
                    message: L("引用的文件不存在：\(path)")
                ))
            }
        }

        return issues
    }

    /// Relative file paths referenced by markdown links/images in the body.
    static func relativeLinkTargets(in markdown: String) -> [String] {
        var targets: [String] = []
        for match in markdown.matches(of: /\[[^\]]*\]\(([^)\s]+)\)/) {
            var path = String(match.1)
            if path.hasPrefix("http://") || path.hasPrefix("https://")
                || path.hasPrefix("mailto:") || path.hasPrefix("#")
                || path.hasPrefix("/") {
                continue
            }
            if let anchor = path.firstIndex(of: "#") {
                path = String(path[path.startIndex..<anchor])
            }
            path = path.removingPercentEncoding ?? path
            if !path.isEmpty, !targets.contains(path) {
                targets.append(path)
            }
        }
        return targets
    }

    static func stripFrontmatter(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return text
        }
        for index in 1..<lines.count
        where lines[index].trimmingCharacters(in: .whitespaces) == "---" {
            lines.removeSubrange(0...index)
            return lines.joined(separator: "\n")
        }
        return text
    }
}
