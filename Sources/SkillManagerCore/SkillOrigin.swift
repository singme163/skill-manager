import Foundation

/// Provenance sidecar written into a skill folder on install
/// (`.skillmanager.json`): where it came from and at which revision,
/// enabling upstream update checks.
public struct SkillOrigin: Codable, Hashable, Sendable {
    public var sourceURL: String
    public var ref: String?
    public var commit: String?
    public var installedAt: Date

    public static let filename = ".skillmanager.json"

    public init(sourceURL: String, ref: String? = nil, commit: String? = nil, installedAt: Date = .now) {
        self.sourceURL = sourceURL
        self.ref = ref
        self.commit = commit
        self.installedAt = installedAt
    }

    public static func read(from skillDirectory: URL) -> SkillOrigin? {
        let url = skillDirectory.appending(path: filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SkillOrigin.self, from: data)
    }

    public func write(to skillDirectory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: skillDirectory.appending(path: Self.filename))
    }

    /// Whether `latest` (a commit sha) matches the installed revision.
    /// Zipball folder names carry short shas, so compare by prefix.
    public func isCurrent(latest: String) -> Bool {
        guard let commit, !commit.isEmpty, !latest.isEmpty else { return false }
        return latest.hasPrefix(commit) || commit.hasPrefix(latest)
    }
}
