import Foundation

public struct InstallCandidate: Identifiable, Hashable, Sendable {
    public let name: String
    public let sourceDirectory: URL
    /// Provenance to record on install (set by the GitHub pipeline).
    public var origin: SkillOrigin?

    public init(name: String, sourceDirectory: URL, origin: SkillOrigin? = nil) {
        self.name = name
        self.sourceDirectory = sourceDirectory
        self.origin = origin
    }

    public var id: String { sourceDirectory.path }
}

public enum InstallError: LocalizedError, Equatable {
    case noSkillFound
    case alreadyExists(name: String, tool: Tool)
    case invalidGitHubURL
    case downloadFailed(String)
    case unzipFailed(String)
    case invalidName(String)
    case readOnlyTool(String)

    public var errorDescription: String? {
        switch self {
        case .noSkillFound:
            return L("没有找到包含 SKILL.md 的 skill 目录。")
        case .readOnlyTool(let name):
            return L("「\(name)」是只读来源，不能安装或修改。")
        case .alreadyExists(let name, let tool):
            return L("\(tool.displayName) 中已存在同名 skill「\(name)」。")
        case .invalidGitHubURL:
            return L("无法识别的 GitHub 链接。支持仓库或仓库子目录链接，例如 https://github.com/org/repo 或 …/tree/main/skills/foo。")
        case .downloadFailed(let reason):
            return L("下载失败：\(reason)")
        case .unzipFailed(let reason):
            return L("解压失败：\(reason)")
        case .invalidName(let name):
            return L("「\(name)」不是合法的 skill 名称（只允许小写字母、数字和连字符）。")
        }
    }
}

/// All write-side operations: import, template creation, cross-tool copy,
/// GitHub install. Every install goes "stage in temp → copy into place";
/// overwrite moves the old version to the Trash first, never hard-deletes.
public enum SkillInstaller {
    // MARK: - Discovery

    /// Finds skill roots (directories containing SKILL.md) under `url`,
    /// searching a few levels deep to tolerate zip/GitHub nesting.
    public static func findSkillRoots(in url: URL, maxDepth: Int = 4) -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []

