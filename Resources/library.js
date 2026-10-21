// Prints the library's songs as JSON, with what decides which copy to keep. Changes nothing.
// Each property is fetched for all songs at once: one Apple event per property, not per song.
function run() {
  const T = Application('Music').libraryPlaylists[0].tracks
  const kind = T.mediaKind(), id = T.databaseID(), name = T.name(), artist = T.artist()
  const duration = T.duration(), album = T.album(), plays = T.playedCount()
  const out = []
  kind.forEach((k, i) => {
    if (k !== 'song') return
    out.push({ id: id[i], name: name[i] || '', artist: artist[i] || '', duration: duration[i] || 0, album: album[i] || '', playedCount: plays[i] || 0 })
  })
  return JSON.stringify(out)
}
