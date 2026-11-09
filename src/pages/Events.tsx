import { useEffect, useState } from 'react'
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

const isPast = (e: GuildEvent, now: number) => new Date(e.starts_at).getTime() + e.duration_minutes * 60000 < now

/** `pick`: an event's id from its link (#/events/<id>, as the Discord post links it), scrolled into view. */
export function Events({ pick }: { pick?: string }) {
  const { data, viewer } = useApp()
  const picked = data.events.find((e) => e.id === pick)
  const [past, setPast] = useState(() => !!picked && isPast(picked, Date.now()))
  const [editing, setEditing] = useState<GuildEvent | 'new' | null>(null)
  useEffect(() => {
    if (pick) document.getElementById(`event-${pick}`)?.scrollIntoView({ block: 'start' })
  }, [pick])
  const now = Date.now()
  const list = data.events
    .filter((e) => isPast(e, now) === past)
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
    <article className="card event" id={`event-${e.id}`}>
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
                      {c ? <CharLine c={{ ...c, role: s.role }} /> : memberName(data, s.member_id)}
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

/** Whether the event is up in the guild's Discord channel: the Discord logo, lit or faded, named on hover. */
function DiscordMark({ posted }: { posted: boolean }) {
  const label = posted ? 'Posted in Discord' : 'Not in Discord yet'
  return (
    <span className={`discord-mark ${posted ? 'on' : ''}`} title={label} role="img" aria-label={label}>
      <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="currentColor">
        <path d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.057 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028 14.09 14.09 0 0 0 1.226-1.994.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.946 2.418-2.157 2.418z" />
      </svg>
    </span>
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
      <h2>{event ? 'Edit event' : 'New event'}{event && store.mode === 'live' && <DiscordMark posted={!!event.discord_message_id} />}</h2>
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
