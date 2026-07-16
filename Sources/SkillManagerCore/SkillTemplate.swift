import Foundation

/// Built-in scaffolds for new skills.
public enum SkillTemplate: String, CaseIterable, Identifiable, Sendable {
    /// Just a SKILL.md skeleton.
    case basic
    /// SKILL.md + references/ for background documents.
    case reference
    /// SKILL.md + scripts/ with an executable starter script.
    case scripted

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .basic: return L("基础")
        case .reference: return L("参考文档型")
        case .scripted: return L("脚本型")
        }
    }

    public var summary: String {
        switch self {
        case .basic: return L("只有 SKILL.md 骨架，适合纯指令类 skill")
        case .reference: return L("附带 references/ 目录，适合需要背景资料的 skill")
        case .scripted: return L("附带 scripts/ 可执行脚本，适合调用工具的 skill")
        }
    }

    public func markdown(name: String, description: String) -> String {
        let base = FrontmatterParser.templateSkillMarkdown(name: name, description: description)
        switch self {
        case .basic:
            return base
        case .reference:
            return base + "\n\n## References\n\n- [notes](references/notes.md)\n"
        case .scripted:
            return base + "\n\n## Scripts\n\nRun the bundled script:\n\n```bash\nscripts/run.sh\n```\n"
        }
    }

    /// Extra files to scaffold alongside SKILL.md (relative path, contents).
    public var extraFiles: [(path: String, contents: String, executable: Bool)] {
        switch self {
        case .basic:
            return []
        case .reference:
            return [(
                "references/notes.md",
                "# Notes\n\nBackground material this skill relies on.\n",
                false
            )]
        case .scripted:
            return [(
                "scripts/run.sh",
                "#!/bin/bash\nset -euo pipefail\n\necho \"TODO: implement\"\n",
                true
            )]
        }
    }
}
