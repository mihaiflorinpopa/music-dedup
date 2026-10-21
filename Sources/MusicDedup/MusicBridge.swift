import Foundation
import MusicDedupCore

/// Talks to the Music app through its scripting dictionary, running the bundled
/// JavaScript for Automation scripts with /usr/bin/osascript.
enum MusicBridge {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static func scan() throws -> [Playlist] {
        try JSONDecoder().decode([Playlist].self, from: run("scan"))
    }

    /// Removes the given entries, all from one playlist. Fails without removing anything if the playlist changed since the scan.
    static func remove(_ entries: [Entry], from playlistID: String) throws {
        _ = try run("remove", [playlistID] + entries.map { "\($0.index):\($0.track.id)" })
    }

    /// The playlist that collects library duplicates for the user to delete in Music.
    static let duplicatesPlaylist = "Music Dedup: Duplicates"

    static func scanLibrary() throws -> [LibrarySong] {
        try JSONDecoder().decode([LibrarySong].self, from: run("library"))
    }

    /// Adds the given library songs to `duplicatesPlaylist` and returns how many were new there.
    static func collect(_ ids: [Int]) throws -> Int {
        let out = String(decoding: try run("collect", [duplicatesPlaylist] + ids.map(String.init)), as: UTF8.self)
        guard let added = Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw Failure(errorDescription: "collect.js printed \"\(out)\" instead of a count.")
        }
        return added
    }

    private static func run(_ script: String, _ args: [String] = []) throws -> Data {
        guard let path = Bundle.main.path(forResource: script, ofType: "js") else {
            throw Failure(errorDescription: "\(script).js is missing from the app bundle.")
        }
        let p = Process(), out = Pipe(), err = Pipe()
        p.executableURL = URL(filePath: "/usr/bin/osascript")
        p.arguments = ["-l", "JavaScript", path] + args
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        // shortcut: stderr is read after exit, so more than a pipe's 64 KB of it would block;
        // osascript writes one error line there. Read it concurrently if that ever changes.
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(errorDescription: message.isEmpty ? "osascript exited with status \(p.terminationStatus)." : message)
        }
        return data
    }
}
