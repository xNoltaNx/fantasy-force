import { useEffect, useMemo, useRef, useState } from 'react'
import { useApp } from '../app'
import { store } from '../store'
import { bestTimes, DAYS, hourLabel, localGrid, myTimeZone } from '../week'

export function Availability() {
  const { data, viewer } = useApp()
  const grid = useMemo(() => localGrid(), [])
  const [rankFilter, setRankFilter] = useState('')

  const people = data.members.filter((m) => m.rank_id !== null && (!rankFilter || String(m.rank_id) === rankFilter))
  const ids = new Set(people.map((m) => m.id))
  const rows = data.availability.filter((a) => ids.has(a.member_id))
  const whoAt = (slot: number) => rows.filter((a) => a.slots.includes(slot)).map((a) => people.find((m) => m.id === a.member_id)!.display_name)
  const counts = grid.map((day) => day.map((slot) => whoAt(slot).length))
  const most = Math.max(1, ...counts.flat())
  const best = bestTimes(counts)

  return (
    <section>
      {viewer?.member && <MyWeek grid={grid} memberId={viewer.member.id} />}

      <h2>When the guild plays</h2>
      <div className="filters">
        <select value={rankFilter} onChange={(e) => setRankFilter(e.target.value)} aria-label="Rank">
          <option value="">Every rank</option>
          {[...data.ranks].sort((a, b) => a.sort - b.sort).map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
        </select>
        <span className="muted small">Times in your time zone ({myTimeZone().replace(/_/g, ' ')}) · {rows.length} of {people.length} members have filled in their week</span>
      </div>
      {best.length > 0 && (
        <div className="tiles">
          {best.map((b, i) => (
            <div className="tile" key={i}>
              <div className="tile-label">{i === 0 ? 'Best raid time' : 'Also good'}</div>
              <div className="tile-number small-number">{DAYS[b.day]} {hourLabel(b.hour)} to {hourLabel((b.hour + 3) % 24)}</div>
              <div className="muted small">{b.players} players free all 3 hours</div>
            </div>
          ))}
        </div>
      )}
      <WeekGrid
        cell={(day, hour) => {
          const n = counts[day][hour]
          const names = whoAt(grid[day][hour])
          return {
            style: { background: n ? `rgba(94, 160, 255, ${0.15 + 0.85 * (n / most)})` : undefined },
            title: `${DAYS[day]} ${hourLabel(hour)}: ${n} free${names.length ? '\n' + names.join(', ') : ''}`,
            label: n ? String(n) : '',
          }
        }}
      />
    </section>
  )
}

function MyWeek({ grid, memberId }: { grid: number[][]; memberId: string }) {
  const { data, act } = useApp()
  const saved = data.availability.find((a) => a.member_id === memberId)?.slots ?? []
  const [slots, setSlots] = useState(() => new Set(saved))
  const paint = useRef<boolean | null>(null)
  const dirty = saved.length !== slots.size || saved.some((s) => !slots.has(s))

  useEffect(() => {
    const up = () => (paint.current = null)
    window.addEventListener('pointerup', up)
    return () => window.removeEventListener('pointerup', up)
  }, [])

  const set = (slot: number, on: boolean) => setSlots((prev) => {
    const next = new Set(prev)
    if (on) next.add(slot)
    else next.delete(slot)
    return next
  })

  return (
    <div className="card">
      <h2>My usual week</h2>
      <p className="muted small">Click or drag over the hours you usually play. Everyone sees them in their own time zone.</p>
      <WeekGrid
        cell={(day, hour) => {
          const slot = grid[day][hour]
          const on = slots.has(slot)
          return {
            className: on ? 'on' : '',
            title: `${DAYS[day]} ${hourLabel(hour)}`,
            onPointerDown: (e: React.PointerEvent) => { e.preventDefault(); paint.current = !on; set(slot, !on) },
            onPointerEnter: () => { if (paint.current !== null) set(slot, paint.current) },
          }
        }}
      />
      <div className="row">
        <button className="button" disabled={!dirty} onClick={() => act(() => store.saveAvailability(memberId, [...slots].sort((a, b) => a - b)))}>Save my week</button>
        <button className="button ghost" disabled={!dirty} onClick={() => setSlots(new Set(saved))}>Undo changes</button>
        <button className="button ghost" onClick={() => setSlots(new Set())}>Clear</button>
      </div>
    </div>
  )
}

type CellProps = {
  className?: string
  style?: React.CSSProperties
  title?: string
  label?: string
  onPointerDown?: (e: React.PointerEvent) => void
  onPointerEnter?: () => void
}

function WeekGrid({ cell }: { cell: (day: number, hour: number) => CellProps }) {
  return (
    <div className="week" role="grid">
      <span />
      {Array.from({ length: 24 }, (_, h) => <span key={h} className="week-hour">{h % 3 === 0 ? hourLabel(h) : ''}</span>)}
      {DAYS.map((d, day) => (
        <Row key={d} day={day} name={d} cell={cell} />
      ))}
    </div>
  )
}

function Row({ day, name, cell }: { day: number; name: string; cell: (day: number, hour: number) => CellProps }) {
  return (
    <>
      <span className="week-day">{name}</span>
      {Array.from({ length: 24 }, (_, hour) => {
        const { label, className, ...rest } = cell(day, hour)
        return <span key={hour} className={`week-cell ${className ?? ''}`} {...rest}>{label}</span>
      })}
    </>
  )
}
