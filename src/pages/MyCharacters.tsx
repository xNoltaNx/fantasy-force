import { useState } from 'react'
import { useApp } from '../app'
import { CharLine, charsOf } from '../bits'
import { store } from '../store'
import type { Character, Profession } from '../types'
import { myTimeZone, zoneChoices, zoneLabel } from '../week'
import { CLASSES, classById, MAX_LEVEL, PROFESSIONS, racesFor, roleFor } from '../wow'
import { AddonImport } from './AddonImport'

/** A member's profile and characters: your own, or anyone's for an officer (#/me/<member id>). */
export function MyCharacters({ memberId }: { memberId?: string }) {
  const { data, viewer, act } = useApp()
  const id = memberId ?? viewer?.member?.id
  const m = data.members.find((x) => x.id === id)
  const [editing, setEditing] = useState<Character | 'new' | null>(null)

  if (!viewer) return <p>Sign in with Discord to add your characters.</p>
  if (!m) return <p className="muted">That member isn't here.</p>
  const mine = m.id === viewer.id
  if (!mine && !viewer.isOfficer) return <p className="muted">Only officers can edit other members.</p>
  const chars = charsOf(data, m.id)

  return (
    <section>
      {mine && !viewer.isApproved && (
        <div className="card notice">An officer needs to approve you before you show on the roster. Add your characters meanwhile.</div>
      )}
      {!mine && <p className="muted">Editing {m.display_name} as an officer.</p>}
      <Profile key={m.id} memberId={m.id} />
      <AddonImport memberId={m.id} />

      <div className="card">
        <div className="card-head">
          <h2>Characters</h2>
          <button className="button" onClick={() => setEditing('new')}>Add character</button>
        </div>
        {editing && <CharacterForm memberId={m.id} c={editing === 'new' ? null : editing} done={() => setEditing(null)} />}
        {chars.length === 0 && !editing && <p className="muted">No characters yet. Add your main first.</p>}
        <ul className="char-list">
          {chars.map((c) => (
            <li key={c.id} className="char-edit">
              <CharLine c={c} race />
              {c.is_main ? <span className="tag">Main</span> : <button className="button ghost small" onClick={() => act(() => store.setMain(m.id, c.id))}>Make main</button>}
              <button className="button ghost small" onClick={() => setEditing(c)}>Edit</button>
              <button className="button ghost small" onClick={() => confirm(`Remove ${c.name}?`) && act(() => store.deleteCharacter(c.id))}>Remove</button>
            </li>
          ))}
        </ul>
      </div>
    </section>
  )
}

function Profile({ memberId }: { memberId: string }) {
  const { data, act } = useApp()
  const m = data.members.find((x) => x.id === memberId)!
  const [f, setF] = useState({ display_name: m.display_name, timezone: m.timezone, about: m.about })
  const dirty = f.display_name !== m.display_name || f.timezone !== m.timezone || f.about !== m.about
  const mine = myTimeZone()
  const zones = zoneChoices(mine, f.timezone)
  return (
    <div className="card form">
      <h2>Profile</h2>
      <div className="row">
        <label>Name the guild knows you by <input value={f.display_name} onChange={(e) => setF({ ...f, display_name: e.target.value })} /></label>
        <label>Time zone
          <select value={f.timezone} onChange={(e) => setF({ ...f, timezone: e.target.value })}>
            <optgroup label="Common">
              {zones.common.map((z) => <option key={z} value={z}>{zoneLabel(z)}</option>)}
            </optgroup>
            <optgroup label="All">
              {zones.all.map((z) => <option key={z} value={z}>{zoneLabel(z)}</option>)}
            </optgroup>
          </select>
          {f.timezone !== mine && (
            <button type="button" className="button ghost small" onClick={() => setF({ ...f, timezone: mine })}>Use {zoneLabel(mine)}</button>
          )}
        </label>
      </div>
      <label>About (optional) <textarea rows={2} value={f.about} onChange={(e) => setF({ ...f, about: e.target.value })} /></label>
      <div className="row"><button className="button" disabled={!dirty} onClick={() => act(() => store.updateMember(m.id, f))}>Save profile</button></div>
    </div>
  )
}

