import SwiftUI
import SkillManagerCore

/// First-launch welcome sheet: what the app manages and where.
/// Re-openable from the Help menu.
struct WelcomeSheet: View {
    @EnvironmentObject private var store: SkillStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.accentColor)
            Text(L("欢迎使用 Skill Manager"))
                .font(.title2.weight(.semibold))
            Text(L("在一个窗口里管理 Claude Code 与 Codex 的全部 skill"))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                row(
                    icon: "square.grid.2x2",
                    title: L("统一盘点"),
                    detail: L("两个工具的 skill 合并展示，搜索、排序、双端徽标一目了然")
                )
                row(
                    icon: "plus.circle",
                    title: L("四种安装方式"),
                    detail: L("本地文件夹 / zip、拖拽、新建模板、跨工具复制、GitHub 链接")
                )
                row(
                    icon: "trash",
                    title: L("安全删除"),
                    detail: L("删除只会移入废纸篓，随时可恢复")
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.tools) { tool in
                        directoryRow(tool)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            } label: {
                Text(L("管理的目录"))
            }

            Button(L("开始使用")) { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(24)
        .frame(width: 470)
    }

    private func row(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func directoryRow(_ tool: Tool) -> some View {
        let exists = FileManager.default.fileExists(atPath: tool.skillsDirectory.path)
        return HStack(spacing: 8) {
            ToolBadge(tool: tool)
            Text(tool.skillsDirectory.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(exists ? L("已存在") : L("不存在（安装首个 skill 时会自动创建）"))
                .font(.caption)
                .foregroundStyle(exists ? Color.green : Color.orange)
        }
    }
}
