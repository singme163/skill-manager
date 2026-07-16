import Foundation

public struct Toast: Identifiable, Equatable, Sendable {
    public enum Style: Sendable { case info, success, error }

    public let id = UUID()
    public let message: String
    public let style: Style

    public init(_ message: String, style: Style = .success) {
        self.message = message
        self.style = style
    }
}

/// App-wide observable state: scan results, directory watching, and the
/// write-side operations the UI calls into.
@MainActor
public final class SkillStore: ObservableObject {
    @Published public private(set) var skills: [Skill] = []
    @Published public private(set) var tools: [Tool]
    @Published public private(set) var isLoading = false
    @Published public var toast: Toast?

    private var watchers: [DirectoryWatcher] = []
    private var toastDismissTask: Task<Void, Never>?

    public init() {
        tools = ToolRegistry.load()
    }

    public var writableTools: [Tool] {
        tools.filter { !$0.isReadOnly }
    }

    /// AI-tool sources for the sidebar's 来源 section.
    public var regularTools: [Tool] {
        tools.filter { $0.category == .tool }
    }

    /// Registered projects for the sidebar's 项目 section.
    public var projects: [Tool] {
        tools.filter { $0.category == .project }
    }

    public func count(for tool: Tool) -> Int {
        skills.filter { $0.copy(for: tool) != nil }.count
    }

    // MARK: - Tool management

    /// Presets not yet in the active list, offered by the "add tool" menu.
    public var availablePresets: [Tool] {
        Tool.presets.filter { preset in !tools.contains { $0.id == preset.id } }
    }

    public func addTool(_ tool: Tool) async {
        guard !tools.contains(where: { $0.id == tool.id }) else { return }
        var added = tool
        added.sortOrder = (tools.map(\.sortOrder).max() ?? -1) + 1
        tools.append(added)
        persistToolsAndRescan()
        await refresh()
    }

    /// Registers a project directory (managing its `.claude/skills`).
    /// Returns false when the same project is already registered.
    @discardableResult
    public func addProject(directory: URL) async -> Bool {
        let skillsPath = directory
            .appending(path: ".claude/skills", directoryHint: .isDirectory)
            .standardizedFileURL.path
        guard !tools.contains(where: { $0.skillsDirectory.standardizedFileURL.path == skillsPath }) else {
            showToast(Toast(L("该项目已登记"), style: .info))
            return false
        }
        let project = ToolRegistry.makeProject(projectDirectory: directory, existing: tools)
        await addTool(project)
        showToast(Toast(L("已登记项目「\(project.name)」")))
        return true
    }

    public func removeTool(_ tool: Tool) async {
        tools.removeAll { $0.id == tool.id }
        persistToolsAndRescan()
        await refresh()
    }

    public func updateToolPath(_ tool: Tool, to path: String) {
        guard let index = tools.firstIndex(where: { $0.id == tool.id }) else { return }
        tools[index].directoryPath = path
        ToolRegistry.save(tools)
    }

    private func persistToolsAndRescan() {
        tools.sort { $0.sortOrder < $1.sortOrder }
        ToolRegistry.save(tools)
        startWatching()
    }

