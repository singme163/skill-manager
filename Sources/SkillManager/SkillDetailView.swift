import SwiftUI
import AppKit
import SkillManagerCore

struct SkillDetailView: View {
    @EnvironmentObject private var store: SkillStore

    let skill: Skill
    let onDelete: (Skill) -> Void

    @State private var selectedTool: Tool?
    @State private var mode: DetailMode = .preview
    @State private var editorText = ""
    @State private var loadedText = ""
    @State private var showForceSaveAlert = false
    @State private var overwriteCopyTarget: Tool?

    enum DetailMode: String, CaseIterable, Identifiable {
        case preview
        case edit
        case files
        case usage

        var id: String { rawValue }

        var title: String {
            switch self {
            case .preview: return L("预览")
            case .edit: return L("编辑")
            case .files: return L("文件")
            case .usage: return L("用法")
            }
        }
    }

    private var currentCopy: SkillCopy {
        if let selectedTool, let copy = skill.copy(for: selectedTool) {
            return copy
        }
        return skill.copies[0]
    }

    private var hasUnsavedChanges: Bool { editorText != loadedText }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .task(id: currentCopy.id) {
            loadEditorText()
        }
        .alert(L("Frontmatter 校验未通过"), isPresented: $showForceSaveAlert) {
            Button(L("仍要保存"), role: .destructive) {
                Task { await save(force: true) }
            }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("文件开头缺少合法的 YAML frontmatter（--- 包裹的 name/description 块），可能导致工具无法识别此 skill。"))
        }
        .confirmationDialog(
            L("\(overwriteCopyTarget?.displayName ?? "") 中已存在「\(skill.folderName)」"),
            isPresented: Binding(
                get: { overwriteCopyTarget != nil },
                set: { if !$0 { overwriteCopyTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("覆盖（旧版本移入废纸篓）"), role: .destructive) {
                if let target = overwriteCopyTarget {
                    Task { _ = await store.copySkill(currentCopy, to: target, overwrite: true) }
                }
            }
            Button(L("取消"), role: .cancel) {}
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(currentCopy.displayName)
                    .font(.title2.weight(.semibold))
                Spacer()
                ForEach(skill.tools) { tool in
                    ToolBadge(tool: tool)
                }
            }

            if let description = currentCopy.metadataDescription {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else if !currentCopy.hasValidMetadata {
                Label(
                    currentCopy.hasSkillFile
                        ? L("SKILL.md 缺少合法的 frontmatter 元数据")
                        : L("缺少 SKILL.md 文件"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.yellow)
            }

            HStack(spacing: 12) {
                if skill.copies.count > 1 {
                    Picker(L("副本"), selection: toolSelection) {
                        ForEach(skill.tools) { tool in
                            Text(tool.displayName).tag(tool)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                Label(
                    ByteCountFormatter.string(fromByteCount: currentCopy.sizeBytes, countStyle: .file),
                    systemImage: "externaldrive"
                )
                Label(
                    currentCopy.modifiedDate.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "clock"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(currentCopy.directoryURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(currentCopy.directoryURL.path, forType: .string)
                    store.showToast(Toast(L("路径已复制"), style: .info))
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help(L("复制路径"))
            }

            Picker(L("模式"), selection: $mode) {
                ForEach(DetailMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding()
        .toolbar { detailToolbar }
    }

    private var toolSelection: Binding<Tool> {
        Binding(
            get: { currentCopy.tool },
            set: { selectedTool = $0 }
        )
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([currentCopy.directoryURL])
            } label: {
                Label(L("在 Finder 中显示"), systemImage: "folder")
            }
            .help(L("在 Finder 中显示"))

            Button {
                NSWorkspace.shared.open(currentCopy.skillFileURL)
            } label: {
                Label(L("用默认编辑器打开"), systemImage: "square.and.pencil")
            }
            .help(L("用默认编辑器打开 SKILL.md"))
            .disabled(!currentCopy.hasSkillFile)

            if let target = copyTargetTool {
                Button {
                    Task {
                        let done = await store.copySkill(currentCopy, to: target, overwrite: false)
                        if !done { overwriteCopyTarget = target }
                    }
                } label: {
                    Label(L("复制到 \(target.displayName)"), systemImage: "arrow.right.doc.on.clipboard")
                }
                .help(L("复制到 \(target.displayName)"))
            }

            Button(role: .destructive) {
                onDelete(skill)
            } label: {
                Label(L("删除"), systemImage: "trash")
            }
            .help(L("移入废纸篓"))
        }
    }

    /// The other tool, offered as a copy destination (even if it already has
    /// a copy — that flows into the overwrite confirmation).
    private var copyTargetTool: Tool? {
        Tool.allCases.first { $0 != currentCopy.tool }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .preview:
            if currentCopy.hasSkillFile {
                SimpleMarkdownView(text: Self.stripFrontmatter(loadedText))
            } else {
                ContentUnavailableView(
                    L("没有 SKILL.md"),
                    systemImage: "doc.questionmark",
                    description: Text(L("此目录缺少 SKILL.md，切换到“编辑”可创建一个。"))
                )
            }
        case .edit:
            editor
        case .files:
            fileList
        case .usage:
            usageView
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            TextEditor(text: $editorText)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(8)
            Divider()
            HStack {
                if hasUnsavedChanges {
                    Text(L("未保存的修改"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button(L("还原")) { editorText = loadedText }
                    .disabled(!hasUnsavedChanges)
                Button(L("保存")) {
                    Task { await save(force: false) }
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!hasUnsavedChanges)
            }
            .padding(10)
        }
    }

    private var usageView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                usageSection(title: L("自动触发"), icon: "wand.and.stars") {
                    Text(L("工具会根据 SKILL.md frontmatter 中的 description 判断当前任务是否匹配，匹配时自动加载此 skill，无需手动调用。描述写得越具体、包含越多触发关键词，命中越准确。"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let description = currentCopy.metadataDescription {
                        Text(description)
                            .font(.callout)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    } else {
                        Label(
                            L("此 skill 缺少 description，只能显式调用，建议在“编辑”中补全。"),
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.callout)
                        .foregroundStyle(.orange)
                    }
                }

                usageSection(title: L("显式调用"), icon: "keyboard") {
                    if skill.copy(for: .claudeCode) != nil {
                        copyRow(
                            snippet: "/\(skill.folderName)",
                            note: L("Claude Code 中作为斜杠命令直接调用")
                        )
                    }
                    copyRow(
                        snippet: L("使用 \(currentCopy.displayName) 技能："),
                        note: L("对话中自然语言指名调用（Claude Code / Codex 通用）")
                    )
                }

                usageSection(title: L("示例提示词"), icon: "text.bubble") {
                    copyRow(
                        snippet: examplePrompt,
                        note: L("复制后补全任务内容即可发送")
                    )
                }

                usageSection(title: L("安装位置"), icon: "internaldrive") {
                    ForEach(skill.copies) { copy in
                        HStack(spacing: 8) {
                            ToolBadge(tool: copy.tool)
                            Text(copy.directoryURL.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    @ViewBuilder
    private func usageSection(
        title: String,
        icon: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
    }

    private func copyRow(snippet: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(snippet)
                    .font(.callout.monospaced())
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                    store.showToast(Toast(L("已复制"), style: .info))
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help(L("复制"))
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            Text(note)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var examplePrompt: String {
        if let description = currentCopy.metadataDescription {
            // Take the first clause of the description as a task hint.
            let firstClause = description
                .components(separatedBy: CharacterSet(charactersIn: "。.;；"))
                .first ?? description
            return L("请使用 \(currentCopy.displayName) 技能：\(firstClause.trimmingCharacters(in: .whitespaces))")
        }
        return L("请使用 \(currentCopy.displayName) 技能完成以下任务：")
    }

    private var fileList: some View {
        List(SkillScanner.fileListing(of: currentCopy.directoryURL), id: \.self) { path in
            HStack(spacing: 6) {
                Image(systemName: path.hasSuffix("/") ? "folder" : "doc.text")
                    .foregroundStyle(path.hasSuffix("/") ? Color.accentColor : .secondary)
                Text(path)
                    .font(.callout.monospaced())
            }
        }
    }

    // MARK: - Actions

    private func loadEditorText() {
        let text = (try? String(contentsOf: currentCopy.skillFileURL, encoding: .utf8)) ?? ""
        loadedText = text
        editorText = text
    }

    private func save(force: Bool) async {
        if !force, FrontmatterParser.parse(markdown: editorText) == nil {
            showForceSaveAlert = true
            return
        }
        if await store.saveSkillFile(currentCopy, contents: editorText) {
            loadedText = editorText
        }
    }

    static func stripFrontmatter(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return text
        }
        for index in 1..<lines.count
        where lines[index].trimmingCharacters(in: .whitespaces) == "---" {
            lines.removeSubrange(0...index)
            return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
        }
        return text
    }
}
