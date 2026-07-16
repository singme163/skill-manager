import SwiftUI
import SkillManagerCore

/// Edit-history browser: snapshots taken automatically before each in-app
/// save. Restoring loads the snapshot into the editor (save to apply).
struct SnapshotHistorySheet: View {
    @EnvironmentObject private var store: SkillStore
    @Environment(\.dismiss) private var dismiss

    let copy: SkillCopy
    let onRestore: (String) -> Void

    @State private var snapshots: [SnapshotStore.Snapshot] = []
    @State private var selectedID: SnapshotStore.Snapshot.ID?

    private var selectedSnapshot: SnapshotStore.Snapshot? {
        snapshots.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("编辑历史"))
                .font(.title3.weight(.semibold))
            Text(L("每次在 App 内保存前会自动快照当前版本（每个 skill 最多保留 20 份）。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if snapshots.isEmpty {
                ContentUnavailableView(
                    L("还没有历史快照"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(L("在 App 内保存过一次之后，这里就会出现可回滚的版本。"))
                )
                .frame(minHeight: 160)
            } else {
                HSplitView {
                    List(snapshots, selection: $selectedID) { snapshot in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.date.formatted(date: .abbreviated, time: .standard))
                            Text(ByteCountFormatter.string(fromByteCount: snapshot.sizeBytes, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .tag(snapshot.id)
                    }
                    .frame(minWidth: 180, maxWidth: 220)

                    Group {
                        if let snapshot = selectedSnapshot,
                           let contents = SnapshotStore.read(snapshot) {
                            ScrollView {
                                Text(contents)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                        } else {
                            ContentUnavailableView(
                                L("选择一个快照预览"),
                                systemImage: "doc.text.magnifyingglass"
                            )
                        }
                    }
                    .frame(minWidth: 260)
                }
                .frame(minHeight: 260, maxHeight: 340)
                .border(.quaternary)
            }

            HStack {
                Spacer()
                Button(L("关闭")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("载入编辑器")) {
                    if let snapshot = selectedSnapshot,
                       let contents = SnapshotStore.read(snapshot) {
                        onRestore(contents)
                        store.showToast(Toast(L("已载入快照，保存后生效"), style: .info))
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedSnapshot == nil)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            snapshots = SnapshotStore.snapshots(for: copy)
            selectedID = snapshots.first?.id
        }
    }
}
