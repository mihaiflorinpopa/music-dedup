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

    public var track: Track { Track(id: id, name: name, artist: artist, duration: duration) }

    /// Apple Music adds " - Single" and " - EP" to the titles of those releases (Apple Music Style Guide).
    public var isSingleOrEP: Bool { album.hasSuffix(" - Single") || album.hasSuffix(" - EP") }

    /// The title or album says it's a remaster or an anniversary reissue, which usually is one.
    public var isRemaster: Bool { (name + " " + album).contains(#/(?i)\bremaster(ed)?\b|\banniversary edition\b/#) }
}

/// How loosely two tracks may differ and still count as the same song.
/// The defaults are spotify-dedup's rules.
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

/// spotify-dedup's rules: a later entry is a duplicate if it is the same track, or has
/// the same name and first artist (case-insensitive) and a length within the tolerance.
public func findDuplicates(in playlist: Playlist, options: MatchOptions = .init()) -> [Entry] {
    var seenIDs = Set<Int>()
    var seen: [String: [Keyed]] = [:]
    var dups: [Entry] = []
    for (i, t) in playlist.tracks.enumerated() {
        let k = Keyed(t, options)
        let reason = seenIDs.contains(t.id) ? "same track"
            : seen[k.bucket, default: []].contains { $0.matches(k, options) } ? "same name and artist"
            : nil
        if let reason {
            dups.append(Entry(playlistID: playlist.id, playlistName: playlist.name, index: i, track: t, reason: reason))
        } else {
            seenIDs.insert(t.id)
            seen[k.bucket, default: []].append(k)
        }
    }
    return dups
}

/// Songs that sit in more than one playlist (same matching rules), one group per song.
public func findCrossPlaylist(_ playlists: [Playlist], options: MatchOptions = .init()) -> [[Entry]] {
    var groups: [String: [(first: Keyed, entries: [Entry])]] = [:]
    for p in playlists {
        let dups = Set(findDuplicates(in: p, options: options).map(\.index))
        for (i, t) in p.tracks.enumerated() where !dups.contains(i) {
            let e = Entry(playlistID: p.id, playlistName: p.name, index: i, track: t)
            let k = Keyed(t, options)
            if let g = groups[k.bucket]?.firstIndex(where: { $0.first.matches(k, options) }) {
                groups[k.bucket]![g].entries.append(e)
            } else {
                groups[k.bucket, default: []].append((k, [e]))
            }
        }
    }
    return groups.values.joined().map(\.entries)
        .filter { Set($0.map(\.playlistID)).count > 1 }
        .sorted { $0[0].track.name.localizedStandardCompare($1[0].track.name) == .orderedAscending }
}

/// Library songs that are the same song (same matching rules), one group per song, with the copy
/// to keep first: the one in the most playlists, then a remaster or anniversary edition over the
/// original, then an album's copy over a single's or EP's, then the most played, then the first in
/// the library. Quality and release date can't decide: Music reports the same bit rate for every
/// Apple Music copy, and reissues keep the original release date.
public func findLibraryDuplicates(_ songs: [LibrarySong], playlistCount: [Int: Int] = [:], options: MatchOptions = .init()) -> [[LibrarySong]] {
    var groups: [String: [(first: Keyed, songs: [LibrarySong])]] = [:]
    for s in songs {
        let k = Keyed(s.track, options)
        if let g = groups[k.bucket]?.firstIndex(where: { $0.first.matches(k, options) }) {
            groups[k.bucket]![g].songs.append(s)
        } else {
            groups[k.bucket, default: []].append((k, [s]))
        }
    }
    func rank(_ s: LibrarySong, _ order: Int) -> (Int, Int, Int, Int, Int) {
        (-(playlistCount[s.id] ?? 0), s.isRemaster ? 0 : 1, s.isSingleOrEP ? 1 : 0, -s.playedCount, order)
    }
    return groups.values.joined().map(\.songs)
        .filter { $0.count > 1 }
        .map { g in g.enumerated().sorted { rank($0.element, $0.offset) < rank($1.element, $1.offset) }.map(\.element) }
        .sorted { $0[0].name.localizedStandardCompare($1[0].name) == .orderedAscending }
}

/// What two tracks are compared on, worked out once per track. Only tracks in the same
/// bucket can match.
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
        bucket == other.bucket && abs(track.duration - other.track.duration) < options.tolerance
            && (!options.anyCreditedArtist || !artists.isDisjoint(with: other.artists))
    }
}

/// Lowercased name + first credited artist, like spotify-dedup's `name:artists[0]`.
func matchKey(_ t: Track, options: MatchOptions = .init()) -> String {
    let first = t.artist.lowercased()
        .split(separator: #/,|&|\bfeat\.?\s|\bft\.\s|\bfeaturing\s/#, maxSplits: 1).first ?? ""
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
    let names = ([t.artist] + inTitle).flatMap {
        $0.lowercased().split(separator: #/,|&|\bfeat\.?\s|\bft\.\s|\bfeaturing\s|\bwith\s/#)
    }
    return Set(names.map { options.foldText ? fold(String($0)) : $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
}

/// A "(feat. X)" part of a title. Computed: Regex isn't Sendable, so it can't be a global constant.
private var featuring: Regex<(Substring, Substring)> { #/(?i)\s*[(\[](?:feat\.?|ft\.|featuring|with)\s+([^)\]]*)[)\]]/# }

/// Case, accents and width folded, "&" read as "and", and punctuation dropped, so
/// "Red-Nosed" matches "Red Nosed", "Don’t" matches "Don't" and "Beyoncé" matches "Beyonce".
func fold(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        .replacing("&", with: " and ")
        .replacing(#/[^\p{L}\p{N}]+/#, with: " ")
        .trimmingCharacters(in: .whitespaces)
}

/// Removes bracketed parts and " - " suffixes that name a release, not a recording.
/// Remixes, live and acoustic versions are kept: they are different recordings.
func stripVersionTags(_ title: String) -> String {
    let tag = #/(?i)\b(remaster(ed)?|radio edit|(single|album|lp) version|original mix|mono|stereo|explicit|clean|bonus track|(deluxe|anniversary|expanded)( edition)?)\b|^\W*(feat\.?|ft\.|featuring|with)\s/#
    return title.replacing(#/\s*[(\[]([^)\]]*)[)\]]|\s+[-–—]\s+(.*)$/#) { match in
        let inner = match.output.1 ?? match.output.2 ?? ""
        return inner.contains(tag) ? "" : String(match.output.0)
    }
}
