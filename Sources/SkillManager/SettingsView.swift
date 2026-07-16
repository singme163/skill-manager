import SwiftUI
import SkillManagerCore

struct SettingsView: View {
    @EnvironmentObject private var store: SkillStore

    @State private var showCustomToolSheet = false
    @State private var showProjectImporter = false

    var body: some View {
        Form {
            Section(L("工具")) {
                ForEach(store.regularTools) { tool in
                    toolRow(tool)
                }
                Menu(L("添加工具")) {
                    ForEach(store.availablePresets) { preset in
                        Button(preset.displayName) {
                            Task { await store.addTool(preset) }
                        }
                    }
                    if !store.availablePresets.isEmpty {
                        Divider()
                    }
                    Button(L("自定义工具…")) { showCustomToolSheet = true }
                }
                Text(L("内置工具不可移除；修改路径后点击重新扫描生效。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("项目")) {
                ForEach(store.projects) { project in
                    toolRow(project)
                }
                Button(L("添加项目…")) { showProjectImporter = true }
                Text(L("登记项目后，管理其中的 .claude/skills 目录；也可以直接把项目文件夹拖进主窗口。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button(L("立即重新扫描")) {
                    Task {
                        await store.refresh()
                        store.startWatching()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding(.vertical, 8)
        .sheet(isPresented: $showCustomToolSheet) {
            CustomToolSheet()
        }
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

    @ViewBuilder
    private func toolRow(_ tool: Tool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: tool.symbolName)
                .frame(width: 20)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tool.displayName)
                        .font(.headline)
                    if tool.isReadOnly {
                        Label(L("只读"), systemImage: "lock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
                TextField(
                    L("路径"),
                    text: Binding(
                        get: { tool.directoryPath },
                        set: { store.updateToolPath(tool, to: $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .labelsHidden()
            }
            Spacer()
            if !tool.isBuiltIn {
                Button {
                    Task { await store.removeTool(tool) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(L("移除"))
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Custom tool

struct CustomToolSheet: View {
    @EnvironmentObject private var store: SkillStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var path = ""

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !path.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("自定义工具"))
                .font(.title3.weight(.semibold))
            Text(L("任何遵循「目录/skill 名/SKILL.md」约定的工具都可以接入。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Form {
                TextField(L("工具名称"), text: $name, prompt: Text(verbatim: "Gemini CLI"))
                    .textFieldStyle(.roundedBorder)
                TextField(L("路径"), text: $path, prompt: Text(verbatim: "~/.gemini/skills"))
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
            }

            HStack {
                Spacer()
                Button(L("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("添加")) {
                    let tool = ToolRegistry.makeCustomTool(
                        name: name,
                        directoryPath: path,
                        existing: store.tools
                    )
                    Task {
                        await store.addTool(tool)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
