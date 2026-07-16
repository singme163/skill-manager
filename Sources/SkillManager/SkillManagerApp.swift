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

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
