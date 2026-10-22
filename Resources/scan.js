// Prints the user's own playlists (no smart, Genius, folder or special ones) as JSON.
// Each property is fetched for all items at once: one Apple event per property, not per track.
function run() {
  const P = Application('Music').userPlaylists
  const ids = P.persistentID(), names = P.name(), smart = P.smart(), genius = P.genius(), kinds = P.specialKind()
  const out = []
  ids.forEach((id, i) => {
    if (smart[i] || genius[i] || kinds[i] !== 'none') return
    const T = P[i].tracks
    // A bulk get fails with "Can't get object" on an empty playlist, so check its length first.
    if (T.length === 0) return out.push({ id, name: names[i], tracks: [] })
    const tid = T.databaseID(), tn = T.name(), ta = T.artist(), td = T.duration(), tl = T.album(), tc = T.cloudStatus()
    out.push({
      id, name: names[i],
      tracks: tid.map((x, j) => ({ id: x, name: tn[j] || '', artist: ta[j] || '', duration: td[j] || 0, album: tl[j] || '', cloudStatus: tc[j] || '' })),
    })
  })
  return JSON.stringify(out)
}
