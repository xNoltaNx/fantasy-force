import { useEffect, useRef, useState } from 'react'
import { readAddonFile, type AddonFile } from '../addonFile'
import { useApp } from '../app'
import { RoleIcon } from '../bits'
import { allowed, canRemember, forget, pick, recall, remember, type Remembered } from '../savedFile'
import { store } from '../store'
import { classById, raceName } from '../wow'

const PATH = 'World of Warcraft\\_forever_\\WTF\\Account\\<your account>\\SavedVariables\\FantasyForce.lua'

const ago = (ms: number) => {
  const min = Math.round((Date.now() - ms) / 60000)
  if (min < 1) return 'just now'
  if (min < 60) return `${min} min ago`
  const h = Math.round(min / 60)
  return h < 48 ? `${h} h ago` : `${Math.round(h / 24)} days ago`
}

/** Drop the addon's saved file here: your characters (and, for officers, the in-game guild list) come in.
 *  In Chrome and Edge the file can be remembered, and is read again on each visit. */
export function AddonImport({ memberId }: { memberId: string }) {
  const { data, viewer, act } = useApp()
  const [file, setFile] = useState<AddonFile | null>(null)
  const [error, setError] = useState('')
  const [picked, setPicked] = useState<Set<string>>(new Set())
  const [over, setOver] = useState(false)
  const [done, setDone] = useState('')
  const [linked, setLinked] = useState<Remembered | null>(null)
  const pending = useRef(0) // lastModified of the remembered file now on screen, recorded once it's brought in

  const known = new Set(data.characters.filter((c) => c.member_id === memberId).map((c) => c.name.toLowerCase()))
  const otherOwner = (name: string) => data.characters.find((c) => c.member_id !== memberId && c.name.toLowerCase() === name.toLowerCase())

  const parse = async (f: File): Promise<AddonFile | null> => {
    try {
      const parsed = readAddonFile(await f.text())
      if (!parsed.characters.length && !parsed.guild && !parsed.bank && !parsed.raids.length) throw new Error('The file has no characters yet. Log in on each character once, then log out or type /reload.')
      setError('')
      return parsed
    } catch (e) {
      setFile(null)
      setError(e instanceof Error ? e.message : String(e))
      return null
    }
  }

  const show = (parsed: AddonFile, only?: string[]) => {
    setFile(parsed)
    const inGuild = parsed.characters.filter((c) => c.inGuild)
    setPicked(new Set(only ?? (inGuild.length ? inGuild : parsed.characters).map((c) => c.name)))
  }

  const read = async (f: File | undefined) => {
    if (!f) return
    setDone('')
    pending.current = 0
    const parsed = await parse(f)
    if (parsed) show(parsed)
  }

  const link = useRef<Remembered | null>(null) // the same as linked, without waiting for a render
  const setLink = (r: Remembered | null) => { link.current = r; setLinked(r) }
  const markImported = async () => {
    const r = link.current
    if (!r || !pending.current) return
    const next = { ...r, imported: pending.current }
    pending.current = 0
    setLink(next)
    await remember(memberId, next)
  }

  // Reading it again on each visit is done site-wide (SavedFileSync); here it's only chosen, shown and forgotten.
  useEffect(() => {
    if (!canRemember()) return
    let gone = false
    void recall(memberId).then((r) => { if (!gone) setLink(r) })
    return () => { gone = true }
  }, [memberId])

  // Chosen (or dropped) and remembered: the whole file shows, to pick which characters come in.
  const connect = async (given?: Awaited<ReturnType<typeof pick>>) => {
    const h = given ?? await pick()
    if (!h) return
    setDone('')
    const r = { handle: h, imported: 0 }
    setLink(r)
    await remember(memberId, r)
    if (!(await allowed(h, true))) { setError("The browser didn't allow reading the file. Choose it again and allow it."); return }
    let f: File
    try { f = await h.getFile() } catch {
      setError("Couldn't open that file. Choose it again.")
      return
    }
    const parsed = await parse(f)
    if (!parsed) return
    pending.current = f.lastModified
    show(parsed)
  }

  const chosen = file?.characters.filter((c) => picked.has(c.name)) ?? []

  return (
    <div className={`card import ${over ? 'over' : ''}`}
      onDragOver={(e) => { e.preventDefault(); setOver(true) }}
      onDragLeave={() => setOver(false)}
      onDrop={(e) => {
        e.preventDefault()
        setOver(false)
        // Chrome and Edge can hand over the dropped file itself, to remember (asked for before any await)
        const item = e.dataTransfer.items?.[0] as (DataTransferItem & { getAsFileSystemHandle?: () => Promise<{ kind: string } | null> }) | undefined
        const handle = canRemember() && !linked ? item?.getAsFileSystemHandle?.() : undefined
        const f = e.dataTransfer.files[0]
        if (handle) {
          void handle.then((h) => h && h.kind === 'file' ? connect(h as unknown as Parameters<typeof connect>[0]) : read(f), () => read(f))
        } else void read(f)
      }}>
      <h2>Bring in characters from the addon</h2>
      {!file && (
        <>
          <p className="muted small">
            With the Fantasy Force addon installed, log in on each of your characters once, then log out. Drop its file here, or choose it:
          </p>
          <p className="path small">{PATH}</p>
          {linked ? (
            <div className="row linked">
              <span className="muted small">Remembered: <b>{linked.handle.name}</b>{linked.imported ? `, last brought in ${ago(linked.imported)}` : ''}. Your characters update from it whenever you open the site.</span>
              <button className="button ghost" onClick={() => { setLink(null); void forget(memberId) }}>Forget it</button>
            </div>
          ) : (
            <div className="row">
              {canRemember() && <button className="button" onClick={() => void connect()}>Choose and remember it</button>}
              <label className="button ghost">Choose file<input type="file" accept=".lua" hidden onChange={(e) => void read(e.target.files?.[0])} /></label>
            </div>
          )}
          {canRemember() && !linked && (
            <p className="muted small">
              "Choose and remember it" keeps the file in this browser, so your characters come up to date whenever you open any page of the site.
              In the file window, paste the path above (with your account folder) into the File name box. When the browser asks, pick "Allow on every visit".
            </p>
          )}
        </>
      )}
      {error && <p className="error-line">{error}</p>}
      {done && <p className="done-line">{done}</p>}
      {file && (
        <>
          <ul className="import-list">
            {file.characters.map((c) => {
              const owner = otherOwner(c.name)
              return (
                <li key={c.name}>
                  <label className="check">
                    <input type="checkbox" checked={picked.has(c.name)} disabled={!!owner} onChange={(e) => {
                      const next = new Set(picked)
                      if (e.target.checked) next.add(c.name)
                      else next.delete(c.name)
                      setPicked(next)
                    }} />
                    <RoleIcon role={c.role} />
                    <b className="cls-name" style={{ '--cls': classById(c.class_id)?.color } as React.CSSProperties}>{c.name}</b>
                    <span className="muted">Level {c.level} {raceName(c.race)} {c.spec} {classById(c.class_id)?.name}</span>
                    {c.professions.length > 0 && <span className="muted small">· {c.professions.map((p) => `${p.name} ${p.skill}`).join(', ')}</span>}
                    {known.has(c.name.toLowerCase()) && <span className="tag">Update</span>}
                    {owner && <span className="tag">Someone else's</span>}
                    {!c.inGuild && <span className="muted small">(not in the guild)</span>}
                  </label>
                </li>
              )
            })}
          </ul>
          <div className="row">
            <button className="button" disabled={!chosen.length} onClick={async () => {
              if (await act(() => store.importCharacters(memberId, chosen))) {
                setDone(`${chosen.length} ${chosen.length === 1 ? 'character' : 'characters'} brought in.`)
                setFile(null)
                await markImported()
              }
            }}>Bring in {chosen.length} {chosen.length === 1 ? 'character' : 'characters'}</button>
            {viewer?.isOfficer && file.guild && (
              <button className="button ghost" onClick={async () => {
                const g = file.guild!
                if (await act(() => store.saveInGameRoster({ updated_at: new Date(g.updated * 1000).toISOString(), recorded_by: g.by, members: g.members }))) {
                  setDone(`In-game guild list updated: ${g.members.length} members.`)
                }
              }}>Update the in-game guild list ({file.guild.members.length})</button>
            )}
            {viewer?.isOfficer && file.bank && (
              <button className="button ghost" onClick={async () => {
                if (await act(() => store.saveBank(file.bank!))) setDone(`Guild bank updated: ${file.bank!.tabs.reduce((n, t) => n + t.items.length, 0)} kinds of item.`)
              }}>Update the guild bank</button>
            )}
            {viewer?.isOfficer && file.raids.length > 0 && (
              <button className="button ghost" onClick={async () => {
                if (await act(() => store.importRaids(file.raids))) setDone(`${file.raids.length} ${file.raids.length === 1 ? 'raid' : 'raids'} brought in.`)
              }}>Bring in raids ({file.raids.length})</button>
            )}
            <button className="button ghost" onClick={() => { setFile(null); void markImported() }}>{pending.current ? 'Not now' : 'Cancel'}</button>
          </div>
        </>
      )}
    </div>
  )
}