        func walk(_ dir: URL, depth: Int) {
            if fm.fileExists(atPath: dir.appending(path: "SKILL.md").path) {
                results.append(dir)
                return // a skill root's subfolders are its resources, not more skills
            }
            guard depth < maxDepth,
                  let children = try? fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                  ) else { return }
            for child in children
            where (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                walk(child, depth: depth + 1)
            }
        }

        walk(url.standardizedFileURL, depth: 0)
        return results.sorted { $0.path < $1.path }
    }

    // MARK: - Import (local folder / zip)

    /// Stages a local folder or .zip and returns the install candidates found inside.
    public static func prepareImport(from source: URL) throws -> [InstallCandidate] {
        let fm = FileManager.default
        var root = source

        if source.pathExtension.lowercased() == "zip" {
            let tempDir = try makeTempDirectory()
            try unzip(source, to: tempDir)
            root = tempDir
        }

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw InstallError.noSkillFound
        }

        let roots = findSkillRoots(in: root)
        guard !roots.isEmpty else { throw InstallError.noSkillFound }
        return roots.map { InstallCandidate(name: $0.lastPathComponent, sourceDirectory: $0) }
    }

    // MARK: - Install

    public static func install(candidate: InstallCandidate, to tool: Tool, overwrite: Bool) throws {
        guard !tool.isReadOnly else { throw InstallError.readOnlyTool(tool.displayName) }
        try install(candidate: candidate, intoDirectory: tool.skillsDirectory, tool: tool, overwrite: overwrite)
    }

    public static func install(
        candidate: InstallCandidate,
        intoDirectory skillsDir: URL,
        tool: Tool,
        overwrite: Bool
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)

        let destination = skillsDir.appending(path: candidate.name, directoryHint: .isDirectory)
        if fm.fileExists(atPath: destination.path) {
            guard overwrite else {
                throw InstallError.alreadyExists(name: candidate.name, tool: tool)
            }
            try fm.trashItem(at: destination, resultingItemURL: nil)
        }
        try fm.copyItem(at: candidate.sourceDirectory, to: destination)
        if let origin = candidate.origin {
            try? origin.write(to: destination)
        }
    }

    // MARK: - New blank template

    @discardableResult
    public static func createTemplate(
        name: String,
        description: String,
        template: SkillTemplate = .basic,
        inDirectory skillsDir: URL,
        tool: Tool
    ) throws -> URL {
        guard FrontmatterParser.isValidSkillName(name) else {
            throw InstallError.invalidName(name)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)

        let destination = skillsDir.appending(path: name, directoryHint: .isDirectory)
        guard !fm.fileExists(atPath: destination.path) else {
            throw InstallError.alreadyExists(name: name, tool: tool)
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: false)
        let markdown = template.markdown(name: name, description: description)
        try markdown.write(to: destination.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

        for file in template.extraFiles {
            let fileURL = destination.appending(path: file.path)
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.contents.write(to: fileURL, atomically: true, encoding: .utf8)
            if file.executable {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
            }
        }
        return destination
    }

    @discardableResult
    public static func createTemplate(
        name: String,
        description: String,
        template: SkillTemplate = .basic,
        tool: Tool
    ) throws -> URL {
        try createTemplate(
            name: name, description: description, template: template,
            inDirectory: tool.skillsDirectory, tool: tool
        )
    }

    // MARK: - Cross-tool copy

    public static func copySkill(_ copy: SkillCopy, to tool: Tool, overwrite: Bool) throws {
        // Use the physical folder name, not `folderName`: deep-scanned copies
        // (plugin skills) carry a root-relative path there.
        let candidate = InstallCandidate(
            name: copy.directoryURL.lastPathComponent,
            sourceDirectory: copy.directoryURL
        )
        try install(candidate: candidate, to: tool, overwrite: overwrite)
    }

    // MARK: - GitHub install

    public struct GitHubTarget: Equatable, Sendable {
        public let owner: String
        public let repo: String
        public let ref: String?
        public let subpath: String?

        public var zipballURL: URL {
            var path = "https://api.github.com/repos/\(owner)/\(repo)/zipball"
            if let ref { path += "/\(ref)" }
            return URL(string: path)!
        }
    }

    /// Accepts `https://github.com/org/repo`, `…/repo.git`, and
    /// `…/repo/tree/<ref>/<subpath>` forms.
    public static func parseGitHubURL(_ raw: String) -> GitHubTarget? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host(), host == "github.com" || host == "www.github.com" else {
            return nil
        }
        var parts = url.path().split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }

        let owner = parts.removeFirst()
        var repo = parts.removeFirst()
        if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        guard !owner.isEmpty, !repo.isEmpty else { return nil }

        var ref: String?
        var subpath: String?
        if let marker = parts.first, marker == "tree" || marker == "blob" {
            parts.removeFirst()
            guard !parts.isEmpty else { return nil }
            ref = parts.removeFirst()
            if !parts.isEmpty { subpath = parts.joined(separator: "/") }
        } else if !parts.isEmpty {
            return nil
        }
        return GitHubTarget(owner: owner, repo: repo, ref: ref, subpath: subpath)
    }

    /// Downloads a public repo zipball, extracts it, and returns candidates.
    public static func downloadFromGitHub(_ raw: String) async throws -> [InstallCandidate] {
        guard let target = parseGitHubURL(raw) else { throw InstallError.invalidGitHubURL }

        let request = GitHubAuth.request(for: target.zipballURL)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw InstallError.downloadFailed(L("HTTP \(http.statusCode)（私有仓库需在设置中配置 GitHub Token，请检查链接与网络）"))
        }

        let tempDir = try makeTempDirectory()
        let zipURL = tempDir.appending(path: "repo.zip")
        try data.write(to: zipURL)
        let extractDir = tempDir.appending(path: "extracted", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try unzip(zipURL, to: extractDir)

        // Zipball wraps everything in a single "owner-repo-sha" folder.
        let fm = FileManager.default
        let topLevel = (try? fm.contentsOfDirectory(
            at: extractDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var searchRoot = extractDir
        var commit: String?
        if topLevel.count == 1,
           (try? topLevel[0].resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            searchRoot = topLevel[0]
            // The wrapper folder is "<owner>-<repo>-<sha>" — harvest the sha.
            commit = shaSuffix(of: searchRoot.lastPathComponent)
        }
        if let subpath = target.subpath {
            searchRoot = searchRoot.appending(path: subpath)
        }

        let origin = SkillOrigin(
            sourceURL: raw.trimmingCharacters(in: .whitespacesAndNewlines),
            ref: target.ref,
            commit: commit
        )
        let roots = findSkillRoots(in: searchRoot)
        guard !roots.isEmpty else { throw InstallError.noSkillFound }
        return roots.map {
            InstallCandidate(name: $0.lastPathComponent, sourceDirectory: $0, origin: origin)
        }
    }

    /// Extracts the trailing commit sha from a zipball wrapper folder name
    /// ("owner-repo-abc1234"). Returns nil when the suffix isn't hex-like.
    static func shaSuffix(of wrapperFolderName: String) -> String? {
        guard let last = wrapperFolderName.split(separator: "-").last else { return nil }
        let sha = String(last)
        let isHex = sha.count >= 7 && sha.allSatisfy { $0.isHexDigit }
        return isHex ? sha : nil
    }

    /// Latest commit sha upstream for an installed skill's source.
    /// Uses the GitHub "sha" media type, which returns the bare sha.
    public static func latestCommit(for target: GitHubTarget) async throws -> String {
        let url = URL(string: "https://api.github.com/repos/\(target.owner)/\(target.repo)/commits/\(target.ref ?? "HEAD")")!
        var request = GitHubAuth.request(for: url)
        request.setValue("application/vnd.github.sha", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let sha = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !sha.isEmpty else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw InstallError.downloadFailed("HTTP \(code)")
        }
        return sha
    }

    // MARK: - Export

    /// Zips a skill folder into `destinationFolder/<name>.zip` (overwriting).
    @discardableResult
    public static func exportZip(of skillDirectory: URL, to destinationFolder: URL) throws -> URL {
        let zipURL = destinationFolder.appending(path: "\(skillDirectory.lastPathComponent).zip")
        try? FileManager.default.removeItem(at: zipURL)
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", skillDirectory.path, zipURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallError.unzipFailed("ditto exit \(process.terminationStatus)")
        }
        return zipURL
    }

    // MARK: - Helpers

    public static func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "SkillManager-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Extracts a zip using the system `ditto` tool (no third-party deps).
    public static func unzip(_ zip: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, destination.path]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            throw InstallError.unzipFailed(String(data: data, encoding: .utf8) ?? "ditto exit \(process.terminationStatus)")
        }
    }
}
