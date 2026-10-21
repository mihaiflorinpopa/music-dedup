import Foundation
import MusicDedupCore

/// The last scan and what it found, under the current settings. Settings live in
/// UserDefaults, so their properties call `access` and `withMutation` themselves.
@MainActor @Observable
final class Model {
    private(set) var playlists: [Playlist] = []  // every playlist the last scan read
    private(set) var within: [[Entry]] = []  // per playlist: the entries to remove
    private(set) var across: [[Entry]] = []  // per song: its entry in each playlist
    private(set) var scanned = false
    private(set) var busy = false
    var error: String?

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
            analyze()
        }
    }

    func scan() async {
        error = nil
        await load()
    }

    func remove(_ entries: [Entry]) async {
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

    private func load() async {
        busy = true
        defer { busy = false }
        do {
            playlists = try await Task.detached { try MusicBridge.scan() }.value
            scanned = true
            analyze()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func analyze() {
        let options = MatchOptions(ignoreVersionTags: ignoreVersionTags, tolerance: tolerance)
        let included = playlists.filter { !skipped.contains($0.id) }
        within = included.map { findDuplicates(in: $0, options: options) }.filter { !$0.isEmpty }
        across = findCrossPlaylist(included, options: options)
    }
}
