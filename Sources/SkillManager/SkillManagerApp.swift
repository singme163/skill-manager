import SwiftUI
import AppKit
import SkillManagerCore

@main
struct SkillManagerApp: App {
    @StateObject private var store = SkillStore()

    init() {
        // Launched from a plain executable (swift run / app bundle alike):
        // make sure we behave as a regular foreground app.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("Skill Manager") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 880, minHeight: 540)
                .task {
                    await store.refresh()
                    store.startWatching()
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L("关于 Skill Manager")) { showAboutPanel() }
            }
            CommandGroup(replacing: .help) {
                Button(L("Skill Manager 帮助（GitHub）")) {
                    NSWorkspace.shared.open(AppInfo.repoURL)
                }
                Button(L("显示欢迎页")) {
                    UserDefaults.standard.set(false, forKey: "hasSeenWelcome")
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }

    private func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppInfo.version,
            .credits: NSAttributedString(
                string: L("开源的 Claude Code / Codex skill 管理工具"),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ),
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
