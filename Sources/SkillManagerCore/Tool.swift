import Foundation

/// A skill source this app manages: an AI tool's skills directory, or a
/// read-only source like the Claude plugin cache. Data-driven so users can
/// add any tool that follows the `<dir>/<skill>/SKILL.md` convention.
public struct Tool: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    /// Short text for the colored badge next to skill names.
    public var badge: String
    public var symbolName: String
    /// May contain `~`; expanded on access.
    public var directoryPath: String
    /// Read-only sources (e.g. plugin cache): no delete/edit/install into.
    public var isReadOnly: Bool
    /// Deep-scanned sources search for SKILL.md recursively instead of
    /// expecting one skill folder per directory entry.
    public var deepScan: Bool
    /// Built-in tools can't be removed, only re-pathed.
    public var isBuiltIn: Bool
    /// Stable position: drives sidebar order and badge color assignment.
    public var sortOrder: Int

    public init(
        id: String,
        name: String,
        badge: String,
        symbolName: String,
        directoryPath: String,
        isReadOnly: Bool = false,
        deepScan: Bool = false,
        isBuiltIn: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.badge = badge
        self.symbolName = symbolName
        self.directoryPath = directoryPath
        self.isReadOnly = isReadOnly
        self.deepScan = deepScan
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
    }

    public var displayName: String { name }

    public var skillsDirectory: URL {
        URL(filePath: (directoryPath as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    }

    /// Legacy (pre-v1.2) per-tool path override key, read once for migration.
    public var pathOverrideDefaultsKey: String { "skillsPathOverride.\(id)" }
}

// MARK: - Built-in presets

extension Tool {
    public static let claudeCode = Tool(
        id: "claudeCode",
        name: "Claude Code",
        badge: "Claude",
        symbolName: "asterisk.circle.fill",
        directoryPath: "~/.claude/skills",
        isBuiltIn: true,
        sortOrder: 0
    )

    public static let codex = Tool(
        id: "codex",
        name: "Codex",
        badge: "Codex",
        symbolName: "chevron.left.forwardslash.chevron.right",
        directoryPath: "~/.codex/skills",
        isBuiltIn: true,
        sortOrder: 1
    )

    public static let claudePlugins = Tool(
        id: "claudePlugins",
        name: L("Claude 插件"),
        badge: L("插件"),
        symbolName: "puzzlepiece",
        directoryPath: "~/.claude/plugins/cache",
        isReadOnly: true,
        deepScan: true,
        sortOrder: 2
    )

    public static let geminiCLI = Tool(
        id: "geminiCLI",
        name: "Gemini CLI",
        badge: "Gemini",
        symbolName: "diamond",
        directoryPath: "~/.gemini/skills",
        sortOrder: 3
    )

    public static let openCode = Tool(
        id: "openCode",
        name: "OpenCode",
        badge: "OpenCode",
        symbolName: "terminal",
        directoryPath: "~/.config/opencode/skills",
        sortOrder: 4
    )

    /// Presets offered in the "add tool" menu.
    public static let presets: [Tool] = [claudeCode, codex, claudePlugins, geminiCLI, openCode]
}

// MARK: - Registry persistence

/// Loads and saves the user's active tool list (UserDefaults-backed JSON).
public enum ToolRegistry {
    static let defaultsKey = "toolRegistry.v1"

    public static func load(defaults: UserDefaults = .standard) -> [Tool] {
        if let data = defaults.data(forKey: defaultsKey),
           let tools = try? JSONDecoder().decode([Tool].self, from: data),
           !tools.isEmpty {
            return tools.sorted { $0.sortOrder < $1.sortOrder }
        }
        return firstRunDefaults(defaults: defaults)
    }

    public static func save(_ tools: [Tool], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(tools) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    /// Initial tool set: Claude Code + Codex (honoring pre-v1.2 path
    /// overrides), plus the plugin cache as a read-only source if present.
    static func firstRunDefaults(defaults: UserDefaults = .standard) -> [Tool] {
        var tools: [Tool] = [.claudeCode, .codex]
        for index in tools.indices {
            if let legacy = defaults.string(forKey: tools[index].pathOverrideDefaultsKey),
               !legacy.trimmingCharacters(in: .whitespaces).isEmpty {
                tools[index].directoryPath = legacy
            }
        }
        if FileManager.default.fileExists(atPath: Tool.claudePlugins.skillsDirectory.path) {
            tools.append(.claudePlugins)
        }
        return tools
    }

    /// Creates a user-defined tool with a fresh id, appended after `existing`.
    public static func makeCustomTool(name: String, directoryPath: String, existing: [Tool]) -> Tool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        return Tool(
            id: "custom-\(UUID().uuidString)",
            name: trimmedName,
            badge: trimmedName.components(separatedBy: " ").first ?? trimmedName,
            symbolName: "wrench.and.screwdriver",
            directoryPath: directoryPath.trimmingCharacters(in: .whitespaces),
            sortOrder: (existing.map(\.sortOrder).max() ?? 0) + 1
        )
    }
}
