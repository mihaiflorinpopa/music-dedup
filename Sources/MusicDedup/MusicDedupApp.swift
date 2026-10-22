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
            CommandGroup(after: .newItem) {
                Button("Show Removal Log") { NSWorkspace.shared.activateFileViewerSelecting([RemovalLog.url]) }
                    .disabled(!model.logged)
            }
            // Sparkle's SwiftUI guide puts "Check for Updates…" in the app menu; the HIG keeps About
            // alone in its group and puts custom items after Settings.
            CommandGroup(after: .appSettings) {
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
