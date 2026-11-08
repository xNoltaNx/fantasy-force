import { useState } from 'react'
import { readAddonFile, type AddonFile } from '../addonFile'
import { useApp } from '../app'
import { RoleIcon } from '../bits'
import { store } from '../store'
import { classById, raceName } from '../wow'

const PATH = 'World of Warcraft\\_forever_\\WTF\\Account\\<your account>\\SavedVariables\\FantasyForce.lua'

/** Drop the addon's saved file here: your characters (and, for officers, the in-game guild list) come in. */
export function AddonImport({ memberId }: { memberId: string }) {
  const { data, viewer, act } = useApp()
  const [file, setFile] = useState<AddonFile | null>(null)
  const [error, setError] = useState('')
  const [picked, setPicked] = useState<Set<string>>(new Set())
  const [over, setOver] = useState(false)
  const [done, setDone] = useState('')

  const read = async (f: File | undefined) => {
    if (!f) return
    setDone('')
    try {
      const parsed = readAddonFile(await f.text())
      if (!parsed.characters.length && !parsed.guild && !parsed.bank && !parsed.raids.length) throw new Error('The file has no characters yet. Log in on each character once, then log out or type /reload.')
      setFile(parsed)
      setError('')
      const inGuild = parsed.characters.filter((c) => c.inGuild)
      setPicked(new Set((inGuild.length ? inGuild : parsed.characters).map((c) => c.name)))
    } catch (e) {
      setFile(null)
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  const known = new Set(data.characters.filter((c) => c.member_id === memberId).map((c) => c.name.toLowerCase()))
  const chosen = file?.characters.filter((c) => picked.has(c.name)) ?? []
  const otherOwner = (name: string) => data.characters.find((c) => c.member_id !== memberId && c.name.toLowerCase() === name.toLowerCase())

  return (
    <div className={`card import ${over ? 'over' : ''}`}
      onDragOver={(e) => { e.preventDefault(); setOver(true) }}
      onDragLeave={() => setOver(false)}
      onDrop={(e) => { e.preventDefault(); setOver(false); void read(e.dataTransfer.files[0]) }}>
      <h2>Bring in characters from the addon</h2>
      {!file && (
        <>
          <p className="muted small">
            With the Fantasy Force addon installed, log in on each of your characters once, then log out. Drop its file here, or choose it:
          </p>
          <p className="path small">{PATH}</p>
          <label className="button ghost">Choose file<input type="file" accept=".lua" hidden onChange={(e) => void read(e.target.files?.[0])} /></label>
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
            <button className="button ghost" onClick={() => setFile(null)}>Cancel</button>
          </div>
        </>
      )}
    </div>
  )
}
