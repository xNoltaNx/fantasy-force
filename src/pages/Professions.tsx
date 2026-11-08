import { useState } from 'react'
import { useApp } from '../app'
import { memberName } from '../bits'
import type { Character, Profession } from '../types'
import { classById, PROFESSIONS } from '../wow'

type Known = { c: Character; p: Profession }

// Professions: every profession as a chip; pick one (#/professions/Tailoring) to see all the recipes the guild
// knows for it, searchable, and its crafters by skill. With none picked, a search covers every profession.
export function Professions({ pick }: { pick?: string }) {
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
  const current = pick ? groups.find((g) => g.name.toLowerCase() === decodeURIComponent(pick).toLowerCase()) : undefined

  // Every recipe known in the guild (in the picked profession, or all), with who knows it.
  const recipes = new Map<string, Known[]>()
  for (const g of current ? [current] : groups) for (const k of g.people) for (const r of k.p.recipes ?? []) {
    recipes.set(r, [...(recipes.get(r) ?? []), k])
  }
  const needle = q.trim().toLowerCase()
  const showList = !!current || needle.length >= 2
  const found = [...recipes.entries()].filter(([r]) => !needle || r.toLowerCase().includes(needle)).sort((a, b) => a[0].localeCompare(b[0]))
  const anyRecipes = recipes.size > 0

  return (
    <section>
      <nav className="prof-chips" aria-label="Professions">
        <a href="#/professions" className={!current ? 'on' : ''}>All</a>
        {groups.map((g) => (
          <a key={g.name} href={`#/professions/${encodeURIComponent(g.name)}`} className={current?.name === g.name ? 'on' : ''}
            onClick={() => { setQ(''); setOpen(null) }}>{g.name}</a>
        ))}
      </nav>
      <div className="filters">
        <input className="recipe-search" value={q} onChange={(e) => setQ(e.target.value)}
          placeholder={current ? `Search ${current.name} recipes` : 'Who can make… (a recipe, like Arcanite Reaper)'} />
        <label className="check"><input type="checkbox" checked={mainsOnly} onChange={(e) => setMainsOnly(e.target.checked)} /> Mains only</label>
      </div>

      {current && <Crafters g={current} open={open} setOpen={setOpen} />}

      {showList && (
        <div className="card recipe-results">
          <h2>{current ? `${current.name} recipes` : 'Recipes'} <span className="muted small">{found.length}{needle ? ` of ${recipes.size}` : ''}</span></h2>
          {found.length === 0 && <p className="muted">{anyRecipes ? `No recipe matching "${q.trim()}".` : 'No recipes yet: they arrive when members open their profession windows with the addon on.'}</p>}
          {found.map(([recipe, who]) => (
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
        </div>
      )}

      {!current && (
        <>
          {groups.length === 0 && <p className="muted">No professions yet. They arrive when members bring in their characters from the addon.</p>}
          <div className="prof-grid">
            {groups.map((g) => <Crafters key={g.name} g={g} open={open} setOpen={setOpen} link />)}
          </div>
        </>
      )}
    </section>
  )
}

/** A profession's crafters, highest skill first; a row opens that person's recipes. */
function Crafters({ g, open, setOpen, link = false }: { g: { name: string; people: Known[] }; open: string | null; setOpen: (k: string | null) => void; link?: boolean }) {
  const { data } = useApp()
  const count = new Set(g.people.flatMap(({ p }) => p.recipes ?? [])).size
  return (
    <div className="card prof-card">
      <h2>
        {link ? <a className="prof-title" href={`#/professions/${encodeURIComponent(g.name)}`}>{g.name}</a> : g.name}
        <span className="muted small"> {g.people.length} {g.people.length === 1 ? 'crafter' : 'crafters'}{count ? ` · ${count} recipes` : ''}</span>
      </h2>
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
  )
}
