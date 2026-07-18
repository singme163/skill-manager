import Foundation

public enum SyncError: LocalizedError {
    case notConfigured
    case gitFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return L("尚未配置同步仓库，请先在设置中填写远端地址并初始化。")
        case .gitFailed(let message):
            return L("git 操作失败：\(message)")
        }
    }
}

public struct SyncSummary: Sendable {
    public let mirroredSkills: Int
    public let pushed: Bool
}

/// Multi-machine sync through the user's own git repository — no server of
/// ours involved. A working clone lives under Application Support; pushing
/// mirrors every writable tool's skills into `<toolID>/<skill>/`, commits,
/// rebases onto the remote, and pushes. Pulling scans that layout back into
/// install candidates.
public enum SyncEngine {
    public static let remoteDefaultsKey = "sync.remoteURL"
    public static let lastSyncDefaultsKey = "sync.lastAt"

    public static var defaultRepoDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "SkillManager/SyncRepo", directoryHint: .isDirectory)
    }

    public static func isConfigured(repoDir: URL = defaultRepoDirectory) -> Bool {
        FileManager.default.fileExists(atPath: repoDir.appending(path: ".git").path)
    }

    // MARK: - git plumbing

    @discardableResult
    static func git(_ args: [String], in dir: URL?) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = args
        if let dir { process.currentDirectoryURL = dir }
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0" // fail fast instead of prompting
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SyncError.gitFailed(error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    // MARK: - Setup

    /// Clones the remote into the sync directory (or repoints origin when a
    /// clone already exists). Falls back to `git init` + remote add when the
    /// remote can't be cloned yet.
    public static func configure(remote: String, repoDir: URL = defaultRepoDirectory) throws {
        let fm = FileManager.default
        if isConfigured(repoDir: repoDir) {
            try git(["remote", "set-url", "origin", remote], in: repoDir)
        } else {
            try? fm.createDirectory(
                at: repoDir.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            do {
                try git(["clone", remote, repoDir.path], in: nil)
            } catch {
                try fm.createDirectory(at: repoDir, withIntermediateDirectories: true)
                try git(["init"], in: repoDir)
                try git(["remote", "add", "origin", remote], in: repoDir)
            }
        }
        // Commits must work even without a global git identity.
        try git(["config", "user.name", "Skill Manager"], in: repoDir)
        try git(["config", "user.email", "sync@skillmanager.local"], in: repoDir)
    }

    // MARK: - Push

    /// Mirrors the given tools' skills into the repo, commits, and pushes.
    public static func push(tools: [Tool], repoDir: URL = defaultRepoDirectory) throws -> SyncSummary {
        guard isConfigured(repoDir: repoDir) else { throw SyncError.notConfigured }
        let fm = FileManager.default

        var mirrored = 0
        for tool in tools {
            let destination = repoDir.appending(path: tool.id, directoryHint: .isDirectory)
            try? fm.removeItem(at: destination)
            let copies = SkillScanner.scan(tool: tool)
            guard !copies.isEmpty else { continue }
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            for copy in copies {
                try fm.copyItem(
                    at: copy.directoryURL,
                    to: destination.appending(path: copy.directoryURL.lastPathComponent)
                )
                mirrored += 1
            }
        }

        try git(["add", "-A"], in: repoDir)
        let status = try git(["status", "--porcelain"], in: repoDir)
        if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let host = Host.current().localizedName ?? "mac"
            try git(["commit", "-m", "Sync from \(host)"], in: repoDir)
        }

        // Integrate remote changes first; tolerate an empty remote.
        try? git(["pull", "--rebase", "origin", "HEAD"], in: repoDir)
        try git(["push", "-u", "origin", "HEAD"], in: repoDir)
        return SyncSummary(mirroredSkills: mirrored, pushed: true)
    }

    // MARK: - Pull

    /// Pulls the remote and returns install candidates grouped by tool id
    /// (layout: `<toolID>/<skillName>/SKILL.md`).
    public static func pullCandidates(
        repoDir: URL = defaultRepoDirectory
    ) throws -> [(toolID: String, candidate: InstallCandidate)] {
        guard isConfigured(repoDir: repoDir) else { throw SyncError.notConfigured }
        try? git(["pull", "--rebase", "origin", "HEAD"], in: repoDir)

        let fm = FileManager.default
        var results: [(String, InstallCandidate)] = []
        let toolDirs = (try? fm.contentsOfDirectory(
            at: repoDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for toolDir in toolDirs
        where (try? toolDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let toolID = toolDir.lastPathComponent
            let skillDirs = (try? fm.contentsOfDirectory(
                at: toolDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for skillDir in skillDirs
            where fm.fileExists(atPath: skillDir.appending(path: "SKILL.md").path) {
                results.append((
                    toolID,
                    InstallCandidate(name: skillDir.lastPathComponent, sourceDirectory: skillDir)
                ))
            }
        }
        return results
    }
}
