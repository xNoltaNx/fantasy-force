import { describe, expect, it } from 'vitest'
import type { ImportedKos } from './addonFile'
import { kosInput, marksToSend, sentKey } from './kosAuto'
import { seedData } from './store/seed'

const data = seedData()
const me = data.characters.find((c) => c.member_id === 'm1')!
const other = data.characters.find((c) => c.member_id !== 'm1')!
const now = Math.floor(Date.now() / 1000)
const since = now - 3600
const mark = (o: Partial<ImportedKos>): ImportedKos => ({
  name: 'Gankalot', level: 44, race: 'human', class_id: 'rogue', guild: 'Bad Guys', reason: 'Camped the flight master', by: me.name, added: now - 60, ...o,
})
const send = (marks: ImportedKos[], sent: string[] = []) => marksToSend(marks, data, 'm1', since, sent).map((k) => k.name)

describe('marks made in game, sent to Discord by themselves', () => {
  it('sends a new mark the member made', () => {
    expect(send([mark({})])).toEqual(['Gankalot'])
    expect(send([mark({ by: `${me.name.toUpperCase()}-Some Realm` })])).toEqual(['Gankalot'])
  })
  it("leaves guildmates' marks and marks from before it began", () => {
    expect(send([mark({ by: other.name })])).toEqual([])
    expect(send([mark({ added: since - 1 })])).toEqual([])
  })
  it('sends each mark once', () => {
    expect(send([mark({})], [sentKey(mark({}))])).toEqual([])
    expect(send([mark({ added: now - 10 })], [sentKey(mark({}))])).toEqual(['Gankalot']) // marked again later
  })
  it('skips names the site has: active, or made or cleared since the mark', () => {
    expect(send([mark({ name: 'itz  shifty' })])).toEqual([]) // active on the site
    // Mooncrash was cleared 30 hours ago: an older addon mark stays cleared, a newer one goes out
    expect(marksToSend([mark({ name: 'Mooncrash', added: now - 40 * 3600 })], data, 'm1', 0, []).map((k) => k.name)).toEqual([])
    expect(send([mark({ name: 'Mooncrash' })])).toEqual(['Mooncrash'])
  })
  it('turns into a site mark with a middling threat', () => {
    expect(kosInput(mark({}))).toEqual({ name: 'Gankalot', level: 44, race: 'human', class_id: 'rogue', guild: 'Bad Guys', zone: '', reason: 'Camped the flight master', danger: 2 })
  })
})
