<p align="center">
  <img src="Resources/icon/readme-icon.png" alt="Music Dedup app icon" width="160">
</p>

<h1 align="center">Music Dedup</h1>

<p align="center">Find and remove duplicate songs in your playlists. For Apple Music on the Mac.</p>

Music Dedup scans the playlists you made in the Music app, and your library. It shows songs that are in a playlist twice, in several playlists, or in your library more than once, and helps you clear out the copies you choose. It's [spotify-dedup](https://github.com/JMPerez/spotify-dedup) for Apple Music.

It's free, open source (MIT) and runs on macOS 14 or later. With Sync Library turned on, the cleanup also reaches your iPhone, iPad and other devices.

## Install

1. Download `MusicDedup-<version>.dmg` from [Releases](../../releases/latest).
2. Open it and drag Music Dedup into Applications.
3. Open Music Dedup. macOS will warn that it can't check the app, because Music Dedup isn't notarized by Apple. Go to **System Settings > Privacy & Security**, scroll down and click **Open Anyway**.
4. The first time you scan, macOS asks to let Music Dedup control Music. Click **Allow**. macOS may ask again after an update, because Music Dedup isn't signed with a Developer ID.

You only need steps 3 and 4 once. After that, Music Dedup updates itself.

## Use it

Click **Scan**. Music Dedup reads your playlists and your library, and shows five tabs:

