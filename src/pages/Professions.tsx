import { useState } from 'react'
import { useApp } from '../app'
import { memberName } from '../bits'
import type { Character, Profession } from '../types'
import { classById, PROFESSIONS } from '../wow'

// Who in the guild has which profession, highest skill first, and who can make a given recipe:
// the place to find a crafter.
export function Professions() {
  const { data } = useApp()
  const [mainsOnly, setMainsOnly] = useState(false)
  const [q, setQ] = useState('')
  const [open, setOpen] = useState<string | null>(null)
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
  const anyRecipes = chars.some((c) => c.professions.some((p) => p.recipes?.length))

  const needle = q.trim().toLowerCase()
  const matches = new Map<string, { c: Character; p: Profession }[]>()
  if (needle.length >= 2) {
    for (const c of chars) for (const p of c.professions) for (const r of p.recipes ?? []) {
      if (r.toLowerCase().includes(needle)) matches.set(r, [...(matches.get(r) ?? []), { c, p }])
    }
  }
  const found = [...matches.entries()].sort((a, b) => a[0].localeCompare(b[0]))

  return (
    <section>
      <div className="filters">
        <input className="recipe-search" placeholder="Who can make… (a recipe, like Arcanite Reaper)" value={q} onChange={(e) => setQ(e.target.value)} />
        <label className="check"><input type="checkbox" checked={mainsOnly} onChange={(e) => setMainsOnly(e.target.checked)} /> Mains only</label>
      </div>

      {needle.length >= 2 && (
        <div className="card recipe-results">
          {found.length === 0 && <p className="muted">{anyRecipes ? `Nobody has a recipe matching "${q.trim()}" yet.` : 'No recipes yet: they arrive when members open their profession windows with the addon on.'}</p>}
          {found.slice(0, 40).map(([recipe, who]) => (
            <div className="recipe-row" key={recipe}>
              <b>{recipe}</b>
              <span className="recipe-who">
                {who.map(({ c, p }) => (
                  <span key={c.id} className="alt-chip" title={`${p.name} ${p.skill}`}>
                    <i style={{ background: classById(c.class_id)?.color }} />{c.name}<span className="muted"> {memberName(data, c.member_id)}</span>
                  </span>
                ))}
              </span>
            </div>
          ))}
          {found.length > 40 && <p className="muted small">{found.length - 40} more: type more of the name.</p>}
        </div>
      )}

      {groups.length === 0 && <p className="muted">No professions yet. They arrive when members bring in their characters from the addon.</p>}
      <div className="prof-grid">
        {groups.map((g) => (
          <div className="card prof-card" key={g.name}>
            <h2>{g.name} <span className="muted small">{g.people.length}</span></h2>
            <ul>
              {g.people.map(({ c, p }) => {
                const key = `${c.id}:${p.name}`
                const n = p.recipes?.length ?? 0
                return (
                  <li key={key}>
                    <button className="prof-row" disabled={!n} aria-expanded={open === key} onClick={() => setOpen(open === key ? null : key)}
                      title={`${c.name} (${memberName(data, c.member_id)}): ${p.skill} of ${p.max || 300}${n ? `, ${n} recipes` : ''}`}>
                      <span className="prof-who">
                        <b className="cls-name" style={{ '--cls': classById(c.class_id)?.color } as React.CSSProperties}>{c.name}</b>
                        <span className="muted small"> {n ? `${n} recipes` : memberName(data, c.member_id)}</span>
                      </span>
                      <span className="skill-bar"><span style={{ width: `${Math.min(100, (p.skill / 300) * 100)}%` }} /></span>
                      <span className="skill">{p.skill || ''}</span>
                    </button>
                    {open === key && <ul className="recipe-list">{p.recipes!.map((r) => <li key={r}>{r}</li>)}</ul>}
                  </li>
                )
              })}
            </ul>
          </div>
        ))}
      </div>
    </section>
  )
}
