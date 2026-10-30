import Foundation
import MusicDedupCore

/// Talks to the Music app through its scripting dictionary, running the bundled
/// JavaScript for Automation scripts with /usr/bin/osascript.
enum MusicBridge {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static func scan() async throws -> [Playlist] {
        try JSONDecoder().decode([Playlist].self, from: await run("scan"))
    }

    /// Removes the given entries, all from one playlist. Fails without removing anything if the playlist changed since the scan.
    static func remove(_ entries: [Entry], from playlistID: String) async throws {
        _ = try await run("remove", [playlistID] + entries.map { "\($0.index):\($0.track.id)" })
    }

    /// The playlist that collects library duplicates for the user to delete in Music.
    static let duplicatesPlaylist = "Music Dedup: Duplicates"

    static func scanLibrary() async throws -> [LibrarySong] {
        try JSONDecoder().decode([LibrarySong].self, from: await run("library"))
    }

    /// Adds the given library songs to `duplicatesPlaylist` and returns how many were new there.
    static func collect(_ ids: [Int]) async throws -> Int {
        let out = String(decoding: try await run("collect", [duplicatesPlaylist] + ids.map(String.init)), as: UTF8.self)
        guard let added = Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw Failure(errorDescription: "collect.js printed \"\(out)\" instead of a count.")
        }
        return added
    }

    /// Waits for the script on a Dispatch queue: reading its output blocks a thread until it exits, and
    /// Swift concurrency's own threads must not block (WWDC21, "Swift concurrency: Behind the scenes").
    private static func run(_ script: String, _ args: [String] = []) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try runBlocking(script, args) })
            }
        }
    }

    private static func runBlocking(_ script: String, _ args: [String]) throws -> Data {
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
            // errAEEventNotPermitted (-1743, AppleEvents.h): the user turned off our access to Music.
            if message.contains("-1743") {
                throw Failure(errorDescription: "Music Dedup isn't allowed to control Music. Turn it on in System Settings > Privacy & Security > Automation, then scan again.")
            }
            throw Failure(errorDescription: message.isEmpty ? "osascript exited with status \(p.terminationStatus)." : message)
        }
        return data
    }
}
