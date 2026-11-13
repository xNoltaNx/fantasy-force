import { useEffect, useRef, useState } from 'react'
import { readAddonFile, type ImportedCharacter } from './addonFile'
import { useApp } from './app'
import { allowed, recall, remember, type Remembered } from './savedFile'
import { store } from './store'

const ago = (ms: number) => {
  const min = Math.round((Date.now() - ms) / 60000)
  if (min < 1) return 'just now'
  if (min < 60) return `${min} min ago`
  const h = Math.round(min / 60)
  return h < 48 ? `${h} h ago` : `${Math.round(h / 24)} days ago`
}

/** On every page: when this browser remembers the signed-in member's saved file (My characters, "Choose and
 *  remember it"), read it again on opening the site, on each page change and on coming back to the tab. The
 *  member's characters already on the site update by themselves; new ones in the file wait for one click. */
export function SavedFileSync({ page }: { page: string }) {
  const { data, viewer, act } = useApp()
  const memberId = viewer?.member?.id
  const [needsClick, setNeedsClick] = useState(false)
  const [added, setAdded] = useState<ImportedCharacter[]>([])
  const [note, setNote] = useState('')
  const busy = useRef(false)
  const latest = useRef({ data, act })
  latest.current = { data, act }

  const check = async (ask: boolean) => {
    if (!memberId || busy.current) return
    busy.current = true
    try {
      const r: Remembered | null = await recall(memberId)
      if (!r) { setNeedsClick(false); setAdded([]); return }
      if (!(await allowed(r.handle, ask))) { setNeedsClick(true); return }
      setNeedsClick(false)
      const f = await r.handle.getFile()
      const fresh = f.lastModified > r.imported // characters are only re-imported when the game saved since
      const parsed = readAddonFile(await f.text())
      const { data: d, act: run } = latest.current
      const owned = (n: string, mine: boolean) => d.characters.some((c) => (c.member_id === memberId) === mine && c.name.toLowerCase() === n.toLowerCase())
      const inGuild = parsed.characters.some((c) => c.inGuild)
      const mine = parsed.characters.filter((c) => owned(c.name, true))
      const newOnes = parsed.characters.filter((c) => !owned(c.name, true) && !owned(c.name, false) && (c.inGuild || !inGuild) && !(r.skipped ?? []).includes(c.name))
      if (fresh && mine.length && await run(() => store.importCharacters(memberId, mine))) {
        setNote(`Your characters are up to date from your saved file (saved ${ago(f.lastModified)}).`)
      }
      setAdded(newOnes)
      if (fresh) await remember(memberId, { ...r, imported: f.lastModified })
    } catch {
      // moved, renamed or unreadable: My characters says so when it's opened
    } finally {
      busy.current = false
    }
  }

  // on opening the site and on each page change
  useEffect(() => { void check(false) }, [memberId, page]) // eslint-disable-line
  // back on this tab, say after logging out of the game
  useEffect(() => {
    const back = () => { if (document.visibilityState === 'visible') void check(false) }
    document.addEventListener('visibilitychange', back)
    return () => document.removeEventListener('visibilitychange', back)
  }, [memberId]) // eslint-disable-line
  // the note fades after a while
  useEffect(() => {
    if (!note) return
    const t = setTimeout(() => setNote(''), 8000)
    return () => clearTimeout(t)
  }, [note])

  const skip = async () => {
    const r = memberId ? await recall(memberId) : null
    if (r) await remember(memberId!, { ...r, skipped: [...new Set([...(r.skipped ?? []), ...added.map((c) => c.name)])] })
    setAdded([])
  }

  if (!memberId || (!needsClick && !added.length && !note)) return null
  return (
    <div className="sync-bar">
      {needsClick && (
        <>
          <span>Keep your characters up to date from your saved file?</span>
          <button className="button small" onClick={() => void check(true)}>Allow</button>
          <span className="muted small">Pick "Allow on every visit" and this won't ask again.</span>
        </>
      )}
      {!needsClick && added.length > 0 && (
        <>
          <span>New in your saved file: <b>{added.map((c) => c.name).join(', ')}</b></span>
          <button className="button small" onClick={async () => {
            const list = added
            if (await act(() => store.importCharacters(memberId, list))) {
              setAdded([])
              setNote(`${list.length} ${list.length === 1 ? 'character' : 'characters'} added.`)
            }
          }}>Add {added.length === 1 ? 'it' : 'them'}</button>
          <button className="button ghost small" onClick={() => void skip()}>Not {added.length === 1 ? 'this one' : 'these'}</button>
        </>
      )}
      {!needsClick && !added.length && note && <span className="done-line">{note}</span>}
    </div>
  )
}
