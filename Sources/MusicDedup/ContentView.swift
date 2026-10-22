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
            unavailableList.tabItem { Label("Unavailable", systemImage: "exclamationmark.circle") }
            libraryList.tabItem { Label("Library", systemImage: "music.note.house") }
            // Here rather than in Settings: the HIG keeps filters in the view they affect.
            playlistList.tabItem { Label("Playlists", systemImage: "checklist") }
        }
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
        .disabled(model.busy)
        // Positions shift after a removal, and settings change what's listed:
        // keep only selected entries that are still on screen.
        .onChange(of: model.within) { pruneSelection() }
        .onChange(of: model.across) { pruneSelection() }
        .onChange(of: model.unavailable) { pruneSelection() }
        // Every extra copy starts checked; the first copy of each song is the one that stays.
        .onChange(of: model.library) { libraryChecked = extraCopies }
        .confirmationDialog("Remove \(counted(pending.count, "playlist entry", "playlist entries"))?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                selected.subtract(pending)
                Task { await model.remove(pending) }
            }
        } message: {
            // Not "songs stay in your library": many playlist songs were never added to it.
            Text("This only takes entries out of playlists. It doesn't delete songs from your library. With Sync Library on, the change reaches your other devices. A list of them is saved first: File > Show Removal Log.")
        }
    }

    private var withinList: some View {
        let total = model.within.joined().count
        return entryList(model.within, summary: "\(counted(total, "duplicate")) in \(counted(model.within.count, "playlist"))")
            .overlay { emptyState(model.within.isEmpty, "No Duplicates", "No song is in a playlist twice.") }
    }

    private var unavailableList: some View {
        let total = model.unavailable.joined().count
        return entryList(model.unavailable,
                         summary: "\(counted(total, "song")) in \(counted(model.unavailable.count, "playlist")) \(total == 1 ? "is" : "are") no longer available on Apple Music.")
            .overlay {
                emptyState(model.unavailable.isEmpty, "Nothing Unavailable", "No song in your playlists has been removed from Apple Music.",
                           matching: false)
            }
    }

    /// Entries to remove, one section per playlist.
    private func entryList(_ groups: [[Entry]], summary: String) -> some View {
        List {
            if model.scanned && !groups.isEmpty {
                HStack {
                    Text(summary)
                    Spacer()
                    if !groups.isEmpty { Button("Remove All") { confirm(Array(groups.joined())) } }
                }
            }
            ForEach(groups, id: \.[0]) { dups in
                Section {
                    ForEach(dups, id: \.index) { d in
                        Toggle(isOn: isSelected(d)) { TrackRow(track: d.track, position: d.index, detail: repeats(d)) }
                            .contextMenu {
                                // The same track twice is always a duplicate; only different tracks can be kept apart.
                                if let original = d.original, original.id != d.track.id {
                                    Button("Not a Duplicate") { model.notDuplicates.insert(TrackPair(d.track.id, original.id)) }
                                }
                            }
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
            ForEach(model.across, id: \.[0]) { group in
                Section {
                    ForEach(group, id: \.playlistID) { e in
                        Toggle(isOn: isSelected(e)) {
                            VStack(alignment: .leading) {
                                Text(e.playlistName)
                                Text((["#\(e.index + 1)", e.track.album.isEmpty ? nil : e.track.album] as [String?]).compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                            .contextMenu {
                                Button("Select All in “\(e.playlistName)”") {
                                    selected.formUnion(model.across.joined().filter { $0.playlistID == e.playlistID })
                                }
                                skipButton(e)
                            }
                    }
                } header: {
                    TrackRow(track: group[0].track, showAlbum: false, detail: "In \(counted(group.count, "playlist"))")
                }
            }
        }
        .toggleStyle(.checkbox)
        .overlay { emptyState(model.across.isEmpty, "No Duplicates", "No song is in more than one playlist.") }
    }

    private var libraryList: some View {
        List {
            if model.scanned && !model.library.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(counted(model.library.count, "song")) \(model.library.count == 1 ? "is" : "are") in your library more than once.")
                        Spacer()
                        Button("Check All") { libraryChecked = extraCopies }
                            .disabled(libraryChecked == extraCopies)
                        Button("Uncheck All") { libraryChecked = [] }
                            .disabled(libraryChecked.isEmpty)
                        Button("Add \(libraryChecked.count) to “\(MusicBridge.duplicatesPlaylist)”") {
                            Task { await model.collect(Array(libraryChecked)) }
                        }
                        .disabled(libraryChecked.isEmpty)
                    }
                    Text("The first copy of each song stays. The checked copies go into that playlist, and you delete them from your library in Music. Music Dedup never deletes library songs itself.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(model.library, id: \.[0].id) { copies in
                Section {
                    ForEach(copies.dropFirst()) { song in
                        Toggle(isOn: Binding(
                            get: { libraryChecked.contains(song.id) },
                            set: { if $0 { libraryChecked.insert(song.id) } else { libraryChecked.remove(song.id) } })) {
                            // Same album name: Music reports nothing that tells these copies apart.
                            LibraryRow(title: song.album, song: song, playlists: model.inPlaylists[song.id] ?? [],
                                       detailPrefix: song.album == copies[0].album ? "Same album as the copy kept" : nil)
                        }
                        .contextMenu {
                            Button("Not a Duplicate") { model.notDuplicates.insert(TrackPair(song.id, copies[0].id)) }
                        }
                    }
                } header: {
                    LibraryRow(title: copies[0].name, song: copies[0], playlists: model.inPlaylists[copies[0].id] ?? [],
                               detailPrefix: "Keep: \(copies[0].album)")
                }
            }
        }
        .toggleStyle(.checkbox)
        .overlay { emptyState(model.library.isEmpty, "No Duplicates", "No song is in your library twice.") }
    }

    /// Every library copy except the one kept of each song.
    private var extraCopies: Set<Int> {
        Set(model.library.flatMap { $0.dropFirst().map(\.id) })
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

    /// Takes the place of a tab's list when the last scan found nothing for it.
    @ViewBuilder
    private func emptyState(_ isEmpty: Bool, _ title: String, _ description: String, matching: Bool = true) -> some View {
        if model.scanned && !model.busy && isEmpty {
            ContentUnavailableView {
                Label(title, systemImage: "checkmark.circle")
            } description: {
                Text(description)
            } actions: {
                // The HIG (Writing): an empty state shows what people can do next, with a button.
                if matching { SettingsLink { Text("Matching Settings…") } }
            }
        }
    }

    private func isSelected(_ e: Entry) -> Binding<Bool> {
        Binding(get: { selected.contains(e) }, set: { if $0 { selected.insert(e) } else { selected.remove(e) } })
    }

    private func pruneSelection() {
        selected.formIntersection(Set(model.within.joined()).union(model.across.joined()).union(model.unavailable.joined()))
    }

    private func skipButton(_ e: Entry) -> some View {
        Button("Skip “\(e.playlistName)”") { model.skipped.insert(e.playlistID) }
    }

    /// What a duplicate inside a playlist repeats, so it's clear which two entries matched.
    private func repeats(_ d: Entry) -> String? {
        guard let i = d.originalIndex, let original = d.original else { return nil }
        if original.id == d.track.id { return "Same track as #\(i + 1)" }
        return "Same song as #\(i + 1): \(original.name)" + (original.album.isEmpty ? "" : ", \(original.album)")
    }

    private func confirm(_ entries: [Entry]) {
        pending = entries
        confirming = true
    }
}

/// "1 song", "2 songs".
func counted(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
    "\(n) \(n == 1 ? singular : plural ?? singular + "s")"
}

func minutesAndSeconds(_ seconds: Double) -> String {
    Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
}

/// A track: its position and title, then artist, album and length, then a detail line.
struct TrackRow: View {
    let track: Track
    var position: Int?  // in its playlist, from 0
    var showAlbum = true
    var detail: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text(position.map { "#\($0 + 1)  \(track.name)" } ?? track.name)
            Text(([track.artist, showAlbum && !track.album.isEmpty ? track.album : nil, minutesAndSeconds(track.duration)] as [String?])
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
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
            Text(([detailPrefix, song.artist, minutesAndSeconds(song.duration),
                   song.playedCount == 0 ? nil : counted(song.playedCount, "play"),
                   playlists.isEmpty ? nil : "in \(playlists.joined(separator: ", "))"] as [String?])
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
