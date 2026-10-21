import Foundation

public struct Track: Codable, Hashable, Sendable {
    public let id: Int  // Music "database ID": shared by every playlist entry of the same library track
    public let name: String
    public let artist: String
    public let duration: Double  // seconds
    public let album: String  // shown to tell copies apart; matching doesn't use it

    public init(id: Int, name: String, artist: String, duration: Double, album: String = "") {
        self.id = id
        self.name = name
        self.artist = artist
        self.duration = duration
        self.album = album
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
    /// For a duplicate inside a playlist: the position of the earlier entry it repeats.
    public var originalIndex: Int?
    public var original: Track?
}

/// A song in the library, with what decides which copy to keep.
public struct LibrarySong: Codable, Hashable, Sendable, Identifiable {
    public let id: Int  // Music "database ID"
    public let name: String
    public let artist: String
    public let duration: Double  // seconds
    public let album: String
    public let playedCount: Int

    public init(id: Int, name: String, artist: String, duration: Double, album: String, playedCount: Int) {
        self.id = id
        self.name = name
        self.artist = artist
        self.duration = duration
        self.album = album
        self.playedCount = playedCount
    }

    public var track: Track { Track(id: id, name: name, artist: artist, duration: duration, album: album) }

    /// Apple Music adds " - Single" and " - EP" to the titles of those releases (Apple Music Style Guide).
    public var isSingleOrEP: Bool { album.hasSuffix(" - Single") || album.hasSuffix(" - EP") }

    /// The title or album says it's a remaster or an anniversary reissue, which usually is one.
    public var isRemaster: Bool { (name + " " + album).contains(remasterWords) }
}

/// How loosely two tracks may differ and still count as the same song. The defaults are the
/// strict rules: the same track, or the same title and first artist with nearly the same length.
public struct MatchOptions: Equatable, Sendable {
    /// Compare titles without tags that name a release rather than a recording,
    /// such as "(Remastered 2011)", " - Radio Edit", "(Deluxe Edition)" or "(feat. X)".
    public var ignoreVersionTags = false
    /// Ignore case, accents, "&" versus "and" and punctuation, in titles and artists.
    public var foldText = false
    /// Match when two copies share any credited artist, counting "(feat. X)" in the title,
    /// rather than only the same first artist.
    public var anyCreditedArtist = false
    /// Largest length difference, in seconds, between two copies of a song.
    public var tolerance: Double = 2

