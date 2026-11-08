import { useState } from 'react'
import { useApp } from '../app'
import { GameLink } from '../wowhead'

export function gold(copper: number): string {
  const g = Math.floor(copper / 10000), s = Math.floor((copper % 10000) / 100), c = copper % 100
  return [g ? `${g.toLocaleString()}g` : '', s ? `${s}s` : '', !g && !s ? `${c}c` : ''].filter(Boolean).join(' ')
}

// The guild bank (or the bank alt's bags and bank), searchable, as an officer's addon last recorded it.
export function Bank() {
  const { data, viewer } = useApp()
  const [q, setQ] = useState('')
  const [tab, setTab] = useState('')
  const b = data.bank
  if (!viewer?.isApproved) return <p className="muted">Sign in as a guild member to see the bank.</p>
  if (!b) {
    return (
      <div className="card">
        <h2>Guild bank</h2>
        <p className="muted">Nothing here yet. The bank alt (or an officer at the guild bank) runs the Fantasy Force addon; an officer then drops its file on My characters and presses "Update the guild bank".</p>
      </div>
    )
  }
  const needle = q.trim().toLowerCase()
  const tabs = b.tabs.filter((t) => !tab || t.name === tab)
  const total = b.tabs.reduce((n, t) => n + t.items.length, 0)
  const when = new Date(b.updated_at)
  return (
    <section>
      <div className="tiles">
        {b.money != null && <div className="tile"><div className="tile-label">Gold</div><div className="tile-number small-number">{gold(b.money)}</div></div>}
        <div className="tile"><div className="tile-label">Kinds of item</div><div className="tile-number small-number">{total}</div></div>
        <div className="tile"><div className="tile-label">{b.source === 'guild' ? 'Guild bank' : 'Bank alt'}</div><div className="tile-number small-number">{b.recorded_by}</div>
          <div className="muted small">Updated {when.toLocaleDateString([], { month: 'short', day: 'numeric' })}, {when.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}</div></div>
      </div>
      <div className="filters">
        <input placeholder="Search the bank" value={q} onChange={(e) => setQ(e.target.value)} />
        <div className="segmented">
          <button className={!tab ? 'on' : ''} onClick={() => setTab('')}>All</button>
          {b.tabs.map((t) => <button key={t.name} className={tab === t.name ? 'on' : ''} onClick={() => setTab(t.name)}>{t.name}</button>)}
        </div>
      </div>
      {tabs.map((t) => {
        const items = t.items.filter((i) => !needle || i.name.toLowerCase().includes(needle)).sort((a, b2) => a.name.localeCompare(b2.name))
        if (!items.length) return null
        return (
          <div className="card" key={t.name}>
            <h2>{t.name} <span className="muted small">{items.length}</span></h2>
            <ul className="bank-grid">
              {items.map((i) => (
                <li key={i.id || i.name} className={`q${i.quality}`}>
                  <GameLink name={i.name} item={i.id || undefined} />
                  <span className="bank-count">× {i.count.toLocaleString()}</span>
                </li>
              ))}
            </ul>
          </div>
        )
      })}
      <p className="muted small">Want something? Ask an officer in Discord or whisper the bank alt.</p>
    </section>
  )
}
