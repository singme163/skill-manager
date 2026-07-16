import Foundation

/// Scans a tool's skills directory into `SkillCopy` values.
/// Tolerant by design: a folder with a missing/invalid SKILL.md is still
/// listed, just flagged, so one bad skill never hides the rest.
public enum SkillScanner {
    public static func scan(tool: Tool) -> [SkillCopy] {
        tool.deepScan
            ? deepScan(directory: tool.skillsDirectory, tool: tool)
            : scan(directory: tool.skillsDirectory, tool: tool)
    }

    /// Recursively finds every SKILL.md folder under `directory` (plugin
    /// caches nest skills several levels deep). `folderName` becomes the
    /// root-relative path so same-named skills from different plugins stay
    /// distinct and never merge with regular skills.
    public static func deepScan(directory: URL, tool: Tool, maxDepth: Int = 8) -> [SkillCopy] {
        let rootPath = directory.standardizedFileURL.path + "/"
        return SkillInstaller.findSkillRoots(in: directory, maxDepth: maxDepth).map { skillDir in
            var relative = skillDir.standardizedFileURL.path
            if relative.hasPrefix(rootPath) { relative.removeFirst(rootPath.count) }
            return makeCopy(directory: skillDir, folderName: relative, tool: tool)
        }
    }

    public static func scan(directory: URL, tool: Tool) -> [SkillCopy] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.compactMap { url -> SkillCopy? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                return nil
            }
            return makeCopy(directory: url, folderName: url.lastPathComponent, tool: tool)
        }
    }

    private static func makeCopy(directory url: URL, folderName: String, tool: Tool) -> SkillCopy {
        let fm = FileManager.default
        let skillFile = url.appending(path: "SKILL.md")
        let hasSkillFile = fm.fileExists(atPath: skillFile.path)

        var metadata: SkillMetadata?
        if hasSkillFile, let text = try? String(contentsOf: skillFile, encoding: .utf8) {
            metadata = FrontmatterParser.parse(markdown: text)
        }

        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast

        return SkillCopy(
            tool: tool,
            directoryURL: url,
            folderName: folderName,
            metadataName: metadata?.name,
            metadataDescription: metadata?.description,
            hasSkillFile: hasSkillFile,
            hasValidMetadata: metadata?.name != nil,
            sizeBytes: directorySize(url),
            modifiedDate: modified
        )
    }

    public static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    /// Flat, sorted, repo-relative file listing for the detail pane (capped).
    public static func fileListing(of directory: URL, limit: Int = 300) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let prefix = directory.standardizedFileURL.path + "/"
        var paths: [String] = []
        for case let fileURL as URL in enumerator {
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            var relative = fileURL.standardizedFileURL.path
            if relative.hasPrefix(prefix) { relative.removeFirst(prefix.count) }
            paths.append(isDir ? relative + "/" : relative)
            if paths.count >= limit { break }
        }
        return paths.sorted()
    }
}
