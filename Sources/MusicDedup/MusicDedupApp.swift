import SwiftUI

@main
struct MusicDedupApp: App {
    @State private var model = Model()
    @State private var updater = Updater()

    var body: some Scene {
        Window("Music Dedup", id: "main") {
            ContentView(model: model).frame(minWidth: 560, minHeight: 440)
        }
        .commands {
            // Sparkle's SwiftUI guide puts "Check for Updates…" in the app menu.
            CommandGroup(after: .appInfo) {
                if updater.isAvailable {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                }
            }
        }
        Settings {
            SettingsView(model: model, updater: updater)
        }
    }
}
