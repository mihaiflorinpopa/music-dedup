// Usage: remove.js <playlist persistent ID> <index>:<database ID> ...
// Removes those entries from the playlist only. It deletes no songs from the library.
function run(argv) {
  const music = Application('Music')
  const pl = music.userPlaylists.whose({ persistentID: argv[0] })[0]
  const want = argv.slice(1).map(s => s.split(':').map(Number)).sort((a, b) => b[0] - a[0])
  const ids = pl.tracks.databaseID()
  // Check every position first so a changed playlist aborts before anything is removed.
  if (want.some(([i, id]) => ids[i] !== id)) throw new Error(`Playlist "${pl.name()}" changed since the scan. Scan again.`)
  want.forEach(([i]) => music.delete(pl.tracks[i])) // highest index first, so lower indices stay valid
}