- **Within Playlists:** songs that are in the same playlist more than once. Removing takes out the later copies, and the first one stays. **Remove All** clears every playlist at once.
- **Across Playlists:** songs that are in more than one playlist. Check the playlists you don't want each song in. To check all of one playlist's songs, Control-click it and choose **Select All in “…”**.
- **Unavailable:** songs in your playlists that Apple Music no longer has. They're grayed out in Music and can't play. Apple suggests [finding another version](https://support.apple.com/en-us/HT204406) and adding that instead.
- **Library:** songs that are in your library more than once, such as the same song on an album, a single and a compilation, and songs Apple Music no longer has, which Music grays out and can't play. The first copy of each song stays: the one in the most playlists, then a remaster or anniversary edition over the original, then the album's over a single's or EP's, then the most played. Quality and release date can't decide: Music reports the same quality for every Apple Music copy, and reissues keep the original release date. The other copies, and the songs Apple Music no longer has, start checked; **Check All** and **Uncheck All** change them all at once. **Add to “Music Dedup: Duplicates”** puts the checked ones in that playlist. Then, in Music, open the playlist, press ⌘A, Control-click and choose **Delete from Library**. Music Dedup never deletes library songs itself. By default, Music keeps deleted songs in your playlists; see Apple's [Delete items from Music on Mac](https://support.apple.com/guide/music/mus51db94bb1/mac).
- **Playlists:** turn off the playlists you don't want checked. You can also Control-click a playlist in the other tabs to skip it.

If two copies are matched but you want both, Control-click the duplicate and choose **Not a Duplicate**: that pair is never matched again, in any tab. **Settings > Matching** shows how many pairs you've kept apart and can forget them.

In the first three tabs, check the entries you want gone, then click **Remove Selected** (⌘⌫). A playlist's checkbox checks all of its duplicates.

Nothing changes until you confirm. Removing takes the entry out of that playlist only. It doesn't delete the song from your library.

Before any change, Music Dedup saves what it's about to remove, or add to the duplicates playlist, in a removal log. **File > Show Removal Log** shows it in Finder: a CSV file that Numbers or Excel opens, with each entry's playlist, position, title, artist and album. It's written before the change, so it can also list an entry that a failed removal left in place.

**Settings…** (⌘,):

- **Ignore Version Tags** treats "Song", "Song (Remastered 2011)", "Song - Radio Edit", "Song (Deluxe Edition)" and "Song (feat. Guest)" as one song. Remixes and live versions stay apart.
- **Ignore Accents and Punctuation** treats "Red-Nosed" and "Red Nosed", "Beyoncé" and "Beyonce", and "&" and "and" as the same.
- **Match Any Credited Artist** treats "Song (feat. Guest)" by Main and "Song" by Guest & Main as one song. Otherwise only the first artist counts.
- **Same Album Only** counts copies as one song only when they're also on the same album, like Music's **Show Exact Duplicate Items**. Copies on a single, a compilation or a reissue stay apart.
- **Length Difference** sets how much two copies of a song may differ in length. The default is 2 seconds.
- **Check for Updates Automatically.**

## What counts as a duplicate

The same rules as spotify-dedup:

- the same track, added more than once, or
- the same title and first artist (ignoring case), with lengths less than 2 seconds apart. This catches the single and the album copy of a song.

Only playlists you made are checked, and your library. Smart playlists, Genius playlists and folders are left out. The options above change these rules; all are off by default.

**Does it free disk space?** No. A playlist entry only points to a song, so removing one deletes no file, and two entries of the same song are one song. Apple Music songs you haven't downloaded take no space anyway. To save space, delete duplicate songs from your library with the **Library** tab, or remove downloads you don't need.

## If something goes wrong

- **"Music Dedup isn't allowed to control Music."** Turn on Music Dedup in **System Settings > Privacy & Security > Automation**, then scan again.
- **"Playlist … changed since the scan."** The playlist changed in Music, or on another device, after you scanned. Nothing was removed. Scan again.
- **Removing from a playlist fails.** It may be a playlist you follow rather than one you made. Skip it in the Playlists tab.
- **To put a song back,** find it in the removal log (**File > Show Removal Log**) and add it to that playlist again in Music.

## How it works

Apple's [Apple Music API](https://developer.apple.com/documentation/applemusicapi) can read playlists and add songs to them, but it can't remove songs ([Apple's answer on the developer forums](https://developer.apple.com/forums/thread/683035)). MusicKit can only edit playlists that its own app created. The Music app's scripting dictionary can remove them, so Music Dedup uses that. That's also why it's a Mac app.

Small JavaScript for Automation scripts do the work: [`scan.js`](Resources/scan.js) reads your playlists, [`library.js`](Resources/library.js) reads your library, [`remove.js`](Resources/remove.js) removes the playlist entries you confirmed, and [`collect.js`](Resources/collect.js) adds library copies to the duplicates playlist. Before removing anything, `remove.js` checks that every entry is still where the scan found it.

Music Dedup does nothing in the background, and nothing leaves your Mac. It talks to Music only when you scan, remove or add to the duplicates playlist, and checks for updates when it opens and once a day.

## For developers

```sh
./scripts/build-dmg.sh   # builds build/Music Dedup.app and the .dmg
swift test               # runs the tests
```

To release, change the version in [`VERSION`](VERSION) and merge to main. CI publishes the GitHub release with the .dmg and the update feed (`appcast.xml`). Updates are checked with [Sparkle](https://sparkle-project.org). The .dmg and the update feed are both signed with the key in the `SPARKLE_PRIVATE_KEY` secret of the `release` environment, which only `main` can use, and the app accepts neither unless the signature matches. Its public half is [`Resources/sparkle-public-key.txt`](Resources/sparkle-public-key.txt). Without the secret, the release fails instead of publishing an update that couldn't be verified.

## Author

Made by Mihai Florin Popa ([@mihaiflorinpopa](https://github.com/mihaiflorinpopa)).

## Related projects

- [spotify-dedup](https://github.com/JMPerez/spotify-dedup) does the same for Spotify. Its matching rules are Music Dedup's defaults.
- The Music app can [find duplicate items in your library](https://support.apple.com/guide/music/mus4a9a2d6f1/mac): **File > Library > Show Duplicate Items**.
- [Dupin](https://dougscripts.com/dupin) finds duplicates across a whole library, with rules for which copy to keep.

Apple Music is a trademark of Apple Inc., registered in the U.S. and other countries and regions. Music Dedup is not made or endorsed by Apple.
