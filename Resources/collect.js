// Usage: collect.js <playlist name> <database ID> ...
// Adds those library songs to the playlist, making it first if needed, so the user can delete
// them from the library in Music. Changes nothing in the library itself. Prints how many it added.
function run([name, ...ids]) {
  const music = Application('Music'), library = music.libraryPlaylists[0]
  const found = music.userPlaylists.whose({ name })
  const playlist = found.length ? found[0] : music.UserPlaylist({ name }).make()
  // A bulk get fails with "Can't get object" on an empty playlist, so check its length first.
  const have = new Set(playlist.tracks.length ? playlist.tracks.databaseID() : [])
  const songs = ids.map(Number).filter(id => !have.has(id)).map(id => {
    const matches = library.tracks.whose({ databaseID: id })
    if (matches.length !== 1) throw new Error('A song changed in Music since the scan. Scan again.')
    return matches[0]
  })
  // Every song is found before any is added, so a changed library adds nothing.
  songs.forEach(song => music.duplicate(song, { to: playlist }))
  return String(songs.length)
}
