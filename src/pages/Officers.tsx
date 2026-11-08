import { useState } from 'react'
import { useApp } from '../app'
import { Avatar, CharLine, charsOf } from '../bits'
import { store } from '../store'
import type { Member, Rank } from '../types'

export function Officers() {
  const { data, viewer } = useApp()
  if (!viewer?.isOfficer) return <p className="muted">Only officers can see this page.</p>
  const ranks = [...data.ranks].sort((a, b) => a.sort - b.sort)
  const pending = data.members.filter((m) => m.rank_id === null)
  const members = data.members
    .filter((m) => m.rank_id !== null)
    .sort((a, b) => ranks.findIndex((r) => r.id === a.rank_id) - ranks.findIndex((r) => r.id === b.rank_id) || a.display_name.localeCompare(b.display_name))

  return (
    <section>
      <div className="card">
        <h2>Waiting for approval {pending.length > 0 && <span className="count">{pending.length}</span>}</h2>
        {pending.length === 0 && <p className="muted">Nobody waiting. New people appear here after they sign in with Discord.</p>}
        {pending.map((m) => <PendingRow key={m.id} m={m} ranks={ranks} />)}
      </div>

      <div className="card">
        <h2>Members</h2>
        <p className="muted small">Only officers see the notes here.</p>
        <div className="officer-table">
          {members.map((m) => <MemberRow key={m.id} m={m} ranks={ranks} />)}
        </div>
      </div>

      <RanksCard ranks={ranks} />
      <GuildCard />
    </section>
  )
}

function PendingRow({ m, ranks }: { m: Member; ranks: Rank[] }) {
  const { data, act } = useApp()
  const lowest = ranks.filter((r) => !r.is_officer).at(-1)
  const [rank, setRank] = useState(lowest?.id ?? ranks[0]?.id)
  const main = charsOf(data, m.id)[0]
  return (
    <div className="pending">
      <Avatar m={m} />
      <span><b>{m.display_name}</b> <span className="muted small">{m.discord_name}</span></span>
      <span>{main ? <CharLine c={main} region={data.guild.region} /> : <span className="muted">No characters yet</span>}</span>
      {m.about && <span className="muted small">“{m.about}”</span>}
      <span className="row">
        <select value={rank} onChange={(e) => setRank(Number(e.target.value))} aria-label="Rank">
          {ranks.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
        </select>
        <button className="button small" onClick={() => act(() => store.updateMember(m.id, { rank_id: rank, joined_at: new Date().toISOString().slice(0, 10) }))}>Approve</button>
        <button className="button ghost small" onClick={() => confirm(`Turn ${m.display_name} away? Their characters are removed too.`) && act(() => store.removeMember(m.id))}>Turn away</button>
      </span>
    </div>
  )
}

function MemberRow({ m, ranks }: { m: Member; ranks: Rank[] }) {
  const { data, viewer, act } = useApp()
  const saved = data.officerNotes.find((n) => n.member_id === m.id)?.note ?? ''
  const [note, setNote] = useState(saved)
  const main = charsOf(data, m.id)[0]
  const isMe = m.id === viewer?.id
  return (
    <div className="officer-row">
      <span className="officer-who">
        <Avatar m={m} size={28} />
        <span><b>{m.display_name}</b><br />{main ? <CharLine c={main} region={data.guild.region} links={false} /> : <span className="muted small">No characters</span>}</span>
      </span>
      <select value={m.rank_id ?? ''} disabled={isMe} title={isMe ? "You can't change your own rank" : undefined}
        onChange={(e) => act(() => store.updateMember(m.id, { rank_id: Number(e.target.value) }))} aria-label="Rank">
        {ranks.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
      </select>
      <input type="date" value={m.joined_at} onChange={(e) => act(() => store.updateMember(m.id, { joined_at: e.target.value }))} aria-label="Joined" title="Joined" />
      <textarea rows={2} placeholder="Officer note" value={note} onChange={(e) => setNote(e.target.value)}
        onBlur={() => note !== saved && act(() => store.saveOfficerNote(m.id, note))} />
      <span className="row">
        <a className="button ghost small" href={`#/me/${m.id}`}>Characters</a>
        {!isMe && <button className="button ghost small" onClick={() => confirm(`Remove ${m.display_name} from the guild site? Their characters, week and sign-ups go too.`) && act(() => store.removeMember(m.id))}>Remove</button>}
      </span>
    </div>
  )
}

function RanksCard({ ranks }: { ranks: Rank[] }) {
  const { data, act } = useApp()
  const [name, setName] = useState('')
  return (
    <div className="card">
      <h2>Ranks</h2>
      <p className="muted small">Top to bottom. Officer ranks can approve people, edit anyone, post events and read officer notes.</p>
      {ranks.map((r, i) => {
        const used = data.members.filter((m) => m.rank_id === r.id).length
        return (
          <div className="rank-row" key={r.id}>
            <input defaultValue={r.name} onBlur={(e) => e.target.value.trim() && e.target.value !== r.name && act(() => store.saveRank({ ...r, name: e.target.value.trim() }))} aria-label="Rank name" />
            <label className="check"><input type="checkbox" checked={r.is_officer} onChange={(e) => act(() => store.saveRank({ ...r, is_officer: e.target.checked }))} /> Officer</label>
            <span className="muted small">{used} {used === 1 ? 'member' : 'members'}</span>
            <button className="button ghost small" disabled={i === 0} onClick={() => act(async () => {
              await store.saveRank({ ...r, sort: ranks[i - 1].sort })
              await store.saveRank({ ...ranks[i - 1], sort: r.sort })
            })} title="Move up">↑</button>
            <button className="button ghost small" disabled={used > 0} title={used > 0 ? 'Move its members to another rank first' : 'Delete rank'}
              onClick={() => act(() => store.deleteRank(r.id))}>Delete</button>
          </div>
        )
      })}
      <div className="row">
        <input placeholder="New rank" value={name} onChange={(e) => setName(e.target.value)} />
        <button className="button small" disabled={!name.trim()} onClick={async () => {
          if (await act(() => store.saveRank({ name: name.trim(), sort: Math.max(0, ...ranks.map((r) => r.sort)) + 1, is_officer: false }))) setName('')
        }}>Add rank</button>
      </div>
    </div>
  )
}

function GuildCard() {
  const { data, act } = useApp()
  const [g, setG] = useState(data.guild)
  const dirty = JSON.stringify(g) !== JSON.stringify(data.guild)
  return (
    <div className="card form">
      <h2>Guild</h2>
      <div className="row">
        <label>Name <input value={g.name} onChange={(e) => setG({ ...g, name: e.target.value })} /></label>
        <label>Home realm <input value={g.realm} onChange={(e) => setG({ ...g, realm: e.target.value })} /></label>
        <label>Region
          <select value={g.region} onChange={(e) => setG({ ...g, region: e.target.value })}>
            <option value="us">Americas and Oceania</option>
            <option value="eu">Europe</option>
            <option value="kr">Korea</option>
            <option value="tw">Taiwan</option>
          </select>
        </label>
      </div>
      <label>Shown under the guild name <textarea rows={2} value={g.about} onChange={(e) => setG({ ...g, about: e.target.value })} /></label>
      <div className="row"><button className="button" disabled={!dirty} onClick={() => act(() => store.updateGuild(g))}>Save guild</button></div>
    </div>
  )
}
