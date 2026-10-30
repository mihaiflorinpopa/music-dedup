# Music Dedup: notes for coding agents

Music Dedup is a macOS app that finds duplicate songs inside and across the user's playlists in the Music app, and removes the playlist entries the user confirms. The README describes what it does.

## Build and test

- `swift test` runs the MusicDedupCore tests.
- `./scripts/build-app.sh` builds `build/Music Dedup.app` (universal, ad-hoc signed). `./scripts/build-dmg.sh` also makes the .dmg, with `diskutil image` (macOS 27 deprecates `hdiutil`).
- `osascript -l JavaScript Resources/scan.js` and `Resources/library.js` print, as JSON, what the app reads from Music. They change nothing.
- Never test `remove.js` on the user's real playlists. Make a throwaway playlist with one track added twice, remove from it, check the library still has the track, then delete the playlist. Test `collect.js` with a throwaway playlist name, never "Music Dedup: Duplicates", and delete that playlist afterwards.
- zsh doesn't split unquoted variables into words, so `$IDS` reaches a script as one argument. Pass database IDs as separate arguments (or `${=IDS}`).
- Swift Build (the default build system from Swift 6.4, Xcode 27) records the deployment target as the SDK version, and macOS then draws the app like macOS 14 (the window title shows, with the tabs in a bar below it). `build-app.sh` checks the SDK the binary records and, only if it's wrong, relinks with `-platform_version` (Swift 6.3, Xcode 26, records it right and hands linker flags to clang, which rejects that one); it fails if the binary still records another SDK, and CI checks it too. Xcode 27 also warns that x86_64 is deprecated.

## Layout

