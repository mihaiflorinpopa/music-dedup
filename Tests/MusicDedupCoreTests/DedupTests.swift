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

    func testMoreEditionTags() {
        XCTAssertEqual(stripVersionTags("Song (Deluxe Edition)"), "Song")
        XCTAssertEqual(stripVersionTags("Song [10th Anniversary Edition]"), "Song")
        XCTAssertEqual(stripVersionTags("Song (Expanded Edition)"), "Song")
        XCTAssertEqual(stripVersionTags("Song - LP Version"), "Song")
        XCTAssertEqual(stripVersionTags("Song (2011 Stereo Mix)"), "Song")
        XCTAssertEqual(stripVersionTags("Song (Extended Mix)"), "Song (Extended Mix)")
    }

    func testFoldTextOnlyWhenAsked() {
        let p = Playlist(id: "P", name: "P", tracks: [
            t(1, "Rudolph the Red-Nosed Reindeer", "Burl Ives", 130),
            t(2, "Rudolph the Red Nosed Reindeer", "Burl Ives", 130.4),
            t(3, "Don’t Stop", "Beyoncé", 200),
            t(4, "Don't Stop", "Beyonce", 200),
            t(5, "Rock & Roll", "Band", 100),
            t(6, "Rock and Roll", "Band", 100),
        ])
        XCTAssertTrue(findDuplicates(in: p).isEmpty)
        XCTAssertEqual(findDuplicates(in: p, options: .init(foldText: true)).map(\.index), [1, 3, 5])
    }

    func testAnyCreditedArtistOnlyWhenAsked() {
        let p = Playlist(id: "P", name: "P", tracks: [
            t(1, "Song (feat. Guest)", "Main", 200),
            t(2, "Song", "Guest & Main", 200),
            t(3, "Song", "Someone Else", 200),
        ])
        XCTAssertTrue(findDuplicates(in: p).isEmpty)
        XCTAssertEqual(findDuplicates(in: p, options: .init(anyCreditedArtist: true)).map(\.index), [1])
    }

    func testLibraryKeepsTheCopyInPlaylistsThenTheAlbumThenTheMostPlayed() {
        func s(_ id: Int, _ album: String, plays: Int) -> LibrarySong {
            LibrarySong(id: id, name: "Song", artist: "Artist", duration: 200, album: album, playedCount: plays)
        }
        let songs = [s(1, "Song - Single", plays: 50), s(2, "Album", plays: 1), s(3, "Best Of", plays: 0), s(4, "Other", plays: 9)]
        XCTAssertEqual(findLibraryDuplicates(songs, playlistCount: [3: 1]).map { $0.map(\.id) }, [[3, 4, 2, 1]])
        XCTAssertEqual(findLibraryDuplicates(songs).map { $0.map(\.id) }, [[4, 2, 3, 1]])
        XCTAssertTrue(findLibraryDuplicates([s(1, "A", plays: 0), LibrarySong(id: 2, name: "Other", artist: "Artist", duration: 200, album: "A", playedCount: 0)]).isEmpty)
    }

    func testLibraryPrefersRemastersRightAfterPlaylists() {
        func s(_ id: Int, _ name: String, _ album: String, plays: Int = 0) -> LibrarySong {
            LibrarySong(id: id, name: name, artist: "Artist", duration: 200, album: album, playedCount: plays)
        }
        let songs = [
            s(1, "Song", "Album", plays: 9),
            s(2, "Song", "Album (20th Anniversary Edition)"),
            s(3, "Song", "Album (Remastered) - Single"),
        ]
        XCTAssertEqual(findLibraryDuplicates(songs).map { $0.map(\.id) }, [[2, 3, 1]])
        XCTAssertEqual(findLibraryDuplicates(songs, playlistCount: [1: 1]).map { $0.map(\.id) }, [[1, 2, 3]])
        // A remaster named in the title counts too, once Ignore Version Tags groups it with the original.
        let titled = [s(1, "Song", "Album", plays: 9), s(2, "Song (2011 Remaster)", "Album")]
        XCTAssertEqual(findLibraryDuplicates(titled, options: .init(ignoreVersionTags: true)).map { $0.map(\.id) }, [[2, 1]])
        XCTAssertFalse(s(1, "Song", "Remastering the Classics Live").isRemaster)
    }
}
