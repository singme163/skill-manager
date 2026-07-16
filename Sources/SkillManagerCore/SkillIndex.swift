import Foundation

/// One entry in the curated discovery index.
public struct SkillIndexEntry: Codable, Identifiable, Hashable, Sendable {
    public var name: String
    public var description: String
    public var author: String
    /// GitHub repository or subdirectory link, installable via the existing
    /// GitHub install pipeline.
    public var url: String
    public var tags: [String]?

    public var id: String { url }

    public init(name: String, description: String, author: String, url: String, tags: [String]? = nil) {
        self.name = name
        self.description = description
        self.author = author
        self.url = url
        self.tags = tags
    }
}

/// Loads the curated index: remote first (community-maintained via PRs to
/// the app repository), falling back to the bundled snapshot when offline.
public enum SkillIndexLoader {
    public static let remoteURL =
        URL(string: "https://raw.githubusercontent.com/singme163/skill-manager/main/index/skills.json")!

    public struct Result: Sendable {
        public let entries: [SkillIndexEntry]
        public let fromRemote: Bool
    }

    public static func load() async -> Result {
        if let (data, response) = try? await URLSession.shared.data(from: remoteURL),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let entries = try? JSONDecoder().decode([SkillIndexEntry].self, from: data),
           !entries.isEmpty {
            return Result(entries: entries, fromRemote: true)
        }
        return Result(entries: bundled(), fromRemote: false)
    }

    public static func bundled() -> [SkillIndexEntry] {
        guard let url = Bundle.module.url(forResource: "skills-index", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([SkillIndexEntry].self, from: data) else {
            return []
        }
        return entries
    }
}
