import Foundation

public struct Track: Codable, Hashable, Sendable {
    public let id: Int  // Music "database ID": shared by every playlist entry of the same library track
    public let name: String
    public let artist: String
    public let duration: Double  // seconds

    public init(id: Int, name: String, artist: String, duration: Double) {
        self.id = id
        self.name = name
        self.artist = artist
        self.duration = duration
    }
}

public struct Playlist: Codable, Hashable, Sendable, Identifiable {
    public let id: String  // Music "persistent ID"
    public let name: String
    public let tracks: [Track]

    public init(id: String, name: String, tracks: [Track]) {
        self.id = id
        self.name = name
        self.tracks = tracks
    }
}

/// One track at one position in one playlist: the unit that gets removed.
public struct Entry: Hashable, Sendable {
    public let playlistID: String
    public let playlistName: String
    public let index: Int
    public let track: Track
    public var reason = ""
}

/// How loosely two tracks may differ and still count as the same song.
/// The defaults are spotify-dedup's rules.
public struct MatchOptions: Equatable, Sendable {
    /// Compare titles without tags that name a release rather than a recording,
    /// such as "(Remastered 2011)", " - Radio Edit" or "(feat. X)".
    public var ignoreVersionTags = false
    /// Largest length difference, in seconds, between two copies of a song.
    public var tolerance: Double = 2

    public init(ignoreVersionTags: Bool = false, tolerance: Double = 2) {
        self.ignoreVersionTags = ignoreVersionTags
        self.tolerance = tolerance
    }
}

/// spotify-dedup's rules: a later entry is a duplicate if it is the same track, or has
/// the same name and first artist (case-insensitive) and a length within the tolerance.
public func findDuplicates(in playlist: Playlist, options: MatchOptions = .init()) -> [Entry] {
    var seenIDs = Set<Int>()
    var seenDurations: [String: [Double]] = [:]
    var dups: [Entry] = []
    for (i, t) in playlist.tracks.enumerated() {
        let key = matchKey(t, options: options)
        let reason = seenIDs.contains(t.id) ? "same track"
            : seenDurations[key, default: []].contains { abs($0 - t.duration) < options.tolerance } ? "same name and artist"
            : nil
        if let reason {
            dups.append(Entry(playlistID: playlist.id, playlistName: playlist.name, index: i, track: t, reason: reason))
        } else {
            seenIDs.insert(t.id)
            seenDurations[key, default: []].append(t.duration)
        }
    }
    return dups
}

/// Songs that sit in more than one playlist (same matching rules), one group per song.
public func findCrossPlaylist(_ playlists: [Playlist], options: MatchOptions = .init()) -> [[Entry]] {
    var groups: [String: [[Entry]]] = [:]
    for p in playlists {
        let dups = Set(findDuplicates(in: p, options: options).map(\.index))
        for (i, t) in p.tracks.enumerated() where !dups.contains(i) {
            let e = Entry(playlistID: p.id, playlistName: p.name, index: i, track: t)
            let key = matchKey(t, options: options)
            if let g = groups[key]?.firstIndex(where: { abs($0[0].track.duration - t.duration) < options.tolerance }) {
                groups[key]![g].append(e)
            } else {
                groups[key, default: []].append([e])
            }
        }
    }
    return groups.values.joined()
        .filter { Set($0.map(\.playlistID)).count > 1 }
        .sorted { $0[0].track.name.localizedStandardCompare($1[0].track.name) == .orderedAscending }
}

/// Lowercased name + first credited artist, like spotify-dedup's `name:artists[0]`.
func matchKey(_ t: Track, options: MatchOptions = .init()) -> String {
    let name = options.ignoreVersionTags ? stripVersionTags(t.name) : t.name
    let first = t.artist.lowercased()
        .split(separator: #/,|&|\bfeat\.?\s|\bft\.\s|\bfeaturing\s/#, maxSplits: 1).first ?? ""
    return name.lowercased().trimmingCharacters(in: .whitespaces) + ":" + first.trimmingCharacters(in: .whitespaces)
}

/// Removes bracketed parts and " - " suffixes that name a release, not a recording.
/// Remixes, live and acoustic versions are kept: they are different recordings.
func stripVersionTags(_ title: String) -> String {
    let tag = #/(?i)\b(remaster(ed)?|radio edit|single version|album version|original mix|mono|stereo|explicit|clean|bonus track)\b|^\W*(feat\.?|ft\.|featuring|with)\s/#
    return title.replacing(#/\s*[(\[]([^)\]]*)[)\]]|\s+[-–—]\s+(.*)$/#) { match in
        let inner = match.output.1 ?? match.output.2 ?? ""
        return inner.contains(tag) ? "" : String(match.output.0)
    }
}
