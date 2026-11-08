// Availability is stored as UTC hour-of-week (0 = Monday 00:00 UTC). The grid is drawn in the viewer's own time zone.

export const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

/** The Monday 00:00 (local) of the current week, so daylight saving follows this week's offset. */
function localMonday(now = new Date()): Date {
  const d = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const back = (d.getDay() + 6) % 7
  d.setDate(d.getDate() - back)
  return d
}

/** Local grid cell (day 0-6 from Monday, hour 0-23) to the stored UTC hour-of-week. */
export function localCellToUtcSlot(day: number, hour: number, now = new Date()): number {
  const m = localMonday(now)
  const d = new Date(m.getFullYear(), m.getMonth(), m.getDate() + day, hour)
  return ((d.getUTCDay() + 6) % 7) * 24 + d.getUTCHours()
}

/** Every local cell as its UTC slot, [day][hour]. */
export function localGrid(now = new Date()): number[][] {
  return DAYS.map((_, day) => Array.from({ length: 24 }, (_, hour) => localCellToUtcSlot(day, hour, now)))
}

export function hourLabel(hour: number): string {
  const h = hour % 12 === 0 ? 12 : hour % 12
  return `${h}${hour < 12 ? 'am' : 'pm'}`
}

/** The best runs of at least `length` hours by how many players are free in every hour of the run. */
export function bestTimes(counts: number[][], length = 3, top = 3): { day: number; hour: number; players: number }[] {
  const runs: { day: number; hour: number; players: number }[] = []
  counts.forEach((row, day) => {
    for (let hour = 0; hour + length <= 24; hour++) {
      runs.push({ day, hour, players: Math.min(...row.slice(hour, hour + length)) })
    }
  })
  runs.sort((a, b) => b.players - a.players || a.day - b.day || a.hour - b.hour)
  const picked: typeof runs = []
  for (const r of runs) {
    if (r.players === 0) break
    if (picked.some((p) => p.day === r.day && Math.abs(p.hour - r.hour) < length)) continue
    picked.push(r)
    if (picked.length === top) break
  }
  return picked
}

export function localTimeIn(timezone: string, now = new Date()): string {
  try {
    return now.toLocaleTimeString([], { timeZone: timezone, hour: 'numeric', minute: '2-digit' })
  } catch {
    return ''
  }
}

export function allTimeZones(): string[] {
  const intl = Intl as unknown as { supportedValuesOf?: (k: string) => string[] }
  return intl.supportedValuesOf ? intl.supportedValuesOf('timeZone') : ['UTC']
}

export function myTimeZone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'
}