    // MARK: - Scanning

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let tools = self.tools
        let copies = await Task.detached(priority: .userInitiated) {
            tools.flatMap { SkillScanner.scan(tool: $0) }
        }.value
        skills = Skill.merge(copies)
    }

    public func startWatching() {
        watchers = tools.compactMap { tool in
            DirectoryWatcher(url: tool.skillsDirectory) {
                Task { @MainActor [weak self] in
                    await self?.refresh()
                    // The watched descriptor dies if the directory itself is
                    // replaced; re-arm to keep updates flowing.
                    self?.startWatching()
                }
            }
        }
    }

    // MARK: - Mutations

    public func trash(_ copy: SkillCopy) async {
        do {
            try FileManager.default.trashItem(at: copy.directoryURL, resultingItemURL: nil)
            showToast(Toast(L("已将「\(copy.folderName)」从 \(copy.tool.displayName) 移入废纸篓")))
        } catch {
            showToast(Toast(L("删除失败：\(error.localizedDescription)"), style: .error))
        }
        await refresh()
    }

    public struct InstallRequest: Identifiable, Hashable, Sendable {
        public let candidate: InstallCandidate
        public let tool: Tool

        public init(candidate: InstallCandidate, tool: Tool) {
            self.candidate = candidate
            self.tool = tool
        }

        public var id: String { "\(candidate.id)→\(tool.id)" }
    }

    /// Installs each candidate into its target tool. Returns the requests that
    /// hit a same-name conflict (when `overwrite` is false) so the UI can ask
    /// for overwrite confirmation and retry just those.
    public func install(_ requests: [InstallRequest], overwrite: Bool) async -> [InstallRequest] {
        var conflicts: [InstallRequest] = []
        var installed = 0
        for request in requests {
            do {
                try SkillInstaller.install(candidate: request.candidate, to: request.tool, overwrite: overwrite)
                installed += 1
            } catch let error as InstallError {
                if case .alreadyExists = error, !overwrite {
                    conflicts.append(request)
                } else {
                    showToast(Toast(error.localizedDescription, style: .error))
                }
            } catch {
                showToast(Toast(L("安装失败：\(error.localizedDescription)"), style: .error))
            }
        }
        if installed > 0 {
            showToast(Toast(L("已安装 \(installed) 个 skill")))
        }
        await refresh()
        return conflicts
    }

    /// Creates a blank skill from the template. Returns the created folder name on success.
    public func createTemplate(name: String, description: String, tools: [Tool]) async -> Bool {
        var succeeded = false
        for tool in tools {
            do {
                try SkillInstaller.createTemplate(name: name, description: description, tool: tool)
                succeeded = true
            } catch {
                showToast(Toast(error.localizedDescription, style: .error))
            }
        }
        if succeeded {
            showToast(Toast(L("已创建「\(name)」")))
        }
        await refresh()
        return succeeded
    }

    public func copySkill(_ copy: SkillCopy, to tool: Tool, overwrite: Bool) async -> Bool {
        do {
            try SkillInstaller.copySkill(copy, to: tool, overwrite: overwrite)
            showToast(Toast(L("已将「\(copy.folderName)」复制到 \(tool.displayName)")))
            await refresh()
            return true
        } catch let error as InstallError {
            if case .alreadyExists = error, !overwrite {
                return false // caller shows the overwrite confirmation
            }
            showToast(Toast(error.localizedDescription, style: .error))
        } catch {
            showToast(Toast(L("复制失败：\(error.localizedDescription)"), style: .error))
        }
        await refresh()
        return true
    }

    public func saveSkillFile(_ copy: SkillCopy, contents: String) async -> Bool {
        do {
            try contents.write(to: copy.skillFileURL, atomically: true, encoding: .utf8)
            showToast(Toast(L("已保存 \(copy.folderName)/SKILL.md")))
            await refresh()
            return true
        } catch {
            showToast(Toast(L("保存失败：\(error.localizedDescription)"), style: .error))
            return false
        }
    }

    // MARK: - Origin updates

    public enum UpdateCheckResult: Equatable, Sendable {
        case upToDate
        case available(String)
        case failed(String)
    }

    /// Compares the installed revision against upstream HEAD (or the pinned ref).
    public func checkForUpdate(_ copy: SkillCopy) async -> UpdateCheckResult {
        guard let origin = copy.origin,
              let target = SkillInstaller.parseGitHubURL(origin.sourceURL) else {
            return .failed(L("无法识别的 GitHub 链接。支持仓库或仓库子目录链接，例如 https://github.com/org/repo 或 …/tree/main/skills/foo。"))
        }
        do {
            let latest = try await SkillInstaller.latestCommit(for: target)
            return origin.isCurrent(latest: latest) ? .upToDate : .available(String(latest.prefix(7)))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Re-downloads the skill from its recorded source and overwrites the
    /// local copy (old version goes to the Trash via the install pipeline).
    public func updateFromOrigin(_ copy: SkillCopy) async -> Bool {
        guard let origin = copy.origin else { return false }
        do {
            let candidates = try await SkillInstaller.downloadFromGitHub(origin.sourceURL)
            let wanted = copy.directoryURL.lastPathComponent
            guard let candidate = candidates.first(where: { $0.name == wanted })
                ?? (candidates.count == 1 ? candidates[0] : nil) else {
                showToast(Toast(L("未在上游找到「\(wanted)」"), style: .error))
                return false
            }
            try SkillInstaller.install(candidate: candidate, to: copy.tool, overwrite: true)
            showToast(Toast(L("已更新「\(wanted)」")))
            await refresh()
            return true
        } catch {
            showToast(Toast(L("更新失败：\(error.localizedDescription)"), style: .error))
            return false
        }
    }

    // MARK: - Toast

    public func showToast(_ toast: Toast) {
        self.toast = toast
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
