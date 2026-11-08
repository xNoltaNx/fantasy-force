import { describe, expect, it } from 'vitest'
import type { ImportedCharacter } from '../addonFile'
import type { Character } from '../types'
import { mergeImport, mergeRaid } from './store'
import type { Raid } from '../types'

describe('mergeRaid', () => {
  const night = (o: Partial<Raid>): Raid => ({
    key: 'Molten Core 2026-11-10', zone: 'Molten Core', started_at: '2026-11-11T03:00:00.000Z', ended_at: '2026-11-11T05:00:00.000Z',
    recorded_by: 'A', attendees: ['A', 'B'], bosses: [{ name: 'Lucifron', killed_at: '2026-11-11T03:20:00.000Z', attendees: ['A', 'B'] }],
    loot: [{ item_id: 1, name: 'Boots', quality: 4, to: 'B', at: '2026-11-11T03:21:00.000Z', boss: 'Lucifron' }], ...o,
  })

  it('joins two recordings of one night: everyone seen, every boss, loot once', () => {
    const m = mergeRaid(night({}), night({
      recorded_by: 'C', attendees: ['A', 'C'], started_at: '2026-11-11T02:50:00.000Z', ended_at: '2026-11-11T05:30:00.000Z',
      bosses: [{ name: 'Lucifron', killed_at: '2026-11-11T03:20:00.000Z', attendees: ['A', 'C'] }, { name: 'Magmadar', killed_at: '2026-11-11T03:50:00.000Z', attendees: ['A', 'C'] }],
      loot: [{ item_id: 1, name: 'Boots', quality: 4, to: 'B', at: '2026-11-11T03:21:00.000Z', boss: 'Lucifron' }, { item_id: 2, name: 'Helm', quality: 4, to: 'C', at: '2026-11-11T03:51:00.000Z', boss: 'Magmadar' }],
    }))
    expect(m.attendees).toEqual(['A', 'B', 'C'])
    expect(m.started_at).toBe('2026-11-11T02:50:00.000Z')
    expect(m.ended_at).toBe('2026-11-11T05:30:00.000Z')
    expect(m.bosses.map((b) => [b.name, b.attendees])).toEqual([['Lucifron', ['A', 'B', 'C']], ['Magmadar', ['A', 'C']]])
    expect(m.loot.map((l) => l.name)).toEqual(['Boots', 'Helm'])
  })
})

const imported = (o: Partial<ImportedCharacter>): ImportedCharacter => ({
  name: 'Grukka Stonefist', level: 60, class_id: 'warrior', race: 'orc', spec: 'Arms', role: 'dps',
  professions: [], inGuild: true, guild: 'Fantasy Force', ...o,
})
const existing = (o: Partial<Character>): Character => ({
  id: 'c1', member_id: 'm1', name: 'Grukka Stonefist', race: 'orc', class_id: 'warrior', spec: 'Protection', role: 'tank',
  is_main: true, level: 58, professions: [], note: 'raid tank', ...o,
})

describe('mergeImport', () => {
  it('updates a character by name, keeping its id, main and note, taking the game\'s level, spec and professions', () => {
    const [row] = mergeImport([existing({})], 'm1', [imported({ name: 'grukka stonefist', professions: [{ name: 'Mining', skill: 300, max: 300 }] })])
    expect(row).toMatchObject({ id: 'c1', is_main: true, note: 'raid tank', level: 60, spec: 'Arms', role: 'dps' })
    expect(row!.professions).toHaveLength(1)
  })

  it('keeps a bear or cat pick made on the site, since the game only says Feral', () => {
    const [row] = mergeImport([existing({ class_id: 'druid', spec: 'Feral (bear)', role: 'tank' })], 'm1',
      [imported({ class_id: 'druid', spec: 'Feral (cat)', role: 'dps' })])
    expect(row).toMatchObject({ spec: 'Feral (bear)', role: 'tank' })
  })

  it('keeps recipes already on the site when the file has none for that profession', () => {
    const [row] = mergeImport([existing({ professions: [{ name: 'Mining', skill: 280, max: 300, recipes: [{ name: 'Smelt Thorium' }] }] })], 'm1',
      [imported({ professions: [{ name: 'Mining', skill: 300, max: 300 }] })])
    expect(row!.professions).toEqual([{ name: 'Mining', skill: 300, max: 300, recipes: [{ name: 'Smelt Thorium' }] }])
  })

  it('makes the first new character the main only when there is none', () => {
    expect(mergeImport([], 'm1', [imported({}), imported({ name: 'Alt' })]).map((r) => r.is_main)).toEqual([true, false])
    expect(mergeImport([existing({ name: 'Other' })], 'm1', [imported({})])[0]!.is_main).toBe(false)
  })

  it('with no main yet, picks the highest level, as the addon does', () => {
    expect(mergeImport([], 'm1', [imported({ name: 'Low', level: 20 }), imported({ name: 'High', level: 60 })])
      .map((r) => r.is_main)).toEqual([false, true])
  })

  it('takes the main chosen in game with /ff main over the site\'s', () => {
    const rows = mergeImport([existing({})], 'm1', [imported({}), imported({ name: 'Alt', main: true })])
    expect(rows.map((r) => r.is_main)).toEqual([false, true])
  })
})
