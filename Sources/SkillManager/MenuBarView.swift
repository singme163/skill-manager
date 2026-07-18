import SwiftUI
import AppKit
import SkillManagerCore

/// Menu bar extra: quick search across all skills, recent skills at rest,
/// one click to jump into the main window with the skill selected.
struct MenuBarView: View {
    @EnvironmentObject private var store: SkillStore
    @Environment(\.openWindow) private var openWindow

    @State private var searchText = ""

    private var matches: [Skill] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            return Array(
                store.skills
                    .sorted { $0.latestModified > $1.latestModified }
                    .prefix(6)
            )
        }
        return Array(
            store.skills.filter { skill in
                skill.displayName.localizedCaseInsensitiveContains(query)
                    || skill.folderName.localizedCaseInsensitiveContains(query)
                    || (skill.summary?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .prefix(10)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("搜索 skill"), text: $searchText)
                .textFieldStyle(.roundedBorder)

            if matches.isEmpty {
                Text(searchText.isEmpty ? L("还没有 skill") : L("没有匹配的 skill"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(L("最近更新"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(matches) { skill in
                        skillRow(skill)
                    }
                }
            }

            Divider()

            HStack {
                Button(L("打开 Skill Manager")) { openMainWindow() }
                Spacer()
                Button(L("退出")) { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 300)
    }

    private func skillRow(_ skill: Skill) -> some View {
        Button {
            store.pendingSelection = skill.id
            openMainWindow()
        } label: {
            HStack(spacing: 6) {
                Text(skill.displayName)
                    .lineLimit(1)
                Spacer()
                ForEach(skill.tools) { tool in
                    ToolBadge(tool: tool)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
    }

    private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
