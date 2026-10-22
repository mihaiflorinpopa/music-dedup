import Foundation
import MusicDedupCore

/// A CSV file listing every change the app makes in Music, written before the change, so a
/// removed entry or a library song deleted later can be found and added back.
enum RemovalLog {
    // Apple's File System Programming Guide: app-created data files go in Application Support,
    // in a subdirectory named with the app's bundle identifier.
    static let url = URL.applicationSupportDirectory.appending(path: "io.github.mihaiflorinpopa.music-dedup/Removal Log.csv")

    // path() percent-encodes ("Application%20Support"), which no file is called.
    static var exists: Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    static func removing(_ entries: [Entry]) throws {
        try append(entries.map { ["Removed from playlist", $0.playlistName, String($0.index + 1)] + fields($0.track) })
    }

    static func collecting(_ songs: [LibrarySong]) throws {
        try append(songs.map { ["Added to playlist", MusicBridge.duplicatesPlaylist, ""] + fields($0.track) })
    }

    private static func fields(_ t: Track) -> [String] {
        [t.name, t.artist, t.album, minutesAndSeconds(t.duration), String(t.id)]
    }

    private static func append(_ rows: [[String]]) throws {
        if !exists {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(csvLine(["Date", "Change", "Playlist", "Position", "Title", "Artist", "Album", "Length", "Database ID"]).utf8).write(to: url, options: .withoutOverwriting)  // never wipes a log
        }
        let date = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current))
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.seekToEnd()
        try file.write(contentsOf: Data(rows.map { csvLine([date] + $0) }.joined().utf8))
    }
}
