import MusicDedupCore
import SwiftUI

/// The Settings window (⌘,), one pane per group. It opens on the pane used last,
/// as the HIG asks. Matching changes apply to the last scan right away.
struct SettingsView: View {
    var model: Model
    var updater: Updater
    @AppStorage("settingsPane") private var pane = Pane.matching

    enum Pane: String {
        case matching, general
    }

    var body: some View {
        TabView(selection: $pane) {
            MatchingSettings(model: model)
                .fixedSize(horizontal: false, vertical: true)
                .tabItem { Label("Matching", systemImage: "equal.square") }
                .tag(Pane.matching)
            GeneralSettings(updater: updater)
                .fixedSize(horizontal: false, vertical: true)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Pane.general)
        }
        .frame(width: 460)
    }
}

struct MatchingSettings: View {
    @Bindable var model: Model

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.ignoreVersionTags) {
                    OptionLabel(
                        title: "Ignore Version Tags",
                        detail: "Treats “Song”, “Song (Remastered 2011)”, “Song - Radio Edit”, “Song (Deluxe Edition)” and “Song (feat. Guest)” as one song. Remixes and live versions stay apart.")
                }
                Toggle(isOn: $model.foldText) {
                    OptionLabel(
                        title: "Ignore Accents and Punctuation",
                        detail: "Treats “Red-Nosed” and “Red Nosed”, “Beyoncé” and “Beyonce”, and “&” and “and” as the same.")
                }
                Toggle(isOn: $model.anyCreditedArtist) {
                    OptionLabel(
                        title: "Match Any Credited Artist",
                        detail: "Treats “Song (feat. Guest)” by Main and “Song” by Guest & Main as one song. Otherwise only the first artist counts.")
                }
                Toggle(isOn: $model.sameAlbum) {
                    OptionLabel(
                        title: "Same Album Only",
                        detail: "Counts copies as one song only when they're also on the same album, like Music's Show Exact Duplicate Items. Copies on a single, a compilation or a reissue stay apart.")
                }
                Picker(selection: $model.tolerance) {
                    ForEach([1.0, 2, 5, 10], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                } label: {
                    OptionLabel(
                        title: "Length Difference",
                        detail: "How much two copies of a song may differ in length. The default is 2 seconds.")
                }
                LabeledContent {
                    Button("Forget") { model.notDuplicates = [] }
                        .disabled(model.notDuplicates.isEmpty)
                } label: {
                    OptionLabel(
                        title: "Not a Duplicate",
                        detail: "\(counted(model.notDuplicates.count, "pair")) you kept apart with Control-click > Not a Duplicate. Forget them to see those matches again.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct GeneralSettings: View {
    @Bindable var updater: Updater

    var body: some View {
        Form {
            Section {
                if updater.isAvailable {
                    Toggle(isOn: $updater.automaticallyChecks) {
                        OptionLabel(
                            title: "Check for Updates Automatically",
                            detail: "Checks for a new version when Music Dedup opens and once a day, and asks before installing it.")
                    }
                }
                LabeledContent("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")") {
                    if updater.isAvailable {
                        Button("Check for Updates…") { updater.checkForUpdates() }
                            .disabled(!updater.canCheck)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// An option's title with a one-line description under it.
struct OptionLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
