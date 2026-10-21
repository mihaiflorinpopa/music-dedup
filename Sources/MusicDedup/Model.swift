import Foundation
import MusicDedupCore

/// The last scan and what it found, under the current settings. Settings live in
/// UserDefaults, so their properties call `access` and `withMutation` themselves.
@MainActor @Observable
final class Model {
    private(set) var playlists: [Playlist] = []  // every playlist the last scan read
    private(set) var within: [[Entry]] = []  // per playlist: the entries to remove
    private(set) var across: [[Entry]] = []  // per song: its entry in each playlist
    private(set) var librarySongs: [LibrarySong] = []  // every song in the library
    private(set) var library: [[LibrarySong]] = []  // per song: its copies in the library, the one to keep first
    private(set) var inPlaylists: [Int: [String]] = [:]  // database ID: names of the playlists it's in
    private(set) var scanned = false
    private(set) var busy = false
    var error: String?
    var notice: String?

    private let defaults = UserDefaults.standard

    var ignoreVersionTags: Bool {
        get {
            access(keyPath: \.ignoreVersionTags)
            return defaults.bool(forKey: "ignoreVersionTags")
        }
        set {
            withMutation(keyPath: \.ignoreVersionTags) { defaults.set(newValue, forKey: "ignoreVersionTags") }
            analyze()
        }
    }

    var foldText: Bool {
        get {
            access(keyPath: \.foldText)
            return defaults.bool(forKey: "foldText")
        }
        set {
            withMutation(keyPath: \.foldText) { defaults.set(newValue, forKey: "foldText") }
            analyze()
        }
    }

    var anyCreditedArtist: Bool {
        get {
            access(keyPath: \.anyCreditedArtist)
            return defaults.bool(forKey: "anyCreditedArtist")
        }
        set {
            withMutation(keyPath: \.anyCreditedArtist) { defaults.set(newValue, forKey: "anyCreditedArtist") }
            analyze()
        }
    }

    /// Seconds two copies of a song may differ in length.
    var tolerance: Double {
        get {
            access(keyPath: \.tolerance)
            return defaults.object(forKey: "tolerance") as? Double ?? MatchOptions().tolerance
        }
        set {
            withMutation(keyPath: \.tolerance) { defaults.set(newValue, forKey: "tolerance") }
            analyze()
        }
    }

    /// Persistent IDs of the playlists left out of the results.
    var skipped: Set<String> {
        get {
            access(keyPath: \.skipped)
            return Set(defaults.stringArray(forKey: "skippedPlaylists") ?? [])
        }
        set {
            withMutation(keyPath: \.skipped) { defaults.set(newValue.sorted(), forKey: "skippedPlaylists") }
            analyzePlaylists()
        }
    }

    // Each action returns at once while another runs: the next one would read Music mid-change.
    func scan() async {
        guard !busy else { return }
        error = nil
        await load()
    }

    func remove(_ entries: [Entry]) async {
        guard !busy else { return }
        error = nil
        busy = true
        do {
            try await Task.detached {
                for (id, group) in Dictionary(grouping: entries, by: \.playlistID) {
                    try MusicBridge.remove(group, from: id)
                }
            }.value
        } catch {
            self.error = error.localizedDescription
        }
        await load()  // positions shift after a removal
    }

    /// Adds library songs to the duplicates playlist, for the user to delete from the library in Music.
    func collect(_ ids: [Int]) async {
        guard !busy else { return }
        error = nil
        notice = nil
        busy = true
        defer { busy = false }
        do {
            let added = try await Task.detached { try MusicBridge.collect(ids) }.value
            notice = "Added \(added) \(added == 1 ? "song" : "songs") to “\(MusicBridge.duplicatesPlaylist)”. In Music, open that playlist, press ⌘A, Control-click and choose Delete from Library."
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func load() async {
        busy = true
        notice = nil
        defer { busy = false }
        do {
            let (found, songs) = try await Task.detached { (try MusicBridge.scan(), try MusicBridge.scanLibrary()) }.value
            // The duplicates playlist is the app's own; it isn't checked and doesn't count as a place a song is kept.
            playlists = found.filter { $0.name != MusicBridge.duplicatesPlaylist }
            librarySongs = songs
            inPlaylists = playlists.reduce(into: [:]) { result, p in
                for id in Set(p.tracks.map(\.id)) { result[id, default: []].append(p.name) }
            }
            scanned = true
            analyze()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var options: MatchOptions {
        MatchOptions(ignoreVersionTags: ignoreVersionTags, foldText: foldText, anyCreditedArtist: anyCreditedArtist, tolerance: tolerance)
    }

    private func analyze() {
        analyzePlaylists()
        library = findLibraryDuplicates(librarySongs, playlistCount: inPlaylists.mapValues(\.count), options: options)
    }

    private func analyzePlaylists() {
        let options = options, skipped = skipped  // read once, not once per playlist
        let included = playlists.filter { !skipped.contains($0.id) }
        within = included.map { findDuplicates(in: $0, options: options) }.filter { !$0.isEmpty }
        across = findCrossPlaylist(included, options: options, duplicates: Array(within.joined()))
    }
}
