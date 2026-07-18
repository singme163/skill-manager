import SwiftUI
import AppKit
import SkillManagerCore

/// Works around a SwiftUI quirk where an app with both a WindowGroup and a
/// MenuBarExtra occasionally launches without presenting the main window:
/// if no sizable window appeared shortly after launch, send ourselves a
/// reopen (which reliably materializes the WindowGroup).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureMainWindow(retries: 3)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    private func ensureMainWindow(retries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let hasWindow = NSApp.windows.contains { $0.isVisible && $0.frame.width > 400 }
            guard !hasWindow, retries > 0,
                  Bundle.main.bundleURL.pathExtension == "app" else { return }
            NSWorkspace.shared.open(Bundle.main.bundleURL)
            self.ensureMainWindow(retries: retries - 1)
        }
    }
}

@main
struct SkillManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = SkillStore()

    init() {
        // Launched from a plain executable (swift run / app bundle alike):
        // make sure we behave as a regular foreground app.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @AppStorage("menuBarEnabled") private var menuBarEnabled = true

    var body: some Scene {
        WindowGroup("Skill Manager", id: "main") {
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

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarView()
                .environmentObject(store)
        } label: {
            Image(systemName: "puzzlepiece.extension")
        }
        .menuBarExtraStyle(.window)

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
