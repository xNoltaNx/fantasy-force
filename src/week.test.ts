import { describe, expect, it } from 'vitest'
import { bestTimes, localCellToUtcSlot, localGrid } from './week'

describe('week', () => {
  it('maps every local cell to a distinct UTC slot', () => {
    const slots = localGrid(new Date(2026, 10, 11)).flat()
    expect(new Set(slots).size).toBe(168)
    expect(Math.min(...slots)).toBe(0)
    expect(Math.max(...slots)).toBe(167)
  })

  it('round-trips the local offset', () => {
    const now = new Date(2026, 10, 11)
    const offsetHours = -now.getTimezoneOffset() / 60
    const slot = localCellToUtcSlot(2, 19, now) // Wednesday 7 pm local
    expect(slot).toBe((((2 * 24 + 19 - offsetHours) % 168) + 168) % 168)
  })

  it('finds the best three-hour runs without overlaps', () => {
    const counts = Array.from({ length: 7 }, () => Array(24).fill(0))
    counts[1].fill(5, 19, 23) // Tue 7-11 pm: 5 players
    counts[3].fill(4, 18, 21) // Thu 6-9 pm: 4 players
    const best = bestTimes(counts)
    expect(best[0]).toEqual({ day: 1, hour: 19, players: 5 })
    expect(best[1]).toEqual({ day: 3, hour: 18, players: 4 })
    expect(best).toHaveLength(2)
  })
})
