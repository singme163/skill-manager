import SwiftUI
import AppKit
import SkillManagerCore

/// Curated skill index: browse, search, and one-click install through the
/// existing GitHub pipeline. Index data lives in the app repository
/// (community PRs welcome) with a bundled offline snapshot as fallback.
struct DiscoverySheet: View {
    @Environment(\.dismiss) private var dismiss

    let onFound: ([InstallCandidate]) -> Void

    @State private var entries: [SkillIndexEntry] = []
    @State private var isLoading = true
    @State private var usedFallback = false
    @State private var searchText = ""
    @State private var installingID: SkillIndexEntry.ID?
    @State private var errorMessage: String?

    private var filteredEntries: [SkillIndexEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(query)
                || entry.description.localizedCaseInsensitiveContains(query)
                || entry.author.localizedCaseInsensitiveContains(query)
                || (entry.tags ?? []).contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("发现 Skill"))
                    .font(.title3.weight(.semibold))
                Spacer()
                if usedFallback {
                    Label(L("索引加载失败，已显示内置副本。"), systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Text(L("精选 skill 索引，社区可通过仓库 PR 收录。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(L("搜索名称、描述或标签"), text: $searchText)
                .textFieldStyle(.roundedBorder)

            Group {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView(L("正在加载索引…"))
                        Spacer()
                    }
                    .frame(minHeight: 200)
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        L("没有匹配的条目"),
                        systemImage: "magnifyingglass"
                    )
                    .frame(minHeight: 200)
                } else {
                    List(filteredEntries) { entry in
                        entryRow(entry)
                    }
                    .frame(minHeight: 240, maxHeight: 360)
                    .border(.quaternary)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(L("关闭")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task {
            let result = await SkillIndexLoader.load()
            entries = result.entries
            usedFallback = !result.fromRemote
            isLoading = false
        }
    }

    private func entryRow(_ entry: SkillIndexEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.headline)
                    ForEach(entry.tags ?? [], id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary.opacity(0.6), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(entry.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.author)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    install(entry)
                } label: {
                    if installingID == entry.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(L("安装"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(installingID != nil)

                Button {
                    if let url = URL(string: entry.url) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help(L("在浏览器打开"))
            }
        }
        .padding(.vertical, 4)
    }

    private func install(_ entry: SkillIndexEntry) {
        errorMessage = nil
        installingID = entry.id
        Task {
            do {
                let candidates = try await SkillInstaller.downloadFromGitHub(entry.url)
                installingID = nil
                dismiss()
                onFound(candidates)
            } catch {
                installingID = nil
                errorMessage = "\(entry.name)：\(error.localizedDescription)"
            }
        }
    }
}