    public init(ignoreVersionTags: Bool = false, foldText: Bool = false, anyCreditedArtist: Bool = false, tolerance: Double = 2) {
        self.ignoreVersionTags = ignoreVersionTags
        self.foldText = foldText
        self.anyCreditedArtist = anyCreditedArtist
        self.tolerance = tolerance
    }
}

/// A later entry is a duplicate if it is the same track as an earlier one, or the same song:
/// the same title and first artist (case-insensitive), with a length within the tolerance.
/// Each duplicate records the earlier entry it repeats.
public func findDuplicates(in playlist: Playlist, options: MatchOptions = .init()) -> [Entry] {
    var firstByID: [Int: Int] = [:]  // database ID: position of its first entry
    var seen: [String: [(keyed: Keyed, index: Int)]] = [:]
    var dups: [Entry] = []
    for (i, t) in playlist.tracks.enumerated() {
        let k = Keyed(t, options)
        let match = firstByID[t.id].map { ($0, "same track") }
            ?? seen[k.bucket]?.first { $0.keyed.matches(k, options) }.map { ($0.index, "same name and artist") }
        if let match {
            dups.append(Entry(playlistID: playlist.id, playlistName: playlist.name, index: i, track: t,
                              reason: match.1, originalIndex: match.0, original: playlist.tracks[match.0]))
        } else {
            firstByID[t.id] = i
            seen[k.bucket, default: []].append((k, i))
        }
    }
    return dups
}

/// Songs that sit in more than one playlist (same matching rules), one group per song, with at
/// most one entry per playlist. Pass `duplicates`, findDuplicates' results for these playlists,
/// when they're already worked out; those entries are left out.
public func findCrossPlaylist(_ playlists: [Playlist], options: MatchOptions = .init(), duplicates: [Entry]? = nil) -> [[Entry]] {
    let dups = Dictionary(grouping: duplicates ?? playlists.flatMap { findDuplicates(in: $0, options: options) }, by: \.playlistID)
        .mapValues { Set($0.map(\.index)) }
    var groups: [String: [(first: Keyed, entries: [Entry])]] = [:]
    for p in playlists {
        let skip = dups[p.id] ?? []
        for (i, t) in p.tracks.enumerated() where !skip.contains(i) {
            let e = Entry(playlistID: p.id, playlistName: p.name, index: i, track: t)
            let k = Keyed(t, options)
            if let g = groups[k.bucket]?.firstIndex(where: { group in
                group.first.matches(k, options) && !group.entries.contains { $0.playlistID == p.id }
            }) {
                groups[k.bucket]![g].entries.append(e)
            } else {
                groups[k.bucket, default: []].append((k, [e]))
            }
        }
    }
    return groups.values.joined().map(\.entries)
        .filter { $0.count > 1 }
        .sorted { $0[0].track.name.localizedStandardCompare($1[0].track.name) == .orderedAscending }
}

/// Library songs that are the same song (same matching rules), one group per song, with the copy
/// to keep first: the one in the most playlists, then a remaster or anniversary edition over the
/// original, then an album's copy over a single's or EP's, then the most played, then the first in
/// the library. Quality and release date can't decide: Music reports the same bit rate for every
/// Apple Music copy, and reissues keep the original release date.
public func findLibraryDuplicates(_ songs: [LibrarySong], playlistCount: [Int: Int] = [:], options: MatchOptions = .init()) -> [[LibrarySong]] {
    typealias Copy = (keyed: Keyed, song: LibrarySong, order: Int)
    var groups: [String: [[Copy]]] = [:]
    // Shortest first, so copies a few seconds apart chain into one group instead of splitting.
    for (order, s) in songs.enumerated().sorted(by: { $0.element.duration < $1.element.duration }) {
        let k = Keyed(s.track, options)
        if let g = groups[k.bucket]?.firstIndex(where: { $0.contains { $0.keyed.matches(k, options) } }) {
            groups[k.bucket]![g].append((k, s, order))
        } else {
            groups[k.bucket, default: []].append([(k, s, order)])
        }
    }
    return groups.values.joined()
        .filter { $0.count > 1 }
        .map { copies in
            copies.map { c in ((-(playlistCount[c.song.id] ?? 0), c.song.isRemaster ? 0 : 1, c.song.isSingleOrEP ? 1 : 0, -c.song.playedCount, c.order), c.song) }
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
        .sorted { $0[0].name.localizedStandardCompare($1[0].name) == .orderedAscending }
}

/// What two tracks are compared on, worked out once per track. Callers only compare tracks in
/// the same bucket.
struct Keyed {
    let track: Track
    let bucket: String
    let artists: Set<String>  // only used with anyCreditedArtist

    init(_ t: Track, _ options: MatchOptions) {
        track = t
        bucket = options.anyCreditedArtist ? title(t, options) : matchKey(t, options: options)
        artists = options.anyCreditedArtist ? creditedArtists(t, options) : []
    }

    func matches(_ other: Keyed, _ options: MatchOptions) -> Bool {
        abs(track.duration - other.track.duration) < options.tolerance
            && (!options.anyCreditedArtist || !artists.isDisjoint(with: other.artists))
    }
}

/// Lowercased title + first credited artist.
func matchKey(_ t: Track, options: MatchOptions = .init()) -> String {
    let first = artistField(t, options).split(separator: firstArtistSeparator, maxSplits: 1).first ?? ""
    return title(t, options) + ":" + (options.foldText ? fold(String(first)) : first.trimmingCharacters(in: .whitespaces))
}

func title(_ t: Track, _ options: MatchOptions) -> String {
    var name = options.ignoreVersionTags ? stripVersionTags(t.name) : t.name
    // With anyCreditedArtist, "(feat. X)" counts as a credit rather than part of the title.
    if options.anyCreditedArtist { name = name.replacing(featuring, with: "") }
    return options.foldText ? fold(name) : name.lowercased().trimmingCharacters(in: .whitespaces)
}

/// Everyone credited: the artist field split at ",", "&", "feat.", "ft.", "featuring" and
/// "with", plus anyone in a "(feat. X)" part of the title.
func creditedArtists(_ t: Track, _ options: MatchOptions) -> Set<String> {
    let inTitle = t.name.matches(of: featuring).map { String($0.output.1) }
    let names = ([artistField(t, options)] + inTitle.map { $0.lowercased() }).flatMap { $0.split(separator: creditSeparator) }
    return Set(names.map { options.foldText ? fold(String($0)) : $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
}

/// The lowercased artist field. When folding text, "and" separates artists like "&" does, so
/// "Simon and Garfunkel" splits the same way as "Simon & Garfunkel".
private func artistField(_ t: Track, _ options: MatchOptions) -> String {
    options.foldText ? t.artist.lowercased().replacing(andWord, with: "&") : t.artist.lowercased()
}

/// Case, accents and width folded, "&" read as "and", and punctuation dropped, so
/// "Red-Nosed" matches "Red Nosed", "Don’t" matches "Don't" and "Beyoncé" matches "Beyonce".
func fold(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        .replacing("&", with: " and ")
        .replacing(punctuation, with: " ")
        .trimmingCharacters(in: .whitespaces)
}

/// Removes bracketed parts, then a last " - " part, that name a release rather than a recording.
/// A part that also says remix, live, acoustic, demo or instrumental stays: that's another recording.
func stripVersionTags(_ title: String) -> String {
    func isReleaseTag(_ part: Substring) -> Bool { part.contains(versionTag) && !part.contains(otherRecording) }
    return title
        .replacing(bracketPart) { isReleaseTag($0.output.1) ? "" : String($0.output.0) }
        .replacing(dashSuffix) { isReleaseTag($0.output.1) ? "" : String($0.output.0) }
}

// Built once: making a Regex compiles it, and matching runs these for every track of every scan.
// nonisolated(unsafe) because Regex isn't Sendable; matching only runs on one thread at a time
// (the main actor in the app, the test runner in tests).
nonisolated(unsafe) private let firstArtistSeparator = #/,|&|\bfeat\.?\s|\bft\.\s|\bfeaturing\s/#
nonisolated(unsafe) private let creditSeparator = #/,|&|\bfeat\.?\s|\bft\.\s|\bfeaturing\s|\bwith\s/#
nonisolated(unsafe) private let featuring = #/(?i)\s*[(\[](?:feat\.?|ft\.|featuring|with)\s+([^)\]]*)[)\]]/#
nonisolated(unsafe) private let andWord = #/(?i)\band\b/#
nonisolated(unsafe) private let punctuation = #/[^\p{L}\p{N}]+/#
nonisolated(unsafe) private let bracketPart = #/\s*[(\[]([^)\]]*)[)\]]/#
nonisolated(unsafe) private let dashSuffix = #/\s+[-–—]\s+([^-–—]*)$/#
nonisolated(unsafe) private let versionTag = #/(?i)\b(remaster(ed)?|radio edit|(single|album|lp) version|original mix|mono|stereo|explicit|clean|bonus track|(deluxe|anniversary|expanded)( edition)?)\b|^\W*(feat\.?|ft\.|featuring|with)\s/#
nonisolated(unsafe) private let otherRecording = #/(?i)\b(remix|live|acoustic|demo|instrumental)\b/#
nonisolated(unsafe) private let remasterWords = #/(?i)\bremaster(ed)?\b|\banniversary edition\b/#
