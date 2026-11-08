import { useState } from 'react'
import { useApp } from '../app'
import { Avatar, memberName } from '../bits'
import type { Character } from '../types'
import { GameLink } from '../wowhead'
import { classById } from '../wow'

// Raid attendance and loot from the addon: who came to how many raids, what each raid killed and dropped to whom.
export function Raids() {
  const { data, viewer } = useApp()
  const [span, setSpan] = useState(8)
  const [who, setWho] = useState('')
  if (!viewer?.isApproved) return <p className="muted">Sign in as a guild member to see raids.</p>
  const all = [...data.raids].sort((a, b) => b.started_at.localeCompare(a.started_at))
  if (!all.length) {
    return (
      <div className="card">
        <h2>Raids</h2>
        <p className="muted">No raids yet. Whoever leads the raid runs the Fantasy Force addon; afterwards an officer drops its file on My characters and presses "Bring in raids".</p>
      </div>
    )
  }
  const raids = span ? all.slice(0, span) : all
  const byName = new Map<string, Character>(data.characters.map((c) => [c.name.toLowerCase(), c]))
  const ownerOf = (name: string) => byName.get(name.toLowerCase())?.member_id

  const rows = data.members.filter((m) => m.rank_id !== null).map((m) => {
    const went = raids.filter((r) => r.attendees.some((a) => ownerOf(a) === m.id)).length
    const loot = raids.flatMap((r) => r.loot.filter((l) => ownerOf(l.to) === m.id)).length
    return { m, went, loot }
  }).filter((r) => r.went > 0 || r.loot > 0).sort((a, b) => b.went - a.went || a.loot - b.loot || a.m.display_name.localeCompare(b.m.display_name))

  return (
    <section>
      <div className="filters">
        <div className="segmented">
          {[4, 8, 0].map((n) => <button key={n} className={span === n ? 'on' : ''} onClick={() => setSpan(n)}>{n ? `Last ${n} raids` : 'All raids'}</button>)}
        </div>
        <select value={who} onChange={(e) => setWho(e.target.value)} aria-label="Loot for">
          <option value="">Loot for everyone</option>
          {rows.map(({ m }) => <option key={m.id} value={m.id}>Loot for {m.display_name}</option>)}
        </select>
      </div>

      <div className="card">
        <h2>Attendance <span className="muted small">{raids.length} {raids.length === 1 ? 'raid' : 'raids'}</span></h2>
        <ul className="attend-list">
          {rows.map(({ m, went, loot }) => (
            <li key={m.id} title={`${m.display_name}: ${went} of ${raids.length} raids, ${loot} ${loot === 1 ? 'item' : 'items'} of loot`}>
              <button className="attend-row" onClick={() => setWho(who === m.id ? '' : m.id)} aria-pressed={who === m.id}>
                <Avatar m={m} size={26} />
                <span className="attend-name">{m.display_name}</span>
                <span className="skill-bar"><span style={{ width: `${(went / raids.length) * 100}%` }} /></span>
                <span className="attend-pct">{Math.round((went / raids.length) * 100)}%</span>
                <span className="muted small attend-loot">{loot ? `${loot} loot` : ''}</span>
              </button>
            </li>
          ))}
        </ul>
      </div>

      {raids.map((r) => {
        const loot = r.loot.filter((l) => !who || ownerOf(l.to) === who)
        if (who && !loot.length && !r.attendees.some((a) => ownerOf(a) === who)) return null
        const start = new Date(r.started_at)
        return (
          <article className="card raid" key={r.key}>
            <header className="event-head">
              <div>
                <h2>{r.zone}</h2>
                <div className="muted">{start.toLocaleDateString([], { weekday: 'long', month: 'short', day: 'numeric' })} · {r.bosses.length} {r.bosses.length === 1 ? 'boss' : 'bosses'} killed · {r.attendees.length} there</div>
              </div>
            </header>
            <div className="boss-chips" title={r.bosses.map((b) => `${b.name}: ${b.attendees.length} there`).join('\n')}>
              {r.bosses.map((b) => <span key={b.name} className="tag">{b.name}</span>)}
            </div>
            {loot.length > 0 && (
              <ul className="loot-list">
                {loot.map((l) => {
                  const c = byName.get(l.to.toLowerCase())
                  return (
                    <li key={`${l.item_id}${l.to}${l.at}`} className={`q${l.quality}`}>
                      <GameLink name={l.name} item={l.item_id || undefined} />
                      <span className="muted small">to</span>
                      <b className="cls-name" style={{ '--cls': classById(c?.class_id ?? '')?.color ?? 'var(--text)' } as React.CSSProperties}>{l.to}</b>
                      {c && <span className="muted small">{memberName(data, c.member_id)}</span>}
                      {l.boss && <span className="muted small">· {l.boss}</span>}
                    </li>
                  )
                })}
              </ul>
            )}
          </article>
        )
      })}
    </section>
  )
}