- `Sources/MusicDedupCore`: matching (`Dedup.swift`): spotify-dedup's rules, `MatchOptions` (version tags, folded text, any credited artist, same album, tolerance, and the `TrackPair`s marked Not a Duplicate), `findLibraryDuplicates` with the keeper order, and `findUnavailable` (cloud status "no longer available"; `LibrarySong.isUnavailable` is the same for the Library tab). `CSV.swift` writes the removal log's lines. Tests are in `Tests/MusicDedupCoreTests`.
- `Sources/MusicDedup`: the app. `Model` (`@Observable`, settings in UserDefaults), `ContentView` (Within, Across, Unavailable, Library and Playlists tabs), `SettingsView` (the SwiftUI `Settings` scene), `MusicBridge` (runs the scripts with `/usr/bin/osascript`, waiting on a Dispatch queue: Swift concurrency's threads must not block), `RemovalLog` (the CSV of changes, File > Show Removal Log), `Updater` (Sparkle).
- `Resources/`: Info.plist, `Credits.rtf` (the About panel's credits, with Sparkle's credit and Apple's trademark notice), `scan.js`, `remove.js`, `library.js` and `collect.js` (JavaScript for Automation, copied into the app's Resources), icon (`icon.svg` rendered to `icon-1024.png` for macOS 14 and 15, Icon Composer `MusicDedup.icon` for macOS 26 and later).

## Rules

- Follow the upstream documentation of every component, for the version the project uses: Apple's (SwiftUI, Observation, the Music app's scripting dictionary from `sdef /System/Applications/Music.app`, the JavaScript for Automation release notes, the HIG), Sparkle's, SwiftPM's and GitHub Actions'. Read it before changing how a component is used, quote it in the pull request, and say plainly when something is a workaround the docs don't describe. Apple's pages are rendered with JavaScript, so fetch their JSON: `https://developer.apple.com/tutorials/data/documentation/<path>.json`, and `…/tutorials/data/design/human-interface-guidelines/<page>.json` for the HIG. The SDK headers (`xcrun --show-sdk-path`) settle availability and deprecation.
- Only remove playlist entries (`delete` on a track of a `user playlist`), never library tracks. The user confirms every removal, and `remove.js` checks every position against the scan before it removes anything, and removes each position once. An `Entry` is its playlist, position and track, so one entry shown in two tabs is one selection. Library duplicates, and library songs Apple Music no longer has, are only added to the "Music Dedup: Duplicates" playlist (`collect.js`); the user deletes them from the library in Music.
- Read Music in bulk: one Apple event per property for a whole playlist (`tracks.name()`), never one per track. A bulk get fails with "Can't get object" on an empty playlist, so check `tracks.length` first.
- The matching defaults stay spotify-dedup's: the same database ID, or the same lowercased name and first artist with lengths less than 2 seconds apart. New rules are options, off by default.
- Log every change before making it: `RemovalLog` appends to `~/Library/Application Support/io.github.mihaiflorinpopa.music-dedup/Removal Log.csv` before `remove.js` or `collect.js` runs, and nothing changes if the log can't be written.
- No background work: Music is read only on Scan (playlists and library at once) and after a removal (playlists only: removing entries doesn't change library songs), and written only on a confirmed removal or an add to the duplicates playlist.
- Matching runs on one thread at a time, in the `Matcher` actor (in `Model.swift`), off the main actor: `Dedup.swift` compiles its regexes once into `nonisolated(unsafe)` globals, since building a `Regex` per call made a settings change take seconds, and with every option on a large library still takes about half a second, more than Apple's 250 ms hang threshold. Never call the matching functions from anywhere else in the app.
- Swift 6 language mode. A `Model` property stored in UserDefaults must call `access(keyPath:)` and `withMutation(keyPath:)`, or its UI goes stale.
- Keep the app lightweight, the design minimal and the README easy to read.
- Sign from the inside out. Never use `codesign --deep`.
- Third-party code shipped in the app keeps its license notice in the app: `build-app.sh` copies Sparkle's `LICENSE` to `Contents/Resources/Sparkle LICENSE.txt`, and CI checks it.
- Never weaken or delete tests or assertions to make a check pass.
- Feature work goes through a pull request, and CI must pass before merging.
- Commits and pull requests carry no AI-tool attribution: no Co-Authored-By trailers, no "Generated with" lines.

## Releases

- Bump `VERSION` and merge to main. The `build` job builds, tests and checks the app; when `VERSION` has no tag yet on a main push, the `release` job signs the .dmg and `appcast.xml` (Sparkle EdDSA, the `SPARKLE_PRIVATE_KEY` secret) and publishes the GitHub release. Merges that don't change `VERSION` don't release.
- The workflow's token is read-only; only the `release` job gets `contents: write`. It runs in the `release` environment, which only protected branches (main) can use, and the Sparkle key belongs in that environment's secrets. Without the key, the release job fails rather than publish a release that could never update itself.
- main is protected: pull requests merge only after the `build` and `CodeQL` checks pass. CodeQL is GitHub's default setup (repository settings, no workflow file) for Actions, JavaScript and Swift, as in unplug.
- Release notes, on GitHub and in the app's update dialog, are generated from pull request titles, so write titles for users: what changes for them, in plain words ("Settings changes no longer freeze the window", not "Match off the main thread"). The details go in the PR body. The update dialog drops each line's author and link. `.github/release.yml` leaves out PRs labelled `skip-release-notes`: label CI, build-script, docs-only and version-bump PRs with it (`gh pr create --label skip-release-notes`). Dependabot labels its own.
- The build number is the commit count.
- CI runs on a pinned `xcode-27` runner (macOS 27; GitHub names newer macOS images by Xcode version). Bump it by hand to the next Xcode image. Actions are pinned to commit SHAs, and Dependabot updates them and Sparkle.

## Already decided

Ask the maintainer before revisiting these.

- The Music app's scripting dictionary, not the Apple Music API or MusicKit. The API has no way to remove playlist entries (Apple staff on the developer forums), and MusicKit's `MusicLibrary.edit` only changes playlists its own app created. So the app is macOS only, and Sync Library carries changes to other devices.
- The app never deletes library songs. It collects the extra copies in "Music Dedup: Duplicates" for the user to delete in Music, as Dupin does with cloud songs. Apple's guide says deleting a library song doesn't delete it from playlists unless Music's "Add & Delete Playlist Songs" setting is on. The copy kept is the one in the most playlists, then one whose title or album says Remaster(ed) or Anniversary Edition, then an album's over a " - Single" or " - EP" (suffixes Apple adds, per the Apple Music Style Guide), then the most played. Not quality or release date: every Apple Music copy reports 256 kbps AAC or no bit rate, and reissues keep the original release date.
- The Music app's scripting dictionary has no ISRC or catalog ID, so matching across releases relies on title, artist and length.
- macOS 14 minimum, so tabs use `.tabItem` (soft-deprecated in the macOS 27 SDK) rather than `Tab` (macOS 15).
- Playlist skipping is a tab in the main window, not in Settings: the HIG keeps filters in the view they affect.
- The name is "Music Dedup" and the repository `music-dedup`. Apple's trademark guidelines don't allow "Apple Music" in a product name, so it's used only descriptively ("for Apple Music"), with Apple's trademark notice.
- No privacy manifest: Apple requires required-reason declarations only on iOS, iPadOS, tvOS, visionOS and watchOS.
- Developer ID signing, notarization and Homebrew wait for the maintainer.
- English only.

## Not verified

macOS 14, 15 and 26, Intel Macs, libraries without Sync Library, and removing from playlists the user follows rather than made. Removal was tested on macOS 27.2 with a throwaway playlist: only the chosen entry went, and the song stayed in the library.
