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
    @State private var updateStatus: SkillStore.UpdateCheckResult?
    @State private var isCheckingUpdate = false
    @State private var isUpdating = false
    @State private var fmName = ""
    @State private var fmDescription = ""
    @State private var showHistorySheet = false
    @State private var showSharePicker = false
    @State private var showTranslation = false
    @State private var translatedDescription: String?
    @State private var isTranslating = false
    @State private var translationRequest: [String]?
    @State private var showPreviewTranslation = false
    @State private var translatedPreview: String?
    @State private var isTranslatingPreview = false
    @State private var previewRequest: [String]?
    @State private var previewPlan: MarkdownTranslationPlan?

    enum DetailMode: String, CaseIterable, Identifiable {
        case preview
        case edit
        case files
        case usage
        case lint

        var id: String { rawValue }

        var title: String {
            switch self {
            case .preview: return L("预览")
            case .edit: return L("编辑")
            case .files: return L("文件")
            case .usage: return L("用法")
            case .lint: return L("检查")
            }
        }
    }

    /// Read-only sources hide the editor.
    private var availableModes: [DetailMode] {
        currentCopy.tool.isReadOnly ? [.preview, .files, .usage, .lint] : DetailMode.allCases
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
        .onChange(of: store.requestPreviewTranslation) {
            if store.requestPreviewTranslation {
                togglePreviewTranslation()
                if !isTranslatingPreview {
                    store.requestPreviewTranslation = false
                }
            }
        }
        .onChange(of: store.requestedDetailMode) {
            if let raw = store.requestedDetailMode,
               let requested = DetailMode(rawValue: raw),
               availableModes.contains(requested) {
                mode = requested
                store.requestedDetailMode = nil
            }
        }
        .task(id: currentCopy.id) {
            loadEditorText()
            syncFormFromEditor()
            if !availableModes.contains(mode) {
                mode = .preview
            }
            updateStatus = nil
            isCheckingUpdate = false
            isUpdating = false
            showTranslation = false
            translatedDescription = nil
            isTranslating = false
            translationRequest = nil
            resetPreviewTranslation()
        }
        .onChange(of: loadedText) {
            resetPreviewTranslation()
        }
        .background {
            if #available(macOS 15.0, *) {
                TranslationRunner(
                    request: $translationRequest,
                    targetIdentifier: Self.translationTargetIdentifier
                ) { results in
                    if let first = results.first {
                        translatedDescription = first
                        showTranslation = true
                    }
                    isTranslating = false
                } onError: { message in
                    store.showToast(Toast(L("翻译失败：\(message)"), style: .error))
                    isTranslating = false
                }
                TranslationRunner(
                    request: $previewRequest,
                    targetIdentifier: Self.translationTargetIdentifier
                ) { results in
                    if let plan = previewPlan {
                        var text = plan.reassembled(with: results)
                        if plan.truncated {
                            text += "\n\n> " + L("……（文档较长，仅翻译了开头部分）")
                        }
                        translatedPreview = text
                        showPreviewTranslation = true
                    }
                    isTranslatingPreview = false
                    store.requestPreviewTranslation = false
                } onError: { message in
                    store.showToast(Toast(L("翻译失败：\(message)"), style: .error))
                    isTranslatingPreview = false
                    store.requestPreviewTranslation = false
                }
            }
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
                if currentCopy.tool.isReadOnly {
                    Label(L("只读"), systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(L("此来源为只读（由插件系统管理），不能编辑，可复制到其他工具使用。"))
                }
                Spacer()
                ForEach(skill.tools) { tool in
                    ToolBadge(tool: tool)
                }
            }

            if let description = currentCopy.metadataDescription {
                HStack(alignment: .top, spacing: 6) {
                    Text(displayedDescription(description))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(showTranslation ? 6 : 3)
                    if canOfferTranslation(for: description) {
                        Button {
                            toggleTranslation(of: description)
                        } label: {
                            if isTranslating {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "translate")
                                    .foregroundStyle(showTranslation ? Color.accentColor : Color.secondary)
                            }
                        }
                        .buttonStyle(.borderless)
                        .help(showTranslation ? L("显示原文") : L("翻译"))
                    }
                }
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
                ForEach(availableModes) { mode in
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
                showSharePicker = true
            } label: {
                Label(L("分享（zip + 说明）"), systemImage: "square.and.arrow.up")
            }
            .help(L("导出 zip 和分享说明到指定文件夹"))
            .fileImporter(
                isPresented: $showSharePicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let folder = urls.first {
                    shareExport(to: folder)
                }
            }

            Button {
                NSWorkspace.shared.open(currentCopy.skillFileURL)
            } label: {
                Label(L("用默认编辑器打开"), systemImage: "square.and.pencil")
            }
            .help(L("用默认编辑器打开 SKILL.md"))
            .disabled(!currentCopy.hasSkillFile)

            if copyTargets.count == 1, let target = copyTargets.first {
                Button {
                    copy(to: target)
                } label: {
                    Label(L("复制到 \(target.displayName)"), systemImage: "arrow.right.doc.on.clipboard")
                }
                .help(L("复制到 \(target.displayName)"))
            } else if copyTargets.count > 1 {
                Menu {
                    ForEach(copyTargets) { target in
                        Button(L("复制到 \(target.displayName)")) { copy(to: target) }
                    }
                } label: {
                    Label(L("复制到…"), systemImage: "arrow.right.doc.on.clipboard")
                }
                .help(L("复制到…"))
            }

            if !skill.writableCopies.isEmpty {
                Button(role: .destructive) {
                    onDelete(skill)
                } label: {
                    Label(L("删除"), systemImage: "trash")
                }
                .help(L("移入废纸篓"))
            }
        }
    }

    /// Writable tools other than the current copy's, offered as copy
    /// destinations (existing copies flow into the overwrite confirmation).
    private var copyTargets: [Tool] {
        store.writableTools.filter { $0.id != currentCopy.tool.id }
    }

    private func copy(to target: Tool) {
        Task {
            let done = await store.copySkill(currentCopy, to: target, overwrite: false)
            if !done { overwriteCopyTarget = target }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .preview:
            if currentCopy.hasSkillFile {
                SimpleMarkdownView(
                    text: showPreviewTranslation ? (translatedPreview ?? previewSourceText) : previewSourceText
                )
                .overlay(alignment: .topTrailing) {
                    if canOfferPreviewTranslation {
                        Button {
                            togglePreviewTranslation()
                        } label: {
                            if isTranslatingPreview {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "translate")
                                    .foregroundStyle(showPreviewTranslation ? Color.accentColor : Color.secondary)
                            }
                        }
                        .buttonStyle(.borderless)
                        .padding(7)
                        .background(.regularMaterial, in: Circle())
                        .padding(10)
                        .help(showPreviewTranslation ? L("显示原文") : L("翻译"))
                    }
                }
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
        case .lint:
            lintView
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if FrontmatterParser.parseKeys(markdown: editorText) != nil {
                frontmatterForm
                Divider()
            }
            MarkdownTextEditor(text: $editorText)
            Divider()
            HStack {
                Button(L("历史…")) { showHistorySheet = true }
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
        .onChange(of: editorText) { syncFormFromEditor() }
        .sheet(isPresented: $showHistorySheet) {
            SnapshotHistorySheet(copy: currentCopy) { restored in
                editorText = restored
            }
        }
    }

    /// Structured editing for the two frontmatter keys tools care about.
    private var frontmatterForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(L("名称"), text: $fmName)
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .onChange(of: fmName) { applyFormToEditor(key: "name", value: fmName) }
            TextField(L("描述"), text: $fmDescription, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .lineLimit(1...3)
                .onChange(of: fmDescription) { applyFormToEditor(key: "description", value: fmDescription) }
        }
        .padding(10)
    }

    private func syncFormFromEditor() {
        let meta = FrontmatterParser.parse(markdown: editorText)
        let name = meta?.name ?? ""
        let description = meta?.description ?? ""
        if fmName != name { fmName = name }
        if fmDescription != description { fmDescription = description }
    }

    private func applyFormToEditor(key: String, value: String) {
        let current: String?
        switch key {
        case "name": current = FrontmatterParser.parse(markdown: editorText)?.name
        default: current = FrontmatterParser.parse(markdown: editorText)?.description
        }
        let singleLine = value.replacingOccurrences(of: "\n", with: " ")
        guard (current ?? "") != singleLine else { return }
        editorText = FrontmatterParser.settingKey(key, to: singleLine, in: editorText)
    }

    private var lintView: some View {
        let issues = SkillLinter.lint(
            markdown: hasUnsavedChanges ? editorText : loadedText,
            folderName: currentCopy.directoryURL.lastPathComponent,
            directory: currentCopy.directoryURL
        ).sorted { $0.severity > $1.severity }

        return Group {
            if issues.isEmpty {
                ContentUnavailableView {
                    Label(L("全部通过"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } description: {
                    Text(L("没有发现问题，这个 skill 的元数据和引用都很健康。"))
                }
            } else {
                List(issues) { issue in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: symbolName(for: issue.severity))
                            .foregroundStyle(color(for: issue.severity))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.message)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(issue.ruleID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func symbolName(for severity: LintIssue.Severity) -> String {
        switch severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(for severity: LintIssue.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .yellow
        case .info: return .blue
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
                        Text(displayedDescription(description))
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
                    if skill.copy(for: .claudeCode) != nil || currentCopy.tool.category == .project {
                        copyRow(
                            snippet: "/\(currentCopy.directoryURL.lastPathComponent)",
                            note: currentCopy.tool.category == .project
                                ? L("在该项目内的 Claude Code 会话中作为斜杠命令调用")
                                : L("Claude Code 中作为斜杠命令直接调用")
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

                if let origin = currentCopy.origin {
                    usageSection(title: L("来源与更新"), icon: "arrow.triangle.2.circlepath") {
                        originSection(origin)
                    }
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
    private func originSection(_ origin: SkillOrigin) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                if let url = URL(string: origin.sourceURL) {
                    Link(origin.sourceURL, destination: url)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(origin.sourceURL)
                        .font(.callout)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 12) {
                Text(L("安装于 \(origin.installedAt.formatted(date: .abbreviated, time: .shortened))"))
                if let commit = origin.commit {
                    Text(L("版本 \(String(commit.prefix(7)))"))
                        .font(.caption.monospaced())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    checkUpdate()
                } label: {
                    if isCheckingUpdate {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(L("检查更新"))
                    }
                }
                .disabled(isCheckingUpdate || isUpdating)

                switch updateStatus {
                case .none:
                    EmptyView()
                case .upToDate:
                    Label(L("已是最新"), systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .available(let sha):
                    Label(L("有可用更新（\(sha)）"), systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button(L("更新")) {
                        applyUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isUpdating)
                case .failed(let message):
                    Label(L("检查失败：\(message)"), systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            if case .available = updateStatus {
                Text(L("更新会覆盖本地修改（旧版本移入废纸篓）"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Description translation

    /// Target follows the app's UI language; source is auto-detected.
    static var translationTargetIdentifier: String {
        (Locale.preferredLanguages.first?.hasPrefix("zh") ?? false) ? "zh-Hans" : "en"
    }

    private func displayedDescription(_ original: String) -> String {
        showTranslation ? (translatedDescription ?? original) : original
    }

    /// Offer translation only when the description isn't already in the
    /// UI language (and the system framework is available).
    private func canOfferTranslation(for description: String) -> Bool {
        guard #available(macOS 15.0, *) else { return false }
        let wantsChinese = Self.translationTargetIdentifier == "zh-Hans"
        return wantsChinese
            ? !TextLanguage.isDominantlyCJK(description)
            : TextLanguage.isDominantlyCJK(description)
    }

    private func toggleTranslation(of description: String) {
        if showTranslation {
            showTranslation = false
        } else if translatedDescription != nil {
            showTranslation = true
        } else if !isTranslating {
            isTranslating = true
            translationRequest = [description]
        }
    }

    // MARK: - Preview translation

    private var previewSourceText: String {
        Self.stripFrontmatter(loadedText)
    }

    private var canOfferPreviewTranslation: Bool {
        guard #available(macOS 15.0, *) else { return false }
        let sample = String(previewSourceText.prefix(1500))
        guard sample.contains(where: { $0.isLetter }) else { return false }
        let wantsChinese = Self.translationTargetIdentifier == "zh-Hans"
        return wantsChinese
            ? !TextLanguage.isDominantlyCJK(sample)
            : TextLanguage.isDominantlyCJK(sample)
    }

    private func resetPreviewTranslation() {
        showPreviewTranslation = false
        translatedPreview = nil
        isTranslatingPreview = false
        previewRequest = nil
        previewPlan = nil
    }

    private func togglePreviewTranslation() {
        if showPreviewTranslation {
            showPreviewTranslation = false
        } else if translatedPreview != nil {
            showPreviewTranslation = true
        } else if !isTranslatingPreview {
            let plan = MarkdownTranslationPlan.make(
                markdown: previewSourceText,
                targetIsChinese: Self.translationTargetIdentifier == "zh-Hans"
            )
            guard !plan.segments.isEmpty else {
                store.showToast(Toast(L("没有需要翻译的内容"), style: .info))
                return
            }
            previewPlan = plan
            isTranslatingPreview = true
            previewRequest = plan.segments
        }
    }

    private func shareExport(to folder: URL) {
        let copy = currentCopy
        Task.detached {
            do {
                let result = try ShareExporter.export(copy: copy, to: folder)
                await MainActor.run {
                    store.showToast(Toast(L("已导出分享包")))
                    NSWorkspace.shared.activateFileViewerSelecting([result.zip, result.note])
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    store.showToast(Toast(L("导出失败：\(message)"), style: .error))
                }
            }
        }
    }

    private func checkUpdate() {
        isCheckingUpdate = true
        let copy = currentCopy
        Task {
            let result = await store.checkForUpdate(copy)
            updateStatus = result
            isCheckingUpdate = false
        }
    }

    private func applyUpdate() {
        isUpdating = true
        let copy = currentCopy
        Task {
            if await store.updateFromOrigin(copy) {
                updateStatus = SkillStore.UpdateCheckResult.upToDate
            }
            isUpdating = false
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
