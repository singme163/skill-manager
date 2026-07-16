import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SkillManagerCore

enum SidebarFilter: Hashable {
    case all
    case tool(Tool)

    var title: String {
        switch self {
        case .all: return "全部"
        case .tool(let tool): return tool.displayName
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case name = "按名称"
    case modified = "按修改时间"

    var id: String { rawValue }
}

/// Candidates staged by import/GitHub download, awaiting target selection.
struct PendingInstall: Identifiable {
    let id = UUID()
    var candidates: [InstallCandidate]
}

struct ContentView: View {
    @EnvironmentObject private var store: SkillStore

    @State private var filter: SidebarFilter = .all
    @State private var selectedSkillID: Skill.ID?
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .name

    @State private var showNewSkillSheet = false
    @State private var showGitHubSheet = false
    @State private var showImporter = false
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
        .searchable(text: $searchText, placement: .sidebar, prompt: "搜索 skill 名称或描述")
        .sheet(isPresented: $showNewSkillSheet) {
            NewSkillSheet()
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
        .alert(
            "导入失败",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
        .confirmationDialog(
            "删除 skill「\(deleteTarget?.displayName ?? "")」？",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            deleteDialogButtons
        } message: {
            Text("skill 目录会被移入废纸篓，可随时恢复。")
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

    // MARK: - Columns

    private var sidebar: some View {
        List(selection: $filter) {
            Section("来源") {
                Label("全部", systemImage: "square.grid.2x2")
                    .badge(store.skills.count)
                    .tag(SidebarFilter.all)
                ForEach(Tool.allCases) { tool in
                    Label(tool.displayName, systemImage: tool.symbolName)
                        .badge(store.count(for: tool))
                        .tag(SidebarFilter.tool(tool))
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }

    private var skillList: some View {
        Group {
            if filteredSkills.isEmpty {
                emptyState
            } else {
                List(filteredSkills, selection: $selectedSkillID) { skill in
                    SkillRowView(skill: skill)
                        .tag(skill.id)
                        .contextMenu { rowContextMenu(for: skill) }
                }
                .onDeleteCommand {
                    if let skill = selectedSkill { deleteTarget = skill }
                }
            }
        }
        .navigationTitle(filter.title)
        .navigationSubtitle("\(filteredSkills.count) 个 skill")
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        .toolbar { listToolbar }
    }

    @ViewBuilder
    private var detail: some View {
        if let skill = selectedSkill {
            SkillDetailView(skill: skill) { target in
                deleteTarget = target
            }
        } else {
            ContentUnavailableView(
                "选择一个 skill",
                systemImage: "sparkles.rectangle.stack",
                description: Text("从左侧列表选择 skill 查看详情")
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                searchText.isEmpty ? "还没有 skill" : "没有匹配的 skill",
                systemImage: searchText.isEmpty ? "sparkles.rectangle.stack" : "magnifyingglass"
            )
        } description: {
            Text(
                searchText.isEmpty
                    ? "新建一个 skill，或把 skill 文件夹 / zip 拖到窗口中导入"
                    : "换个关键词试试"
            )
        } actions: {
            if searchText.isEmpty {
                Button("新建 Skill") { showNewSkillSheet = true }
                Button("导入…") { showImporter = true }
            }
        }
    }

    // MARK: - Toolbar & menus

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("新建空白 Skill…") { showNewSkillSheet = true }
                Button("导入文件夹 / zip…") { showImporter = true }
                Button("从 GitHub 安装…") { showGitHubSheet = true }
            } label: {
                Label("添加", systemImage: "plus")
            }
        }
        ToolbarItem {
            Picker("排序", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)
        }
        ToolbarItem {
            Button {
                Task { await store.refresh() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(store.isLoading)
        }
    }

    @ViewBuilder
    private func rowContextMenu(for skill: Skill) -> some View {
        ForEach(skill.copies) { copy in
            Button("在 Finder 中显示（\(copy.tool.displayName)）") {
                NSWorkspace.shared.activateFileViewerSelecting([copy.directoryURL])
            }
        }
        Divider()
        ForEach(skill.copies) { copy in
            let others = Tool.allCases.filter { $0 != copy.tool && skill.copy(for: $0) == nil }
            ForEach(others) { target in
                Button("复制到 \(target.displayName)") {
                    Task { _ = await store.copySkill(copy, to: target, overwrite: false) }
                }
            }
        }
        Divider()
        Button("删除…", role: .destructive) { deleteTarget = skill }
    }

    @ViewBuilder
    private var deleteDialogButtons: some View {
        if let skill = deleteTarget {
            ForEach(skill.copies) { copy in
                Button("从 \(copy.tool.displayName) 删除", role: .destructive) {
                    Task { await store.trash(copy) }
                }
            }
            if skill.copies.count > 1 {
                Button("从两者删除", role: .destructive) {
                    let copies = skill.copies
                    Task {
                        for copy in copies { await store.trash(copy) }
                    }
                }
            }
            Button("取消", role: .cancel) {}
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
        filteredSkills.first { $0.id == selectedSkillID }
    }

    private func stageImport(of urls: [URL]) {
        Task {
            var candidates: [InstallCandidate] = []
            var failures: [String] = []
            for url in urls {
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
                        .help("SKILL.md 缺失或元数据不完整")
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

    var body: some View {
        Text(tool == .claudeCode ? "Claude" : "Codex")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                (tool == .claudeCode ? Color.orange : Color.blue).opacity(0.18),
                in: Capsule()
            )
            .foregroundStyle(tool == .claudeCode ? Color.orange : Color.blue)
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
