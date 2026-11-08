import { useState } from 'react'
import { useApp } from '../app'
import { store } from '../store'
import type { GuildLink } from '../types'

// Guild rules, loot policy and handy links. Everyone reads; officers edit in place.
export function Links() {
  const { data, viewer, act } = useApp()
  const [editing, setEditing] = useState(false)
  const g = data.guild
  const [f, setF] = useState({ rules: g.rules, loot_policy: g.loot_policy, links: g.links })
  const setLink = (i: number, l: Partial<GuildLink> | null) => setF({
    ...f, links: l === null ? f.links.filter((_, j) => j !== i) : f.links.map((x, j) => (j === i ? { ...x, ...l } : x)),
  })

  if (editing) {
    return (
      <section className="card form">
        <h2>Edit links and rules</h2>
        <label>Guild rules (one per line) <textarea rows={5} value={f.rules} onChange={(e) => setF({ ...f, rules: e.target.value })} /></label>
        <label>Loot policy <textarea rows={3} value={f.loot_policy} onChange={(e) => setF({ ...f, loot_policy: e.target.value })} /></label>
        <span className="prof-edit-label">Links</span>
        {f.links.map((l, i) => (
          <div className="row link-edit" key={i}>
            <input placeholder="Title" value={l.title} onChange={(e) => setLink(i, { title: e.target.value })} />
            <input placeholder="https://…" value={l.url} onChange={(e) => setLink(i, { url: e.target.value })} />
            <input placeholder="What it's for" value={l.note} onChange={(e) => setLink(i, { note: e.target.value })} />
            <button className="button ghost small" onClick={() => setLink(i, null)}>Remove</button>
          </div>
        ))}
        <div className="row">
          <button className="button ghost small" onClick={() => setF({ ...f, links: [...f.links, { title: '', url: '', note: '' }] })}>Add link</button>
        </div>
        <div className="row" style={{ marginTop: '0.8rem' }}>
          <button className="button" onClick={async () => {
            const links = f.links.filter((l) => l.title.trim() && /^https?:\/\//.test(l.url.trim()))
            if (await act(() => store.updateGuild({ ...g, ...f, links }))) setEditing(false)
          }}>Save</button>
          <button className="button ghost" onClick={() => { setF({ rules: g.rules, loot_policy: g.loot_policy, links: g.links }); setEditing(false) }}>Cancel</button>
        </div>
      </section>
    )
  }

  return (
    <section>
      {viewer?.isOfficer && <div className="row" style={{ justifyContent: 'flex-end', marginBottom: '0.6rem' }}><button className="button ghost small" onClick={() => setEditing(true)}>Edit links and rules</button></div>}
      <div className="link-grid">
        {g.links.map((l) => (
          <a key={l.url} className="card link-card" href={l.url} target="_blank" rel="noreferrer">
            <b>{l.title}</b>
            {l.note && <span className="muted small">{l.note}</span>}
            <span className="link-host small">{(() => { try { return new URL(l.url).host } catch { return l.url } })()}</span>
          </a>
        ))}
      </div>
      {g.rules.trim() && (
        <div className="card">
          <h2>Guild rules</h2>
          <ul className="rules">{g.rules.split('\n').filter((x) => x.trim()).map((x, i) => <li key={i}>{x}</li>)}</ul>
        </div>
      )}
      {g.loot_policy.trim() && (
        <div className="card">
          <h2>Loot policy</h2>
          {g.loot_policy.split('\n').filter((x) => x.trim()).map((x, i) => <p key={i}>{x}</p>)}
        </div>
      )}
    </section>
  )
}
