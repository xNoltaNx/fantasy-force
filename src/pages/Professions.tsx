import { useState } from 'react'
import { useApp } from '../app'
import { memberName } from '../bits'
import { classById, PROFESSIONS } from '../wow'

// Who in the guild has which profession, highest skill first: the place to find a crafter.
export function Professions() {
  const { data } = useApp()
  const [mainsOnly, setMainsOnly] = useState(false)
  const approved = new Set(data.members.filter((m) => m.rank_id !== null).map((m) => m.id))
  const chars = data.characters.filter((c) => approved.has(c.member_id) && (!mainsOnly || c.is_main))
  const names = [...new Set([...PROFESSIONS, ...chars.flatMap((c) => c.professions.map((p) => p.name))])]
  const groups = names
    .map((name) => ({
      name,
      people: chars.flatMap((c) => c.professions.filter((p) => p.name === name).map((p) => ({ c, p })))
        .sort((a, b) => b.p.skill - a.p.skill),
    }))
    .filter((g) => g.people.length)

  return (
    <section>
      <div className="filters">
        <label className="check"><input type="checkbox" checked={mainsOnly} onChange={(e) => setMainsOnly(e.target.checked)} /> Mains only</label>
        <span className="muted small">From the addon, or added by hand on My characters.</span>
      </div>
      {groups.length === 0 && <p className="muted">No professions yet. They arrive when members bring in their characters from the addon.</p>}
      <div className="prof-grid">
        {groups.map((g) => (
          <div className="card prof-card" key={g.name}>
            <h2>{g.name} <span className="muted small">{g.people.length}</span></h2>
            <ul>
              {g.people.map(({ c, p }) => (
                <li key={c.id} title={`${c.name} (${memberName(data, c.member_id)}): ${p.skill} of ${p.max || 300}`}>
                  <span className="prof-who">
                    <b className="cls-name" style={{ '--cls': classById(c.class_id)?.color } as React.CSSProperties}>{c.name}</b>
                    <span className="muted small"> {memberName(data, c.member_id)}</span>
                  </span>
                  <span className="skill-bar"><span style={{ width: `${Math.min(100, (p.skill / 300) * 100)}%` }} /></span>
                  <span className="skill">{p.skill}</span>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </section>
  )
}
