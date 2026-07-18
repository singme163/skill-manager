import Foundation

/// One-click share: zips a skill and writes a companion markdown note with
/// the description and install instructions (including a Skill Manager
/// deep link when the skill's origin is known).
public enum ShareExporter {
    static let appRepoURL = "https://github.com/singme163/skill-manager"

    @discardableResult
    public static func export(copy: SkillCopy, to folder: URL) throws -> (zip: URL, note: URL) {
        let zip = try SkillInstaller.exportZip(of: copy.directoryURL, to: folder)
        let noteURL = folder.appending(path: "\(copy.directoryURL.lastPathComponent)-分享说明.md")
        try shareNote(for: copy).write(to: noteURL, atomically: true, encoding: .utf8)
        return (zip, noteURL)
    }

    public static func shareNote(for copy: SkillCopy) -> String {
        let name = copy.directoryURL.lastPathComponent
        var lines: [String] = []
        lines.append("# \(copy.displayName)")
        lines.append("")
        if let description = copy.metadataDescription {
            lines.append(description)
            lines.append("")
        }

        lines.append("## \(L("安装方式"))")
        lines.append("")
        if let origin = copy.origin {
            lines.append("- \(L("用 Skill Manager 一键安装（需已安装 App）：")) `skillmanager://install?url=\(origin.sourceURL)`")
            lines.append("- \(L("或从源仓库安装：")) \(origin.sourceURL)")
        }
        lines.append("- \(L("手动安装：解压 \("\(name).zip") 到 ~/.claude/skills/ 或 ~/.codex/skills/"))")
        lines.append("")

        let files = SkillScanner.fileListing(of: copy.directoryURL, limit: 30)
        if !files.isEmpty {
            lines.append("## \(L("包含文件"))")
            lines.append("")
            for file in files {
                lines.append("- `\(file)`")
            }
            lines.append("")
        }

        lines.append("---")
        lines.append(L("由 [Skill Manager](\(appRepoURL)) 导出"))
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
