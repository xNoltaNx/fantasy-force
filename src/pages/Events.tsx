import { useState } from 'react'
import { useApp } from '../app'
import { CharLine, charsOf, memberName, RoleIcon } from '../bits'
import { store } from '../store'
import type { GuildEvent, Signup, SignupStatus } from '../types'
import { ROLES, type Role } from '../wow'

const ROLE_ORDER = ROLES.map((r) => r.id)

const STATUS:{ id: SignupStatus; name: string }[] = [
  { id: 'in', name: 'Going' },
  { id: 'maybe', name: 'Maybe' },
  { id: 'out', name: "Can't make it" },
]

export function Events() {
  const { data, viewer } = useApp()
  const [past, setPast] = useState(false)
  const [editing, setEditing] = useState<GuildEvent | 'new' | null>(null)
  const now = Date.now()
  const list = data.events
    .filter((e) => (new Date(e.starts_at).getTime() + e.duration_minutes * 60000 < now) === past)
    .sort((a, b) => (past ? -1 : 1) * (new Date(a.starts_at).getTime() - new Date(b.starts_at).getTime()))

  return (
    <section>
      <div className="filters">
        <div className="segmented">
          <button className={!past ? 'on' : ''} onClick={() => setPast(false)}>Upcoming</button>
          <button className={past ? 'on' : ''} onClick={() => setPast(true)}>Past</button>
        </div>
        {viewer?.isOfficer && <button className="button" onClick={() => setEditing('new')}>New event</button>}
      </div>
      {editing && <EventForm event={editing === 'new' ? null : editing} done={() => setEditing(null)} />}
      {list.length === 0 && <p className="muted">{past ? 'No past events.' : 'Nothing planned yet.'}</p>}
      {list.map((e) => <EventCard key={e.id} e={e} onEdit={() => setEditing(e)} />)}
    </section>
  )
}

function EventCard({ e, onEdit }: { e: GuildEvent; onEdit: () => void }) {
  const { data, viewer, act } = useApp()
  const signups = data.signups.filter((s) => s.event_id === e.id)
  const going = signups.filter((s) => s.status === 'in')
  const need: Record<Role, number> = { tank: e.need_tank, healer: e.need_healer, dps: e.need_dps }
  const start = new Date(e.starts_at)
  const end = new Date(start.getTime() + e.duration_minutes * 60000)

  return (
    <article className="card event">
      <header className="event-head">
        <div>
          <h2>{e.title}</h2>
          <div className="muted">
            {start.toLocaleDateString([], { weekday: 'long', month: 'short', day: 'numeric' })}, {start.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })} to {end.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', timeZoneName: 'short' })}
          </div>
        </div>
        {viewer?.isOfficer && (
          <div className="row">
            <button className="button ghost small" onClick={onEdit}>Edit</button>
            <button className="button ghost small" onClick={() => confirm(`Delete "${e.title}"?`) && act(() => store.deleteEvent(e.id))}>Delete</button>
          </div>
        )}
      </header>
      {e.description && <p>{e.description}</p>}

      <div className="needs">
        {ROLES.map((r) => {
          const have = going.filter((s) => s.role === r.id).length
          const full = have >= need[r.id]
          return (
            <div key={r.id} className={`need ${full ? 'full' : ''}`}>
              <RoleIcon role={r.id} /> {r.name} <b>{have}</b><span className="muted"> of {need[r.id]}</span>
              <span className="need-bar"><span style={{ width: `${Math.min(100, (have / Math.max(1, need[r.id])) * 100)}%` }} /></span>
            </div>
          )
        })}
      </div>

      {viewer?.isApproved && viewer.member && <MySignup e={e} memberId={viewer.member.id} current={signups.find((s) => s.member_id === viewer.member!.id)} />}

      <div className="signups">
        {STATUS.map((st) => {
          const group = signups.filter((s) => s.status === st.id)
          if (!group.length) return null
          return (
            <div key={st.id}>
              <h3>{st.name} <span className="muted">({group.length})</span></h3>
              <ul>
                {group.sort((a, b) => ROLE_ORDER.indexOf(a.role) - ROLE_ORDER.indexOf(b.role)).map((s) => {
                  const c = data.characters.find((x) => x.id === s.character_id)
                  return (
                    <li key={s.member_id}>
                      {c ? <CharLine c={{ ...c, role: s.role }} region={data.guild.region} links={false} /> : memberName(data, s.member_id)}
                      <span className="muted small"> {memberName(data, s.member_id)}</span>
                      {s.comment && <span className="muted small"> · “{s.comment}”</span>}
                    </li>
                  )
                })}
              </ul>
            </div>
          )
        })}
      </div>
    </article>
  )
}

