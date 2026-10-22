import Foundation
import MusicDedupCore

/// The last scan and what it found, under the current settings. Settings live in
/// UserDefaults, so their properties call `access` and `withMutation` themselves.
@MainActor @Observable
final class Model {
    private(set) var playlists: [Playlist] = []  // every playlist the last scan read
    private(set) var within: [[Entry]] = []  // per playlist: the entries to remove
    private(set) var across: [[Entry]] = []  // per song: its entry in each playlist
    private(set) var unavailable: [[Entry]] = []  // per playlist: entries Apple Music no longer has
    private(set) var librarySongs: [LibrarySong] = []  // every song in the library
    private(set) var library: [[LibrarySong]] = []  // per song: its copies in the library, the one to keep first
    private(set) var inPlaylists: [Int: [String]] = [:]  // database ID: names of the playlists it's in
    private(set) var scanned = false
    private(set) var busy = false
    private(set) var logged = RemovalLog.exists
    var error: String?
    var notice: String?

    private let defaults = UserDefaults.standard
    private let matcher = Matcher()
    @ObservationIgnored private var analysis: Task<Void, Never>?

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

    var sameAlbum: Bool {
        get {
            access(keyPath: \.sameAlbum)
            return defaults.bool(forKey: "sameAlbum")
        }
        set {
            withMutation(keyPath: \.sameAlbum) { defaults.set(newValue, forKey: "sameAlbum") }
            analyze()
        }
    }

    /// Pairs marked "Not a Duplicate", stored as "smaller-larger" database IDs.
    var notDuplicates: Set<TrackPair> {
        get {
            access(keyPath: \.notDuplicates)
            return Set((defaults.stringArray(forKey: "notDuplicates") ?? []).compactMap { pair in
                let ids = pair.split(separator: "-").compactMap { Int($0) }
                return ids.count == 2 ? TrackPair(ids[0], ids[1]) : nil
            })
        }
        set {
            withMutation(keyPath: \.notDuplicates) {
                defaults.set(newValue.map { "\($0.first)-\($0.second)" }.sorted(), forKey: "notDuplicates")
            }
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
            analyze(includingLibrary: false)  // skipping playlists doesn't change the library groups
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
        ProcessInfo.processInfo.disableSuddenTermination()
        defer { ProcessInfo.processInfo.enableSuddenTermination() }
        do {
            try RemovalLog.removing(entries)  // nothing is removed unless it's logged first
            logged = true
            try await Task.detached(priority: .userInitiated) {
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
        ProcessInfo.processInfo.disableSuddenTermination()
        defer {
            busy = false
            ProcessInfo.processInfo.enableSuddenTermination()
        }
        do {
            let wanted = Set(ids)
            try RemovalLog.collecting(librarySongs.filter { wanted.contains($0.id) })
            logged = true
            let added = try await Task.detached(priority: .userInitiated) { try MusicBridge.collect(ids) }.value
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
            let (found, songs) = try await Task.detached(priority: .userInitiated) { (try MusicBridge.scan(), try MusicBridge.scanLibrary()) }.value
            // The duplicates playlist is the app's own; it isn't checked and doesn't count as a place a song is kept.
            playlists = found.filter { $0.name != MusicBridge.duplicatesPlaylist }
            librarySongs = songs
            inPlaylists = playlists.reduce(into: [:]) { result, p in
                for id in Set(p.tracks.map(\.id)) { result[id, default: []].append(p.name) }
            }
            scanned = true
            analyze()
            await analysis?.value  // still busy until the results are in
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var options: MatchOptions {
        MatchOptions(ignoreVersionTags: ignoreVersionTags, foldText: foldText, anyCreditedArtist: anyCreditedArtist, tolerance: tolerance,
                     sameAlbum: sameAlbum, notDuplicates: notDuplicates)
    }

    /// Matches in the background, so the window stays responsive: with every option on, a large
    /// library takes about half a second. A newer analysis makes an unfinished one's results stale.
    private func analyze(includingLibrary: Bool = true) {
        let options = options, skipped = skipped  // read once, not once per playlist
        let included = playlists.filter { !skipped.contains($0.id) }
        let songs = includingLibrary ? librarySongs : nil, counts = inPlaylists.mapValues(\.count)
        analysis?.cancel()
        analysis = Task {
            let found = await matcher.analyze(included, library: songs, playlistCount: counts, options: options)
            guard !Task.isCancelled else { return }
            within = found.within
            across = found.across
            unavailable = found.unavailable
            if let library = found.library { self.library = library }
        }
    }
}

/// Runs matching off the main actor, one analysis at a time: Dedup.swift's compiled regexes are
/// shared, so two analyses mustn't run at once (see AGENTS.md).
actor Matcher {
    struct Found: Sendable {
        let within: [[Entry]]  // per playlist: the entries to remove
        let across: [[Entry]]  // per song: its entry in each playlist
        let unavailable: [[Entry]]  // per playlist: entries Apple Music no longer has
        let library: [[LibrarySong]]?  // nil when the library wasn't analyzed
    }

    func analyze(_ playlists: [Playlist], library songs: [LibrarySong]?, playlistCount: [Int: Int], options: MatchOptions) -> Found {
        let within = playlists.map { findDuplicates(in: $0, options: options) }.filter { !$0.isEmpty }
        return Found(within: within,
                     across: findCrossPlaylist(playlists, options: options, duplicates: Array(within.joined())),
                     unavailable: playlists.map(findUnavailable).filter { !$0.isEmpty },
                     library: songs.map { findLibraryDuplicates($0, playlistCount: playlistCount, options: options) })
    }
}
