import MusicDedupCore
import SwiftUI

struct ContentView: View {
    let model: Model
    @State private var selected: Set<Entry> = []
    @State private var pending: [Entry] = []
    @State private var confirming = false
    @State private var libraryChecked: Set<Int> = []  // database IDs of library copies to collect

    var body: some View {
        TabView {
            withinList.tabItem { Label("Within Playlists", systemImage: "music.note.list") }
            acrossList.tabItem { Label("Across Playlists", systemImage: "square.on.square") }
            libraryList.tabItem { Label("Library", systemImage: "music.note.house") }
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
                    Text("Reads your own playlists and your library from the Music app. Nothing changes until you confirm.")
                } actions: {
                    Button("Scan") { Task { await model.scan() } }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let error = model.error {
                    Text(error).foregroundStyle(.red).textSelection(.enabled).padding(8)
                }
                if let notice = model.notice {
                    Text(notice).textSelection(.enabled).padding(8)
                }
                if !selected.isEmpty {
                    HStack {
                        Text("\(selected.count) selected")
                        Spacer()
                        Button("Deselect All") { selected = [] }
                        Button("Remove Selected") { confirm(Array(selected)) }
                            .keyboardShortcut(.delete, modifiers: .command)
                    }
                    .padding(8)
                    .background(.bar)
                }
            }
        }
        // Positions shift after a removal, and settings change what's listed:
        // keep only selected entries that are still on screen.
        .onChange(of: model.within) { pruneSelection() }
        .onChange(of: model.across) { pruneSelection() }
        // Every extra copy starts checked; the first copy of each song is the one that stays.
        .onChange(of: model.library) { libraryChecked = Set(model.library.flatMap { $0.dropFirst().map(\.id) }) }
        .confirmationDialog("Remove \(pending.count) playlist \(pending.count == 1 ? "entry" : "entries")?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                selected.subtract(pending)
                Task { await model.remove(pending) }
            }
        } message: {
            // Not "songs stay in your library": many playlist songs were never added to it.
            Text("This only takes entries out of playlists. It doesn't delete songs from your library. With Sync Library on, the change reaches your other devices.")
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
                    ForEach(dups, id: \.self) { d in
                        Toggle(isOn: isSelected(d)) { TrackRow(track: d.track, detail: d.reason) }
                    }
                } header: {
                    HStack {
                        // Checks every row below it, and shows a dash when only some are checked.
                        Toggle(sources: dups.map(isSelected), isOn: \.self) { Text(dups[0].playlistName) }
                        Spacer()
                        Button("Remove \(dups.count)") { confirm(dups) }
                    }
                    .contextMenu { skipButton(dups[0]) }
                }
            }
        }
        .toggleStyle(.checkbox)
    }

    private var acrossList: some View {
        List {
            if model.scanned && model.across.isEmpty { Text("No song is in more than one playlist.") }
            ForEach(model.across, id: \.self) { group in
                Section {
                    ForEach(group, id: \.self) { e in
                        Toggle(e.playlistName, isOn: isSelected(e))
                            .contextMenu {
                                Button("Select All in “\(e.playlistName)”") {
                                    selected.formUnion(model.across.joined().filter { $0.playlistID == e.playlistID })
                                }
                                skipButton(e)
                            }
                    }
                } header: {
                    TrackRow(track: group[0].track, detail: "in \(Set(group.map(\.playlistID)).count) playlists")
                }
            }
        }
        .toggleStyle(.checkbox)
    }

    private var libraryList: some View {
        List {
            if model.scanned {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.library.isEmpty ? "No song is in your library twice."
                             : "\(model.library.count) songs are in your library more than once.")
                        Spacer()
                        if !model.library.isEmpty {
                            Button("Add \(libraryChecked.count) to “\(MusicBridge.duplicatesPlaylist)”") {
                                Task { await model.collect(Array(libraryChecked)) }
                            }
                            .disabled(libraryChecked.isEmpty)
                        }
                    }
                    if !model.library.isEmpty {
                        Text("The first copy of each song stays. The checked copies go into that playlist, and you delete them from your library in Music. Music Dedup never deletes library songs itself.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(model.library, id: \.self) { copies in
                Section {
                    ForEach(copies.dropFirst()) { song in
                        Toggle(isOn: Binding(
                            get: { libraryChecked.contains(song.id) },
                            set: { if $0 { libraryChecked.insert(song.id) } else { libraryChecked.remove(song.id) } })) {
                            LibraryRow(title: song.album, song: song, playlists: model.inPlaylists[song.id] ?? [])
                        }
                    }
                } header: {
                    LibraryRow(title: copies[0].name, song: copies[0], playlists: model.inPlaylists[copies[0].id] ?? [],
                               detailPrefix: "Keep: \(copies[0].album)")
                }
            }
        }
        .toggleStyle(.checkbox)
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

    private func isSelected(_ e: Entry) -> Binding<Bool> {
        Binding(get: { selected.contains(e) }, set: { if $0 { selected.insert(e) } else { selected.remove(e) } })
    }

    private func pruneSelection() {
        selected.formIntersection(Set(model.within.joined()).union(model.across.joined()))
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

/// A library copy: its title, then where it's from and how much it's used.
struct LibraryRow: View {
    let title: String
    let song: LibrarySong
    let playlists: [String]
    var detailPrefix: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
            Text(([detailPrefix, song.artist, Duration.seconds(song.duration).formatted(.time(pattern: .minuteSecond)),
                   "\(song.playedCount) \(song.playedCount == 1 ? "play" : "plays")",
                   playlists.isEmpty ? nil : "in \(playlists.joined(separator: ", "))"] as [String?])
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