function MySignup({ e, memberId, current }: { e: GuildEvent; memberId: string; current?: Signup }) {
  const { data, act } = useApp()
  const chars = charsOf(data, memberId)
  const first = chars[0]
  const [charId, setCharId] = useState(current?.character_id ?? first?.id ?? '')
  const char = chars.find((c) => c.id === charId)
  const [role, setRole] = useState<Role>(current?.role ?? first?.role ?? 'dps')
  const [comment, setComment] = useState(current?.comment ?? '')
  if (!chars.length) return <p className="muted">Add a character on <a href="#/me">My characters</a> to sign up.</p>

  const send = (status: SignupStatus) => act(() => store.saveSignup({ event_id: e.id, member_id: memberId, character_id: charId, role, status, comment }))

  return (
    <div className="my-signup">
      <select value={charId} onChange={(ev) => {
        setCharId(ev.target.value)
        const c = chars.find((x) => x.id === ev.target.value)
        if (c) setRole(c.role)
      }} aria-label="Character">
        {chars.map((c) => <option key={c.id} value={c.id}>{c.name} ({c.spec})</option>)}
      </select>
      <select value={role} onChange={(ev) => setRole(ev.target.value as Role)} aria-label="Role">
        {ROLES.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
      </select>
      <input placeholder="Note (optional)" value={comment} onChange={(ev) => setComment(ev.target.value)} />
      {STATUS.map((st) => (
        <button key={st.id} className={`button small ${current?.status === st.id ? '' : 'ghost'}`} onClick={() => send(st.id)} disabled={!char}>{st.name}</button>
      ))}
    </div>
  )
}

function toLocalInput(iso: string): string {
  const d = new Date(iso)
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16)
}

function EventForm({ event, done }: { event: GuildEvent | null; done: () => void }) {
  const { act } = useApp()
  const tomorrow = new Date(Date.now() + 86400000)
  tomorrow.setHours(19, 0, 0, 0)
  const [f, setF] = useState({
    title: event?.title ?? '',
    when: toLocalInput(event?.starts_at ?? tomorrow.toISOString()),
    hours: (event?.duration_minutes ?? 180) / 60,
    description: event?.description ?? '',
    need_tank: event?.need_tank ?? 2,
    need_healer: event?.need_healer ?? 4,
    need_dps: event?.need_dps ?? 14,
  })
  const num = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement>) => setF({ ...f, [k]: Number(e.target.value) })

  const save = async () => {
    const ok = await act(() => store.saveEvent({
      ...(event ? { id: event.id } : {}),
      title: f.title.trim() || 'Untitled event',
      starts_at: new Date(f.when).toISOString(),
      duration_minutes: Math.round(f.hours * 60),
      description: f.description,
      need_tank: f.need_tank, need_healer: f.need_healer, need_dps: f.need_dps,
    }))
    if (ok) done()
  }

  return (
    <div className="card form">
      <h2>{event ? 'Edit event' : 'New event'}</h2>
      <label>Title <input value={f.title} onChange={(e) => setF({ ...f, title: e.target.value })} placeholder="Raid night" /></label>
      <div className="row">
        <label>Starts (your time) <input type="datetime-local" value={f.when} onChange={(e) => setF({ ...f, when: e.target.value })} /></label>
        <label>Hours <input type="number" min={0.5} step={0.5} value={f.hours} onChange={num('hours')} /></label>
      </div>
      <div className="row">
        <label>Tanks needed <input type="number" min={0} value={f.need_tank} onChange={num('need_tank')} /></label>
        <label>Healers needed <input type="number" min={0} value={f.need_healer} onChange={num('need_healer')} /></label>
        <label>DPS needed <input type="number" min={0} value={f.need_dps} onChange={num('need_dps')} /></label>
      </div>
      <label>Details <textarea rows={3} value={f.description} onChange={(e) => setF({ ...f, description: e.target.value })} /></label>
      <div className="row">
        <button className="button" onClick={save}>{event ? 'Save' : 'Post event'}</button>
        <button className="button ghost" onClick={done}>Cancel</button>
      </div>
    </div>
  )
}
