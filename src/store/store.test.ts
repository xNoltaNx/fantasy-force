import { describe, expect, it } from 'vitest'
import type { ImportedCharacter } from '../addonFile'
import type { Character } from '../types'
import { mergeImport } from './store'

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
    const [row] = mergeImport([existing({ professions: [{ name: 'Mining', skill: 280, max: 300, recipes: ['Smelt Thorium'] }] })], 'm1',
      [imported({ professions: [{ name: 'Mining', skill: 300, max: 300 }] })])
    expect(row!.professions).toEqual([{ name: 'Mining', skill: 300, max: 300, recipes: ['Smelt Thorium'] }])
  })

  it('makes the first new character the main only when there is none', () => {
    expect(mergeImport([], 'm1', [imported({}), imported({ name: 'Alt' })]).map((r) => r.is_main)).toEqual([true, false])
    expect(mergeImport([existing({ name: 'Other' })], 'm1', [imported({})])[0]!.is_main).toBe(false)
  })
})
