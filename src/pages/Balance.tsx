import { useState } from 'react'
import { useApp } from '../app'
import { RoleIcon } from '../bits'
import { CLASSES, ROLES } from '../wow'

// How the guild's classes and roles stack up: mains solid, alts lighter, so gaps are easy to see.

export function Balance() {
  const { data } = useApp()
  const [rankFilter, setRankFilter] = useState('')
  const approved = new Set(data.members.filter((m) => m.rank_id !== null && (!rankFilter || String(m.rank_id) === rankFilter)).map((m) => m.id))
  const chars = data.characters.filter((c) => approved.has(c.member_id))
  const mains = chars.filter((c) => c.is_main)
  const alts = chars.filter((c) => !c.is_main)

  const byClass = CLASSES.map((cls) => ({
    cls,
    mains: mains.filter((c) => c.class_id === cls.id).length,
    alts: alts.filter((c) => c.class_id === cls.id).length,
  }))
  const most = Math.max(1, ...byClass.map((r) => r.mains + r.alts))
  const missing = byClass.filter((r) => r.mains === 0).map((r) => r.cls.name)

  // A player "can play" a role if any of their characters fills it.
  const canPlay = ROLES.map((r) => ({
    role: r,
    mains: mains.filter((c) => c.role === r.id).length,
    players: new Set(chars.filter((c) => c.role === r.id).map((c) => c.member_id)).size,
  }))

  return (
    <section>
      <div className="filters">
        <select value={rankFilter} onChange={(e) => setRankFilter(e.target.value)} aria-label="Rank">
          <option value="">Every rank</option>
          {[...data.ranks].sort((a, b) => a.sort - b.sort).map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
        </select>
      </div>

      <h2>Roles</h2>
      <div className="tiles">
        {canPlay.map(({ role, mains, players }) => (
          <div className="tile" key={role.id}>
            <div className="tile-label"><RoleIcon role={role.id} /> {role.name}</div>
            <div className="tile-number">{mains}</div>
            <div className="muted small">mains · {players} players can play it</div>
          </div>
        ))}
      </div>

      <h2>Classes</h2>
      <div className="legend small">
        <span><i className="swatch" /> Mains</span>
        <span><i className="swatch swatch-alt" /> Alts</span>
      </div>
      <div className="bars" role="table" aria-label="Characters by class">
        {byClass.map(({ cls, mains, alts }) => (
          <div className="bar-row" role="row" key={cls.id} title={`${cls.name}: ${mains} mains, ${alts} alts`}>
            <span className="bar-label" role="cell">{cls.name}</span>
            <span className="bar-track" role="cell">
              {mains > 0 && <span className="bar" style={{ width: `${(mains / most) * 100}%`, background: cls.color }} />}
              {alts > 0 && <span className="bar bar-alt" style={{ width: `${(alts / most) * 100}%`, background: cls.color }} />}
            </span>
            <span className="bar-value" role="cell">{mains}{alts ? <span className="muted"> + {alts}</span> : null}</span>
          </div>
        ))}
      </div>
      {missing.length > 0 && <p className="muted">No mains yet: {missing.join(', ')}.</p>}
    </section>
  )
}
