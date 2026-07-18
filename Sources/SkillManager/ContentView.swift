import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SkillManagerCore

enum SidebarFilter: Hashable {
    case all
    case tool(Tool)

    var title: String {
        switch self {
        case .all: return L("全部")
        case .tool(let tool): return tool.displayName
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case name
    case modified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return L("按名称")
        case .modified: return L("按修改时间")
        }
    }
}

/// Candidates staged by import/GitHub download, awaiting target selection.
struct PendingInstall: Identifiable {
    let id = UUID()
    var candidates: [InstallCandidate]
}

struct ContentView: View {
    @EnvironmentObject private var store: SkillStore
    @Environment(\.openSettings) private var openSettings
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    @State private var filter: SidebarFilter = .all
    @State private var selectedSkillIDs = Set<Skill.ID>()
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .name

    @State private var showNewSkillSheet = false
    @State private var showGitHubSheet = false
    @State private var showDiscovery = false
    @State private var batchDeleteSkills: [Skill]?
    @State private var showExportPicker = false
    @State private var showImporter = false
    @State private var showProjectImporter = false
    @State private var pendingInstall: PendingInstall?
    @State private var deleteTarget: Skill?
    @State private var importErrorMessage: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            skillList
        } detail: {
            detail
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: Text(L("搜索 skill 名称或描述")))
        .sheet(isPresented: welcomeBinding) {
            WelcomeSheet()
        }
        .sheet(isPresented: $showNewSkillSheet) {
            NewSkillSheet()
        }
        .sheet(isPresented: $showDiscovery) {
            DiscoverySheet { candidates in
                pendingInstall = PendingInstall(candidates: candidates)
            }
        }
        .sheet(isPresented: $showGitHubSheet) {
            GitHubInstallSheet { candidates in
                pendingInstall = PendingInstall(candidates: candidates)
            }
        }
        .sheet(item: $pendingInstall) { pending in
            InstallCandidatesSheet(candidates: pending.candidates)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.folder, .zip],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                stageImport(of: urls)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            stageImport(of: urls)
            return true
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .task {
            await runSnapshotScriptIfRequested()
        }
        .onChange(of: store.pendingSelection) {
            guard let id = store.pendingSelection else { return }
            filter = .all
            searchText = ""
            selectedSkillIDs = [id]
            store.pendingSelection = nil
        }
        .alert(
            L("导入失败"),
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button(L("好"), role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
        .confirmationDialog(
            L("删除 skill「\(deleteTarget?.displayName ?? "")」？"),
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            deleteDialogButtons
        } message: {
            Text(L("skill 目录会被移入废纸篓，可随时恢复。"))
        }
        .confirmationDialog(
            L("删除 \(batchDeleteSkills?.count ?? 0) 个 skill？"),
            isPresented: Binding(
                get: { batchDeleteSkills != nil },
                set: { if !$0 { batchDeleteSkills = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("删除（移入废纸篓）"), role: .destructive) {
                let copies = (batchDeleteSkills ?? []).flatMap(\.writableCopies)
                Task {
                    for copy in copies { await store.trash(copy) }
                }
            }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("skill 目录会被移入废纸篓，可随时恢复。"))
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.toast)
    }

    private var welcomeBinding: Binding<Bool> {
        Binding(
            get: { !hasSeenWelcome },
            set: { hasSeenWelcome = !$0 }
        )
    }

    // MARK: - Columns

    private var sidebar: some View {
        List(selection: $filter) {
            Section(L("来源")) {
                Label(L("全部"), systemImage: "square.grid.2x2")
                    .badge(store.skills.count)
                    .tag(SidebarFilter.all)
                ForEach(store.regularTools) { tool in
                    Label(tool.displayName, systemImage: tool.symbolName)
                        .badge(store.count(for: tool))
                        .tag(SidebarFilter.tool(tool))
                }
            }
            if !store.projects.isEmpty {
                Section(L("项目")) {
                    ForEach(store.projects) { project in
                        Label(project.displayName, systemImage: project.symbolName)
                            .badge(store.count(for: project))
                            .tag(SidebarFilter.tool(project))
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        .fileImporter(
            isPresented: $showProjectImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await store.addProject(directory: url) }
            }
        }
    }

    private var skillList: some View {
        Group {
            if filteredSkills.isEmpty {
                emptyState
            } else {
                List(filteredSkills, selection: $selectedSkillIDs) { skill in
                    SkillRowView(skill: skill)
                        .tag(skill.id)
                }
                .contextMenu(forSelectionType: Skill.ID.self) { ids in
                    let skills = skills(for: ids)
                    if skills.count == 1, let skill = skills.first {
                        rowContextMenu(for: skill)
                    } else if skills.count > 1 {
                        batchContextMenu(for: skills)
                    }
                }
                .onDeleteCommand {
                    requestDeleteForSelection()
                }
                .fileImporter(
                    isPresented: $showExportPicker,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let folder = urls.first {
                        exportSelection(to: folder)
                    }
                }
            }
        }
        .navigationTitle(filter.title)
        .navigationSubtitle(L("\(filteredSkills.count) 个 skill"))
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        .toolbar { listToolbar }
    }

    @ViewBuilder
    private var detail: some View {
        if let skill = selectedSkill {
            SkillDetailView(skill: skill) { target in
                deleteTarget = target
            }
        } else if selectedSkillIDs.count > 1 {
            ContentUnavailableView(
                L("已选择 \(selectedSkillIDs.count) 个 skill"),
                systemImage: "square.stack.3d.up",
                description: Text(L("右键进行批量删除、复制或导出"))
            )
        } else {
            ContentUnavailableView(
                L("选择一个 skill"),
                systemImage: "sparkles.rectangle.stack",
                description: Text(L("从左侧列表选择 skill 查看详情"))
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                searchText.isEmpty ? L("还没有 skill") : L("没有匹配的 skill"),
                systemImage: searchText.isEmpty ? "sparkles.rectangle.stack" : "magnifyingglass"
            )
        } description: {
            Text(
                searchText.isEmpty
                    ? L("新建一个 skill，或把 skill 文件夹 / zip 拖到窗口中导入")
                    : L("换个关键词试试")
            )
        } actions: {
            if searchText.isEmpty {
                Button(L("新建 Skill")) { showNewSkillSheet = true }
                Button(L("导入…")) { showImporter = true }
            }
        }
    }

    // MARK: - Toolbar & menus

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button(L("新建空白 Skill…")) { showNewSkillSheet = true }
                Button(L("导入文件夹 / zip…")) { showImporter = true }
                Button(L("从 GitHub 安装…")) { showGitHubSheet = true }
                Button(L("发现 Skill…")) { showDiscovery = true }
                Divider()
                Button(L("添加项目目录…")) { showProjectImporter = true }
            } label: {
                Label(L("添加"), systemImage: "plus")
            }
        }
        ToolbarItem {
            Picker(L("排序"), selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.menu)
        }
        ToolbarItem {
            Button {
                Task { await store.refresh() }
            } label: {
                Label(L("刷新"), systemImage: "arrow.clockwise")
            }
            .disabled(store.isLoading)
        }
    }

    @ViewBuilder
    private func rowContextMenu(for skill: Skill) -> some View {
        ForEach(skill.copies) { copy in
            Button(L("在 Finder 中显示（\(copy.tool.displayName)）")) {
                NSWorkspace.shared.activateFileViewerSelecting([copy.directoryURL])
            }
        }
        Divider()
        if let source = skill.writableCopies.first ?? skill.copies.first {
            ForEach(store.writableTools.filter { skill.copy(for: $0) == nil }) { target in
                Button(L("复制到 \(target.displayName)")) {
                    Task { _ = await store.copySkill(source, to: target, overwrite: false) }
                }
            }
        }
        if !skill.writableCopies.isEmpty {
            Divider()
            Button(L("删除…"), role: .destructive) { deleteTarget = skill }
        }
    }

    @ViewBuilder
    private var deleteDialogButtons: some View {
        if let skill = deleteTarget {
            ForEach(skill.writableCopies) { copy in
                Button(L("从 \(copy.tool.displayName) 删除"), role: .destructive) {
                    Task { await store.trash(copy) }
                }
            }
            if skill.writableCopies.count > 1 {
                Button(L("从全部工具删除"), role: .destructive) {
                    let copies = skill.writableCopies
                    Task {
                        for copy in copies { await store.trash(copy) }
                    }
                }
            }
            Button(L("取消"), role: .cancel) {}
        }
    }

    // MARK: - Data

    private var filteredSkills: [Skill] {
        var result = store.skills
        if case .tool(let tool) = filter {
            result = result.filter { $0.copy(for: tool) != nil }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { skill in
                skill.folderName.localizedCaseInsensitiveContains(query)
                    || skill.displayName.localizedCaseInsensitiveContains(query)
                    || (skill.summary?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        switch sortOrder {
        case .name:
            return result
        case .modified:
            return result.sorted { $0.latestModified > $1.latestModified }
        }
    }

    private var selectedSkill: Skill? {
        guard selectedSkillIDs.count == 1, let id = selectedSkillIDs.first else { return nil }
        return filteredSkills.first { $0.id == id }
    }

    private func skills(for ids: Set<Skill.ID>) -> [Skill] {
        filteredSkills.filter { ids.contains($0.id) }
    }

    private func requestDeleteForSelection() {
        let skills = skills(for: selectedSkillIDs).filter { !$0.writableCopies.isEmpty }
        if skills.count == 1 {
            deleteTarget = skills[0]
        } else if skills.count > 1 {
            batchDeleteSkills = skills
        }
    }

    @ViewBuilder
    private func batchContextMenu(for skills: [Skill]) -> some View {
        ForEach(store.writableTools) { target in
            Button(L("复制到 \(target.displayName)")) {
                Task { await batchCopy(skills, to: target) }
            }
        }
        Divider()
        Button(L("导出 zip…")) { showExportPicker = true }
        if skills.contains(where: { !$0.writableCopies.isEmpty }) {
            Divider()
            Button(L("删除…"), role: .destructive) {
                batchDeleteSkills = skills.filter { !$0.writableCopies.isEmpty }
            }
        }
    }

    private func batchCopy(_ skills: [Skill], to target: Tool) async {
        var copied = 0
        var skipped = 0
        for skill in skills {
            guard skill.copy(for: target) == nil,
                  let source = skill.writableCopies.first ?? skill.copies.first else {
                skipped += 1
                continue
            }
            if await store.copySkill(source, to: target, overwrite: false) {
                copied += 1
            } else {
                skipped += 1
            }
        }
        store.showToast(Toast(L("已复制 \(copied) 个，跳过 \(skipped) 个（已存在或冲突）")))
    }

    private func exportSelection(to folder: URL) {
        let skills = skills(for: selectedSkillIDs)
        Task.detached {
            var exported = 0
            var failure: String?
            for skill in skills {
                guard let copy = skill.writableCopies.first ?? skill.copies.first else { continue }
                do {
                    try SkillInstaller.exportZip(of: copy.directoryURL, to: folder)
                    exported += 1
                } catch {
                    failure = error.localizedDescription
                }
            }
            let done = exported
            let err = failure
            await MainActor.run {
                if let err {
                    store.showToast(Toast(L("导出失败：\(err)"), style: .error))
                } else {
                    store.showToast(Toast(L("已导出 \(done) 个 zip")))
                }
            }
        }
    }

    // MARK: - Snapshot mode (SM_SNAPSHOT_DIR)

    /// Documentation screenshot generator: when SM_SNAPSHOT_DIR is set, walk
    /// the app through its showcase states, render each window to a PNG
    /// (self-rendering — no screen-recording permission involved), and quit.
    private func runSnapshotScriptIfRequested() async {
        guard let dir = ProcessInfo.processInfo.environment["SM_SNAPSHOT_DIR"] else { return }
        let external = ProcessInfo.processInfo.environment["SM_SNAPSHOT_EXTERNAL"] == "1"
        let output = URL(filePath: (dir as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        // External mode hands each state to a driver script that runs
        // `screencapture -l <windowNumber>`: write the id into a .ready
        // marker, wait for the matching .done, then move on.
        func shoot(_ name: String, window: NSWindow?) async {
            guard let window else { return }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .seconds(0.4))
            if external {
                let ready = output.appending(path: "\(name).ready")
                let done = output.appending(path: "\(name).done")
                try? String(window.windowNumber).write(to: ready, atomically: true, encoding: .utf8)
                for _ in 0..<100 where !FileManager.default.fileExists(atPath: done.path) {
                    try? await Task.sleep(for: .seconds(0.2))
                }
                try? FileManager.default.removeItem(at: ready)
                try? FileManager.default.removeItem(at: done)
            } else {
                WindowSnapshotter.capture(window, to: output.appending(path: "\(name).png"))
            }
        }

        hasSeenWelcome = true
        try? await Task.sleep(for: .seconds(2))

        // 1. Main window with a well-described skill selected.
        if let skill = store.skills.first(where: { ($0.summary?.count ?? 0) > 40 }) ?? store.skills.first {
            selectedSkillIDs = [skill.id]
        }
        try? await Task.sleep(for: .seconds(1))
        await shoot("main", window: WindowSnapshotter.mainWindow)

        // 2. Lint tab on a skill that actually has findings.
        if let target = store.skills.first(where: { skill in
            guard let copy = skill.copies.first else { return false }
            return !SkillLinter.lint(copy: copy).isEmpty
        }) {
            selectedSkillIDs = [target.id]
            try? await Task.sleep(for: .seconds(0.6))
        }
        store.requestedDetailMode = "lint"
        try? await Task.sleep(for: .seconds(1))
        await shoot("lint", window: WindowSnapshotter.mainWindow)
        store.requestedDetailMode = "preview"
        try? await Task.sleep(for: .seconds(0.4))

        // 3. Discovery sheet (allow time for the remote index fetch).
        showDiscovery = true
        try? await Task.sleep(for: .seconds(4))
        await shoot("discovery", window: WindowSnapshotter.mainWindow?.attachedSheet)
        showDiscovery = false
        try? await Task.sleep(for: .seconds(0.6))

        // 4. Settings, tall enough to show the sync section.
        openSettings()
        try? await Task.sleep(for: .seconds(1.5))
        let settingsWindow = NSApp.keyWindow ?? NSApp.windows.last(where: { $0.isVisible })
        settingsWindow?.setContentSize(NSSize(width: 620, height: 1000))
        settingsWindow?.center()
        settingsWindow?.layoutIfNeeded()
        try? await Task.sleep(for: .seconds(0.5))
        await shoot("sync", window: settingsWindow)
        try? await Task.sleep(for: .seconds(0.5))
        NSApp.terminate(nil)
    }

    /// `skillmanager://install?url=<github-url>` — download and stage the
    /// skills for the normal candidate/target confirmation flow.
    private func handleDeepLink(_ url: URL) {
        guard let target = SkillInstaller.parseInstallDeepLink(url) else {
            store.showToast(Toast(L("无法识别的安装链接"), style: .error))
            return
        }
        Task {
            do {
                let candidates = try await SkillInstaller.downloadFromGitHub(target)
                pendingInstall = PendingInstall(candidates: candidates)
            } catch {
                store.showToast(Toast(error.localizedDescription, style: .error))
            }
        }
    }

    private func stageImport(of urls: [URL]) {
        Task {
            var candidates: [InstallCandidate] = []
            var failures: [String] = []
            for url in urls {
                // A dropped project folder registers as a project instead of
                // importing its skills as copies.
                if ToolRegistry.looksLikeProject(url) {
                    await store.addProject(directory: url)
                    continue
                }
                do {
                    candidates.append(contentsOf: try SkillInstaller.prepareImport(from: url))
                } catch {
                    failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
                }
            }
            if !candidates.isEmpty {
                pendingInstall = PendingInstall(candidates: candidates)
            }
            if !failures.isEmpty {
                importErrorMessage = failures.joined(separator: "\n")
            }
        }
    }
}

// MARK: - Row

struct SkillRowView: View {
    let skill: Skill

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(skill.displayName)
                    .font(.headline)
                    .lineLimit(1)
                if skill.metadataMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help(L("SKILL.md 缺失或元数据不完整"))
                }
                Spacer()
                ForEach(skill.tools) { tool in
                    ToolBadge(tool: tool)
                }
            }
            if let summary = skill.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                Text(ByteCountFormatter.string(fromByteCount: skill.maxSizeBytes, countStyle: .file))
                Text(skill.latestModified, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

struct ToolBadge: View {
    let tool: Tool

    private static let palette: [Color] = [.orange, .blue, .purple, .green, .pink, .teal, .indigo, .brown]

    private var color: Color {
        if tool.isReadOnly { return .gray }
        let count = Self.palette.count
        return Self.palette[((tool.sortOrder % count) + count) % count]
    }

    var body: some View {
        Text(tool.badge)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Toast

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .foregroundStyle(color)
            Text(toast.message)
                .font(.callout)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4, y: 2)
    }

    private var symbolName: String {
        switch toast.style {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch toast.style {
        case .info: return .blue
        case .success: return .green
        case .error: return .red
        }
    }
}