function CharacterForm({ memberId, c, done }: { memberId: string; c: Character | null; done: () => void }) {
  const { data, act } = useApp()
  const hasMain = data.characters.some((x) => x.member_id === memberId && x.is_main)
  const [f, setF] = useState({
    name: c?.name ?? '',
    race: c?.race ?? '',
    class_id: c?.class_id ?? 'warrior',
    spec: c?.spec ?? 'Arms',
    level: c?.level ?? null as number | null,
    professions: c?.professions ?? [] as Profession[],
    note: c?.note ?? '',
    is_main: c?.is_main ?? !hasMain,
  })
  const cls = classById(f.class_id)!
  const setProf = (i: number, p: Partial<Profession> | null) => setF({
    ...f,
    professions: p === null ? f.professions.filter((_, j) => j !== i) : f.professions.map((x, j) => (j === i ? { ...x, ...p } : x)),
  })

  const save = async () => {
    if (!f.name.trim()) return
    const ok = await act(() => store.saveCharacter({
      ...(c ? { id: c.id } : {}),
      member_id: memberId,
      ...f,
      name: f.name.trim(),
      level: f.level ? Math.min(MAX_LEVEL, Math.max(1, f.level)) : null,
      professions: f.professions.filter((p) => p.name),
      role: roleFor(f.class_id, f.spec),
    }))
    if (ok) done()
  }

  return (
    <div className="form inset">
      <div className="row">
        <label>Name <input value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} autoFocus placeholder="First and last name" /></label>
        <label>Race
          <select value={f.race} onChange={(e) => setF({ ...f, race: e.target.value })}>
            <option value="">Not given</option>
            {racesFor(data.guild.faction).map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
          </select>
        </label>
        <label>Level <input type="number" min={1} max={MAX_LEVEL} value={f.level ?? ''} onChange={(e) => setF({ ...f, level: e.target.value ? Number(e.target.value) : null })} /></label>
      </div>
      <div className="row">
        <label>Class
          <select value={f.class_id} onChange={(e) => setF({ ...f, class_id: e.target.value, spec: classById(e.target.value)!.specs[0].name })}>
            {CLASSES.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
          </select>
        </label>
        <label>Spec
          <select value={f.spec} onChange={(e) => setF({ ...f, spec: e.target.value })}>
            {cls.specs.map((s) => <option key={s.name} value={s.name}>{s.name} ({s.role === 'dps' ? 'DPS' : s.role === 'tank' ? 'Tank' : 'Healer'})</option>)}
          </select>
        </label>
      </div>
      <div className="prof-edit">
        <span className="prof-edit-label">Professions</span>
        {f.professions.map((p, i) => (
          <span className="row" key={i}>
            <select value={p.name} onChange={(e) => setProf(i, { name: e.target.value })} aria-label="Profession">
              {[...new Set([p.name, ...PROFESSIONS])].filter(Boolean).map((n) => <option key={n} value={n}>{n}</option>)}
            </select>
            <input type="number" min={0} max={300} value={p.skill} onChange={(e) => setProf(i, { skill: Number(e.target.value), max: Math.max(p.max, 75) })} aria-label="Skill" className="skill-input" />
            <button className="button ghost small" onClick={() => setProf(i, null)}>Remove</button>
          </span>
        ))}
        <button className="button ghost small" onClick={() => setF({ ...f, professions: [...f.professions, { name: PROFESSIONS[0]!, skill: 1, max: 75 }] })}>Add profession</button>
      </div>
      <label>Note (optional) <input value={f.note} onChange={(e) => setF({ ...f, note: e.target.value })} placeholder="Off-spec, what you're working toward…" /></label>
      <label className="check"><input type="checkbox" checked={f.is_main} onChange={(e) => setF({ ...f, is_main: e.target.checked })} /> This is the main</label>
      <div className="row">
        <button className="button" onClick={save} disabled={!f.name.trim()}>{c ? 'Save' : 'Add'}</button>
        <button className="button ghost" onClick={done}>Cancel</button>
      </div>
    </div>
  )
}
