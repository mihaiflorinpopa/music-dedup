<p align="center">
  <img src="Resources/icon/readme-icon.png" alt="Music Dedup app icon" width="160">
</p>

<h1 align="center">Music Dedup</h1>

<p align="center">Find and remove duplicate songs in your playlists. For Apple Music on the Mac.</p>

Music Dedup scans the playlists you made in the Music app. It shows songs that are in a playlist twice, or in several playlists, and removes the copies you choose. It's [spotify-dedup](https://github.com/JMPerez/spotify-dedup) for Apple Music.

It's free, open source (MIT) and runs on macOS 14 or later. With Sync Library turned on, the cleanup also reaches your iPhone, iPad and other devices.

## Install

1. Download `MusicDedup-<version>.dmg` from [Releases](../../releases/latest).
2. Open it and drag Music Dedup into Applications.
3. Open Music Dedup. macOS will warn that it can't check the app, because Music Dedup isn't notarized by Apple. Go to **System Settings > Privacy & Security**, scroll down and click **Open Anyway**.
4. The first time you scan, macOS asks to let Music Dedup control Music. Click **Allow**.

You only need steps 3 and 4 once. After that, Music Dedup updates itself.

## Use it

Click **Scan**. Music Dedup reads your playlists and shows three tabs:

- **Within Playlists:** songs that are in the same playlist more than once. Removing takes out the later copies, and the first one stays. **Remove All** clears every playlist at once.
- **Across Playlists:** songs that are in more than one playlist. Check the playlists you don't want each song in. To check all of one playlist's songs, Control-click it and choose **Select All in “…”**.
- **Playlists:** turn off the playlists you don't want checked. You can also Control-click a playlist in the other tabs to skip it.

Check the entries you want gone in either tab, then click **Remove Selected** (⌘⌫). A playlist's checkbox checks all of its duplicates.

Nothing changes until you confirm. Removing takes the entry out of that playlist only. It doesn't delete the song from your library.

**Settings…** (⌘,):

- **Ignore Version Tags** treats "Song", "Song (Remastered 2011)", "Song - Radio Edit" and "Song (feat. Guest)" as one song. Remixes and live versions stay apart.
- **Length Difference** sets how much two copies of a song may differ in length. The default is 2 seconds.
- **Check for Updates Automatically.**

## What counts as a duplicate

The same rules as spotify-dedup:

- the same track, added more than once, or
- the same title and first artist (ignoring case), with lengths less than 2 seconds apart. This catches the single and the album copy of a song.

Only playlists you made are checked. Smart playlists, Genius playlists and folders are left out.

**Does it free disk space?** No. A playlist entry only points to a song, so removing one deletes no file, and two entries of the same song are one song. Apple Music songs you haven't downloaded take no space anyway. To save space, remove duplicate songs from your library in Music (**File > Library > Show Duplicate Items**) or remove downloads you don't need.

## If something goes wrong

- **"Not authorized to send Apple events to Music."** Turn on Music Dedup in **System Settings > Privacy & Security > Automation**.
- **"Playlist … changed since the scan."** The playlist changed in Music, or on another device, after you scanned. Nothing was removed. Scan again.
- **Removing from a playlist fails.** It may be a playlist you follow rather than one you made. Skip it in the Playlists tab.
- **To put a song back,** add it to the playlist again in Music.

## How it works

Apple's [Apple Music API](https://developer.apple.com/documentation/applemusicapi) can read playlists and add songs to them, but it can't remove songs ([Apple's answer on the developer forums](https://developer.apple.com/forums/thread/683035)). MusicKit can only edit playlists that its own app created. The Music app's scripting dictionary can remove them, so Music Dedup uses that. That's also why it's a Mac app.

Two small JavaScript for Automation scripts do the work: [`scan.js`](Resources/scan.js) reads your playlists, and [`remove.js`](Resources/remove.js) removes the entries you confirmed. Before removing anything, it checks that every entry is still where the scan found it.

Music Dedup does nothing in the background, and nothing leaves your Mac. It talks to Music only when you scan or remove, and checks for updates when it opens and once a day.

## For developers

```sh
./scripts/build-dmg.sh   # builds build/Music Dedup.app and the .dmg
swift test               # runs the tests
```

To release, change the version in [`VERSION`](VERSION) and merge to main. CI publishes the GitHub release with the .dmg and the update feed (`appcast.xml`). Updates are checked with [Sparkle](https://sparkle-project.org). The .dmg and the update feed are both signed with the key in the `SPARKLE_PRIVATE_KEY` repository secret, and the app accepts neither unless the signature matches. Its public half is [`Resources/sparkle-public-key.txt`](Resources/sparkle-public-key.txt). Without the secret, CI builds but doesn't release.

## Author

Made by Mihai Florin Popa ([@mihaiflorinpopa](https://github.com/mihaiflorinpopa)).

## Related projects

- [spotify-dedup](https://github.com/JMPerez/spotify-dedup) does the same for Spotify. Its matching rules are Music Dedup's defaults.
- The Music app can [find duplicate items in your library](https://support.apple.com/guide/music/mus4a9a2d6f1/mac): **File > Library > Show Duplicate Items**.
- [Dupin](https://dougscripts.com/dupin) finds duplicates across a whole library, with rules for which copy to keep.

Apple Music is a trademark of Apple Inc., registered in the U.S. and other countries and regions. Music Dedup is not made or endorsed by Apple.
