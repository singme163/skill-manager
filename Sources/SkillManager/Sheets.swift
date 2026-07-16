import SwiftUI
import SkillManagerCore

// MARK: - New blank skill

struct NewSkillSheet: View {
    @EnvironmentObject private var store: SkillStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var targets: Set<Tool> = []
    @State private var isWorking = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var nameIsValid: Bool { FrontmatterParser.isValidSkillName(trimmedName) }
    private var nameConflicts: [Tool] {
        guard let skill = store.skills.first(where: { $0.folderName == trimmedName }) else { return [] }
        return skill.tools.filter { targets.contains($0) }
    }
    private var canCreate: Bool {
        nameIsValid && nameConflicts.isEmpty && !targets.isEmpty && !isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("新建空白 Skill"))
                .font(.title3.weight(.semibold))

            Form {
                TextField(L("名称"), text: $name, prompt: Text(verbatim: "my-new-skill"))
                    .textFieldStyle(.roundedBorder)
                TextField(
                    L("描述"),
                    text: $descriptionText,
                    prompt: Text(L("这个 skill 做什么、什么时候用")),
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            }

            if !trimmedName.isEmpty && !nameIsValid {
                Label(
                    L("名称只能包含小写字母、数字和连字符，如 my-new-skill"),
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }
            if !nameConflicts.isEmpty {
                Label(
                    L("「\(trimmedName)」已存在于 \(nameConflicts.map(\.displayName).joined(separator: "、"))"),
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }

            ToolTargetPicker(tools: store.writableTools, targets: $targets)

            HStack {
                Spacer()
                Button(L("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("创建")) {
                    isWorking = true
                    Task {
                        let ok = await store.createTemplate(
                            name: trimmedName,
                            description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                            tools: Array(targets)
                        )
                        isWorking = false
                        if ok { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            if targets.isEmpty, let first = store.writableTools.first {
                targets = [first]
            }
        }
    }
}

// MARK: - GitHub install

struct GitHubInstallSheet: View {
    @EnvironmentObject private var store: SkillStore
    @Environment(\.dismiss) private var dismiss

    let onFound: ([InstallCandidate]) -> Void

    @State private var urlText = ""
    @State private var isDownloading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("从 GitHub 安装"))
                .font(.title3.weight(.semibold))
            Text(L("粘贴公开仓库或仓库子目录链接，例如\nhttps://github.com/org/repo 或 https://github.com/org/repo/tree/main/skills/foo"))
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(L("GitHub 链接"), text: $urlText, prompt: Text(verbatim: "https://github.com/…"))
                .textFieldStyle(.roundedBorder)
                .disabled(isDownloading)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("正在下载…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("下载并查找 Skill")) {
                    download()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isDownloading || urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func download() {
        errorMessage = nil
        isDownloading = true
        let url = urlText
        Task {
            do {
                let candidates = try await SkillInstaller.downloadFromGitHub(url)
                isDownloading = false
                dismiss()
                onFound(candidates)
            } catch {
                isDownloading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Candidates → targets

struct InstallCandidatesSheet: View {
    @EnvironmentObject private var store: SkillStore
    @Environment(\.dismiss) private var dismiss

    let candidates: [InstallCandidate]

    @State private var selectedCandidateIDs: Set<InstallCandidate.ID> = []
    @State private var targets: Set<Tool> = []
    @State private var conflicts: [SkillStore.InstallRequest] = []
    @State private var showOverwriteConfirm = false
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                candidates.count > 1
                    ? L("选择要安装的 Skill（找到 \(candidates.count) 个）")
                    : L("安装 Skill")
            )
            .font(.title3.weight(.semibold))

            List(candidates, selection: $selectedCandidateIDs) { candidate in
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(.headline)
                    Text(candidate.sourceDirectory.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .tag(candidate.id)
            }
            .frame(minHeight: 120, maxHeight: 220)
            .border(.quaternary)

            ToolTargetPicker(tools: store.writableTools, targets: $targets)

            HStack {
                Spacer()
                Button(L("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("安装")) {
                    Task { await install(overwrite: false) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedCandidateIDs.isEmpty || targets.isEmpty || isWorking)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            selectedCandidateIDs = Set(candidates.map(\.id))
            if targets.isEmpty, let first = store.writableTools.first {
                targets = [first]
            }
        }
        .confirmationDialog(
            L("存在同名 skill"),
            isPresented: $showOverwriteConfirm,
            titleVisibility: .visible
        ) {
            Button(L("覆盖（旧版本移入废纸篓）"), role: .destructive) {
                let pending = conflicts
                Task {
                    _ = await store.install(pending, overwrite: true)
                    dismiss()
                }
            }
            Button(L("跳过这些"), role: .cancel) { dismiss() }
        } message: {
            Text(conflicts.map { "\($0.candidate.name) → \($0.tool.displayName)" }.joined(separator: "\n"))
        }
    }

    private func install(overwrite: Bool) async {
        isWorking = true
        let requests = candidates
            .filter { selectedCandidateIDs.contains($0.id) }
            .flatMap { candidate in
                targets.map { SkillStore.InstallRequest(candidate: candidate, tool: $0) }
            }
        let remaining = await store.install(requests, overwrite: overwrite)
        isWorking = false
        if remaining.isEmpty {
            dismiss()
        } else {
            conflicts = remaining
            showOverwriteConfirm = true
        }
    }
}

// MARK: - Shared target picker

struct ToolTargetPicker: View {
    let tools: [Tool]
    @Binding var targets: Set<Tool>

    var body: some View {
        HStack(spacing: 16) {
            Text(L("安装到"))
                .foregroundStyle(.secondary)
            ForEach(tools) { tool in
                Toggle(tool.displayName, isOn: Binding(
                    get: { targets.contains(tool) },
                    set: { isOn in
                        if isOn { targets.insert(tool) } else { targets.remove(tool) }
                    }
                ))
                .toggleStyle(.checkbox)
            }
        }
        .font(.callout)
    }
}
