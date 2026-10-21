import MusicDedupCore
import SwiftUI

struct ContentView: View {
    let model: Model
    @State private var pending: [Entry] = []
    @State private var confirming = false

    var body: some View {
        TabView {
            withinList.tabItem { Label("Within Playlists", systemImage: "music.note.list") }
            acrossList.tabItem { Label("Across Playlists", systemImage: "square.on.square") }
            // Here rather than in Settings: the HIG keeps filters in the view they affect.
            playlistList.tabItem { Label("Playlists", systemImage: "checklist") }
        }
        .disabled(model.busy)
        .toolbar {
            Button("Scan", systemImage: "arrow.clockwise") { Task { await model.scan() } }
                .disabled(model.busy)
        }
        .overlay {
            if model.busy {
                ProgressView("Talking to Music…").padding().background(.regularMaterial, in: .rect(cornerRadius: 8))
            } else if !model.scanned {
                ContentUnavailableView {
                    Label("Scan Your Playlists", systemImage: "music.note")
                } description: {
                    Text("Reads your own playlists from the Music app. Nothing changes until you confirm a removal.")
                } actions: {
                    Button("Scan") { Task { await model.scan() } }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let error = model.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled).padding(8)
            }
        }
        .confirmationDialog("Remove \(pending.count) playlist \(pending.count == 1 ? "entry" : "entries")?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await model.remove(pending) } }
        } message: {
            Text("Songs stay in your library. With Sync Library on, the change reaches your other devices.")
        }
    }

    private var withinList: some View {
        List {
            if model.scanned {
                let total = model.within.joined().count
                HStack {
                    Text(total == 0 ? "No duplicates inside any playlist." : "\(total) duplicates in \(model.within.count) playlists")
                    Spacer()
                    if total > 0 { Button("Remove All") { confirm(Array(model.within.joined())) } }
                }
            }
            ForEach(model.within, id: \.self) { dups in
                Section {
                    ForEach(dups, id: \.self) { TrackRow(track: $0.track, detail: $0.reason) }
                } header: {
                    HStack {
                        Text(dups[0].playlistName)
                        Spacer()
                        Button("Remove \(dups.count)") { confirm(dups) }
                    }
                    .contextMenu { skipButton(dups[0]) }
                }
            }
        }
    }

    private var acrossList: some View {
        List {
            if model.scanned && model.across.isEmpty { Text("No song is in more than one playlist.") }
            ForEach(model.across, id: \.self) { group in
                Section {
                    ForEach(group, id: \.self) { e in
                        HStack {
                            Text(e.playlistName)
                            Spacer()
                            Button("Remove from This Playlist") { confirm([e]) }
                        }
                        .contextMenu { skipButton(e) }
                    }
                } header: {
                    TrackRow(track: group[0].track, detail: "in \(Set(group.map(\.playlistID)).count) playlists")
                }
            }
        }
    }

    private var playlistList: some View {
        @Bindable var model = model
        return Form {
            Section {
                ForEach(model.playlists) { p in
                    Toggle(p.name, isOn: Binding(
                        get: { !model.skipped.contains(p.id) },
                        set: { if $0 { model.skipped.remove(p.id) } else { model.skipped.insert(p.id) } }))
                }
            } header: {
                Text("Check These Playlists")
            } footer: {
                Text("Turn off playlists you don't want changed, such as ones you follow.")
            }
        }
        .formStyle(.grouped)
    }

    private func skipButton(_ e: Entry) -> some View {
        Button("Skip “\(e.playlistName)”") { model.skipped.insert(e.playlistID) }
    }

    private func confirm(_ entries: [Entry]) {
        pending = entries
        confirming = true
    }
}

struct TrackRow: View {
    let track: Track
    let detail: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(track.name)
            Text("\(track.artist) · \(Duration.seconds(track.duration).formatted(.time(pattern: .minuteSecond))) · \(detail)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
