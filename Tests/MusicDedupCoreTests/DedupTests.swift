import XCTest
@testable import MusicDedupCore

final class DedupTests: XCTestCase {
    func t(_ id: Int, _ name: String, _ artist: String, _ duration: Double) -> Track {
        Track(id: id, name: name, artist: artist, duration: duration)
    }

    lazy var a = Playlist(id: "A", name: "A", tracks: [
        t(1, "Song", "Artist", 200),
        t(1, "Song", "Artist", 200),                // same track twice
        t(2, "SONG", "Artist feat. Other", 201.5),  // same name and first artist, within 2 s
        t(3, "Song", "Artist", 230),                // e.g. a live version: kept
        t(4, "Other", "Artist", 200),
    ])

    func testSpotifyDedupRules() {
        let dups = findDuplicates(in: a)
        XCTAssertEqual(dups.map(\.index), [1, 2])
        XCTAssertEqual(dups.map(\.reason), ["same track", "same name and artist"])
    }

    func testCrossPlaylistGroupsOneSongAcrossPlaylists() {
        let b = Playlist(id: "B", name: "B", tracks: [t(5, "song", "Artist & Friend", 199), t(6, "Unique", "X", 100)])
        let cross = findCrossPlaylist([a, b])
        XCTAssertEqual(cross.count, 1)
        XCTAssertEqual(cross[0].map(\.playlistID), ["A", "B"])
        XCTAssertEqual(cross[0].map(\.index), [0, 0])
    }

    func testFirstArtist() {
        XCTAssertEqual(matchKey(t(0, "X", "Feather & Co", 1)), "x:feather")
        XCTAssertEqual(matchKey(t(0, "X", "A, B ft. C", 1)), "x:a")
    }

    func testToleranceSetting() {
        let p = Playlist(id: "P", name: "P", tracks: [t(1, "Song", "Artist", 200), t(2, "Song", "Artist", 204)])
        XCTAssertTrue(findDuplicates(in: p).isEmpty)
        XCTAssertEqual(findDuplicates(in: p, options: .init(tolerance: 5)).map(\.index), [1])
    }

    func testVersionTagsAreIgnoredOnlyWhenAsked() {
        let p = Playlist(id: "P", name: "P", tracks: [
            t(1, "Song", "Artist", 200),
            t(2, "Song (Remastered 2011)", "Artist", 200),
            t(3, "Song - Radio Edit", "Artist", 201),
            t(4, "Song (feat. Guest)", "Artist", 200.5),
        ])
        XCTAssertTrue(findDuplicates(in: p).isEmpty)
        XCTAssertEqual(findDuplicates(in: p, options: .init(ignoreVersionTags: true)).map(\.index), [1, 2, 3])
    }

    func testStripVersionTagsKeepsOtherRecordings() {
        XCTAssertEqual(stripVersionTags("Song [2009 Remaster]"), "Song")
        XCTAssertEqual(stripVersionTags("Song – 2011 Remastered Version"), "Song")
        XCTAssertEqual(stripVersionTags("Song (with Guest)"), "Song")
        XCTAssertEqual(stripVersionTags("Song (Live at Wembley)"), "Song (Live at Wembley)")
        XCTAssertEqual(stripVersionTags("Song (Logistics Remix)"), "Song (Logistics Remix)")
        XCTAssertEqual(stripVersionTags("Part 1 - The Beginning"), "Part 1 - The Beginning")
        XCTAssertEqual(stripVersionTags("Without Me"), "Without Me")
    }
}
