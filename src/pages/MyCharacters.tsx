import { useState } from 'react'
import { useApp } from '../app'
import { CharLine, charsOf } from '../bits'
import { store } from '../store'
import type { Character } from '../types'
import { allTimeZones } from '../week'
import { CLASSES, classById, roleFor } from '../wow'

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
              <CharLine c={c} region={data.guild.region} />
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
  return (
    <div className="card form">
      <h2>Profile</h2>
      <div className="row">
        <label>Name the guild knows you by <input value={f.display_name} onChange={(e) => setF({ ...f, display_name: e.target.value })} /></label>
        <label>Time zone
          <select value={f.timezone} onChange={(e) => setF({ ...f, timezone: e.target.value })}>
            {allTimeZones().map((z) => <option key={z} value={z}>{z.replace(/_/g, ' ')}</option>)}
          </select>
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
    realm: c?.realm ?? data.guild.realm,
    class_id: c?.class_id ?? 'warrior',
    spec: c?.spec ?? 'Arms',
    item_level: c?.item_level ?? null as number | null,
    note: c?.note ?? '',
    is_main: c?.is_main ?? !hasMain,
  })
  const cls = classById(f.class_id)!

  const save = async () => {
    if (!f.name.trim()) return
    const ok = await act(() => store.saveCharacter({
      ...(c ? { id: c.id } : {}),
      member_id: memberId,
      ...f,
      name: f.name.trim(),
      realm: f.realm.trim() || data.guild.realm,
      role: roleFor(f.class_id, f.spec),
    }))
    if (ok) done()
  }

  return (
    <div className="form inset">
      <div className="row">
        <label>Name <input value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} autoFocus /></label>
        <label>Realm <input value={f.realm} onChange={(e) => setF({ ...f, realm: e.target.value })} /></label>
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
        <label>Item level <input type="number" value={f.item_level ?? ''} onChange={(e) => setF({ ...f, item_level: e.target.value ? Number(e.target.value) : null })} /></label>
      </div>
      <label>Note (optional) <input value={f.note} onChange={(e) => setF({ ...f, note: e.target.value })} placeholder="Off-spec, professions…" /></label>
      <label className="check"><input type="checkbox" checked={f.is_main} onChange={(e) => setF({ ...f, is_main: e.target.checked })} /> This is the main</label>
      <div className="row">
        <button className="button" onClick={save} disabled={!f.name.trim()}>{c ? 'Save' : 'Add'}</button>
        <button className="button ghost" onClick={done}>Cancel</button>
      </div>
    </div>
  )
}
