import { describe, expect, it } from 'vitest'
import { bestTimes, localCellToUtcSlot, localGrid, zoneChoices, zoneToAdopt } from './week'

describe('zoneChoices', () => {
  it('puts your own and the common zones first, and every list holds UTC and the current pick', () => {
    const { common, all } = zoneChoices('America/Chicago', 'Africa/Abidjan', ['Africa/Abidjan', 'America/Chicago', 'Europe/Paris'])
    expect(common[0]).toBe('America/Chicago')
    expect(common).toContain('America/Los_Angeles')
    expect(new Set(common).size).toBe(common.length)
    expect([...common, ...all]).toContain('UTC')
    expect(all).toContain('Africa/Abidjan')
    expect(all.filter((z) => common.includes(z))).toEqual([])
  })
})

describe('zoneToAdopt', () => {
  it('takes the browser\'s time zone over the UTC a new member starts with, once', () => {
    expect(zoneToAdopt('UTC', 'America/Los_Angeles', false)).toBe('America/Los_Angeles')
    expect(zoneToAdopt('UTC', 'America/Los_Angeles', true)).toBeNull() // adopted before: a later UTC was picked on purpose
    expect(zoneToAdopt('Europe/Berlin', 'America/Los_Angeles', false)).toBeNull() // one already chosen stays
    expect(zoneToAdopt('UTC', 'UTC', false)).toBeNull()
    expect(zoneToAdopt('Africa/Abidjan', 'America/Los_Angeles', false)).toBe('America/Los_Angeles') // the old picker's mistake
  })
})

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
