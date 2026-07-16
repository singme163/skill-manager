import Foundation

/// A CLI agent tool whose skills this app manages.
public enum Tool: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case claudeCode
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    public var symbolName: String {
        switch self {
        case .claudeCode: return "asterisk.circle.fill"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// UserDefaults key for a user-provided skills directory override.
    public var pathOverrideDefaultsKey: String { "skillsPathOverride.\(rawValue)" }

    public var defaultSkillsDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claudeCode: return home.appending(path: ".claude/skills", directoryHint: .isDirectory)
        case .codex: return home.appending(path: ".codex/skills", directoryHint: .isDirectory)
        }
    }

    /// The effective skills directory, honoring the settings override.
    public var skillsDirectory: URL {
        if let override = UserDefaults.standard.string(forKey: pathOverrideDefaultsKey),
           !override.trimmingCharacters(in: .whitespaces).isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(filePath: expanded, directoryHint: .isDirectory)
        }
        return defaultSkillsDirectory
    }
}
