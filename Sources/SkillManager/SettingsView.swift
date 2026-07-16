import SwiftUI
import SkillManagerCore

struct SettingsView: View {
    @EnvironmentObject private var store: SkillStore

    @AppStorage(Tool.claudeCode.pathOverrideDefaultsKey) private var claudePathOverride = ""
    @AppStorage(Tool.codex.pathOverrideDefaultsKey) private var codexPathOverride = ""

    var body: some View {
        Form {
            Section("Skills 目录") {
                pathField(
                    tool: .claudeCode,
                    override: $claudePathOverride
                )
                pathField(
                    tool: .codex,
                    override: $codexPathOverride
                )
                Text("留空使用默认路径。修改后点击刷新或重新打开 App 生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("立即重新扫描") {
                    Task {
                        await store.refresh()
                        store.startWatching()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func pathField(tool: Tool, override: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(
                tool.displayName,
                text: override,
                prompt: Text(tool.defaultSkillsDirectory.path)
            )
            .textFieldStyle(.roundedBorder)
            .font(.callout.monospaced())
            Text("当前生效：\(tool.skillsDirectory.path)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
