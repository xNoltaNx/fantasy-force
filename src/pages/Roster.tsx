import { useMemo, useState } from 'react'
import { useApp } from '../app'
import { Avatar, CharLine, charsOf, rankName } from '../bits'
import { localTimeIn } from '../week'
import { CLASSES, ROLES } from '../wow'

export function Roster() {
  const { data, viewer } = useApp()
  const [q, setQ] = useState('')
  const [cls, setCls] = useState('')
  const [role, setRole] = useState('')
  const [rank, setRank] = useState('')
  const [alts, setAlts] = useState(true)
  const [open, setOpen] = useState<string | null>(null)

  const ranks = [...data.ranks].sort((a, b) => a.sort - b.sort)
  const rows = useMemo(() => {
    const needle = q.trim().toLowerCase()
    return data.members
      .filter((m) => m.rank_id !== null)
      .map((m) => ({ m, chars: charsOf(data, m.id) }))
      .filter(({ m, chars }) => {
        const pool = alts ? chars : chars.filter((c) => c.is_main)
        if (rank && String(m.rank_id) !== rank) return false
        if (cls && !pool.some((c) => c.class_id === cls)) return false
        if (role && !pool.some((c) => c.role === role)) return false
        if (needle && !(m.display_name.toLowerCase().includes(needle) || m.discord_name.toLowerCase().includes(needle)
          || chars.some((c) => c.name.toLowerCase().includes(needle)))) return false
        return true
      })
      .sort((a, b) => {
        const ra = ranks.findIndex((r) => r.id === a.m.rank_id), rb = ranks.findIndex((r) => r.id === b.m.rank_id)
        return ra - rb || a.m.display_name.localeCompare(b.m.display_name)
      })
  }, [data, q, cls, role, rank, alts, ranks])

  const total = data.members.filter((m) => m.rank_id !== null).length

  return (
    <section>
      <div className="filters">
        <input placeholder="Search players or characters" value={q} onChange={(e) => setQ(e.target.value)} />
        <select value={cls} onChange={(e) => setCls(e.target.value)} aria-label="Class">
          <option value="">Every class</option>
          {CLASSES.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
        <select value={role} onChange={(e) => setRole(e.target.value)} aria-label="Role">
          <option value="">Every role</option>
          {ROLES.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
        </select>
        <select value={rank} onChange={(e) => setRank(e.target.value)} aria-label="Rank">
          <option value="">Every rank</option>
          {ranks.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
        </select>
        <label className="check"><input type="checkbox" checked={alts} onChange={(e) => setAlts(e.target.checked)} /> Match alts too</label>
      </div>
      <p className="muted small">{rows.length === total ? `${total} members` : `${rows.length} of ${total} members`}</p>

      <div className="roster">
        {rows.map(({ m, chars }) => {
          const main = chars.find((c) => c.is_main)
          const others = chars.filter((c) => !c.is_main)
          const isOpen = open === m.id
          return (
            <article key={m.id} className={`member ${isOpen ? 'open' : ''}`}>
              <button className="member-head" onClick={() => setOpen(isOpen ? null : m.id)} aria-expanded={isOpen}>
                <Avatar m={m} />
                <span className="member-name">
                  <b>{m.display_name}</b>
                  <span className="muted small">{rankName(data, m.rank_id)}</span>
                </span>
                <span className="member-main">{main ? <CharLine c={main} region={data.guild.region} links={false} /> : <span className="muted">No characters yet</span>}</span>
                <span className="member-alts">
                  {others.map((c) => (
                    <span key={c.id} className="alt-chip" title={`${c.name}: ${c.spec}`}>
                      <i style={{ background: CLASSES.find((x) => x.id === c.class_id)?.color }} />{c.name}
                    </span>
                  ))}
                </span>
                <span className="member-time muted small" title={m.timezone}>{localTimeIn(m.timezone)} their time</span>
              </button>
              {isOpen && (
                <div className="member-body">
                  <ul className="char-list">
                    {chars.map((c) => (
                      <li key={c.id}>
                        <CharLine c={c} region={data.guild.region} />
                        {c.is_main && <span className="tag">Main</span>}
                        <span className="muted small"> {c.realm}</span>
                        {c.note && <div className="muted small">{c.note}</div>}
                      </li>
                    ))}
                  </ul>
                  <p className="muted small">
                    Discord: {m.discord_name} · Joined {new Date(m.joined_at + 'T12:00').toLocaleDateString()} · {m.timezone.replace(/_/g, ' ')}
                  </p>
                  {m.about && <p>{m.about}</p>}
                  {viewer?.isOfficer && <a className="button small" href={`#/me/${m.id}`}>Edit {m.display_name}</a>}
                </div>
              )}
            </article>
          )
        })}
      </div>
    </section>
  )
}
