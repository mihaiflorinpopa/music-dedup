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
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw Failure(errorDescription: String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        return data
    }
}
