import Foundation

/// Automatic SKILL.md snapshots taken before every in-app save, so edits
/// can be rolled back. Stored under Application Support, capped per skill.
public enum SnapshotStore {
    public struct Snapshot: Identifiable, Hashable, Sendable {
        public let url: URL
        public let date: Date
        public let sizeBytes: Int64

        public var id: String { url.path }
    }

    static let maxPerSkill = 20

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "SkillManager/Snapshots", directoryHint: .isDirectory)
    }

    /// One folder per (tool, skill); deep-scan folder names contain slashes.
    static func directory(for copy: SkillCopy, root: URL) -> URL {
        let safeName = copy.folderName.replacingOccurrences(of: "/", with: "__")
        return root
            .appending(path: copy.tool.id, directoryHint: .isDirectory)
            .appending(path: safeName, directoryHint: .isDirectory)
    }

    /// Saves `contents` as a new snapshot and prunes old ones. Filenames are
    /// monotonically increasing sequence numbers, so rapid consecutive saves
    /// never collide and ordering is deterministic.
    public static func save(contents: String, for copy: SkillCopy, root: URL = defaultRoot) throws {
        let dir = directory(for: copy, root: root)
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let existing = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        let maxSequence = existing
            .compactMap { Int($0.split(separator: ".").first ?? "") }
            .max() ?? 0
        let url = dir.appending(path: String(format: "%08d", maxSequence + 1) + ".md")
        try contents.write(to: url, atomically: true, encoding: .utf8)

        // Prune beyond the cap, oldest first.
        let all = snapshots(for: copy, root: root)
        for stale in all.dropFirst(maxPerSkill) {
            try? fm.removeItem(at: stale.url)
        }
    }

    /// Snapshots for a skill, newest first.
    public static func snapshots(for copy: SkillCopy, root: URL = defaultRoot) -> [Snapshot] {
        let dir = directory(for: copy, root: root)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { $0.pathExtension == "md" }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return Snapshot(
                    url: url,
                    date: values?.contentModificationDate ?? .distantPast,
                    sizeBytes: Int64(values?.fileSize ?? 0)
                )
            }
            .sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }
    }

    public static func read(_ snapshot: Snapshot) -> String? {
        try? String(contentsOf: snapshot.url, encoding: .utf8)
    }
}
