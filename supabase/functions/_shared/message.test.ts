import { describe, expect, it } from 'vitest'
import { CLASSES, RACES } from '../../../src/wow'
import {
  bar, buttonReply, CLASS_NAME, customId, eventMessage, eventUrl, kosCommand, kosMessage, kosWho, parseCustomId, plain, RACE_NAME,
  reminderLines, reminderMessage, roleCounts, threat, type EventView, type KosView,
} from './message.ts'

const ID = '0b6f8e2c-1d3a-4c5b-9e7f-112233445566'
const SITE = 'https://xnoltanx.github.io/fantasy-force/'

const event = (o: Partial<EventView> = {}): EventView => ({
  id: ID, title: 'Molten Core', starts_at: '2026-11-11T03:00:00+00:00', duration_minutes: 180,
  description: 'Bring fire resistance.', need_tank: 2, need_healer: 3, need_dps: 15, discord_message_id: null,
  signups: [
    { role: 'tank', status: 'in' }, { role: 'healer', status: 'in' }, { role: 'healer', status: 'in' },
    { role: 'dps', status: 'in' }, { role: 'dps', status: 'maybe' }, { role: 'tank', status: 'out' },
  ],
  ...o,
})

describe('button ids', () => {
  it('round-trips every choice', () => {
    for (const c of ['tank', 'healer', 'dps', 'out'] as const) expect(parseCustomId(customId(ID, c))).toEqual({ eventId: ID, choice: c })
  })

  it('stays inside Discord’s 100 characters', () => {
    expect(customId(ID, 'healer').length).toBeLessThanOrEqual(100)
  })

  it('refuses anything else', () => {
    for (const bad of ['', 'ff', `ff:${ID}`, `ff:${ID}:mage`, `xx:${ID}:tank`, 'ff:e1:tank', `ff:${ID}:tank:extra`]) expect(parseCustomId(bad)).toBeNull()
  })
})

describe('roleCounts', () => {
  it('counts going by role, and maybe and out apart', () => {
    expect(roleCounts(event().signups)).toEqual({ going: { tank: 1, healer: 2, dps: 1 }, maybe: 1, out: 1 })
  })
})

describe('eventMessage', () => {
  const before = Date.parse('2026-11-10T00:00:00Z')

  it('has the title, link, both Discord timestamps, counts, the details quoted and five buttons', () => {
    const m = eventMessage(event({ guild_name: 'Fantasy Force' }), SITE, before)
    const t = Date.parse('2026-11-11T03:00:00Z') / 1000
    const embed = m.embeds[0]!
    expect(embed.title).toBe('Molten Core')
    expect(embed.url).toBe(`${SITE}#/events/${ID}`)
    expect(embed.author.name).toBe('Fantasy Force · Guild event')
    expect(embed.thumbnail.url).toBe(`${SITE}discord/logo.jpg`)
    expect(embed.description).toContain(`<t:${t}:F>`)
    expect(embed.description).toContain(`<t:${t}:R>`)
    expect(embed.description).toContain('3 hours')
    expect(embed.description).toContain('**4** going of 20')
    expect(embed.description).toContain('>>> Bring fire resistance.')
    expect(embed.fields.map((f) => [f.name, f.value.split('\n')[0]])).toEqual([
      ['🛡️ Tank  1/2', '`▰▰▰▰▱▱▱▱`'],
      ['💚 Healer  2/3', '`▰▰▰▰▰▱▱▱`'],
      ['⚔️ DPS  1/15', '`▰▱▱▱▱▱▱▱`'],
    ])
    expect(embed.footer).toEqual({ text: "Maybe 1 · Can't make it 1 · Press a role below to sign up" })
    const buttons = m.components[0]!.components
    expect(buttons.map((b) => b.label)).toEqual(['Tank', 'Healer', 'DPS', "Can't make it", 'Details'])
    expect(buttons.map((b) => ('custom_id' in b ? parseCustomId(b.custom_id)?.choice : b.url))).toEqual(['tank', 'healer', 'dps', 'out', `${SITE}#/events/${ID}`])
    expect(buttons.every((b) => !('disabled' in b) || !b.disabled)).toBe(true)
    expect(m.allowed_mentions).toEqual({ parse: [] })
  })

  it('lists who is going under their role, escaped, and turns mint when every role is filled', () => {
    const signups = [
      { role: 'tank' as const, status: 'in' as const, name: 'Grukka' },
      { role: 'healer' as const, status: 'in' as const, name: 'Mira_Moon' },
      { role: 'dps' as const, status: 'maybe' as const, name: 'Ash' },
    ]
    const m = eventMessage(event({ need_tank: 1, need_healer: 1, need_dps: 0, signups }), SITE, before)
    const embed = m.embeds[0]!
    expect(embed.fields[0]!.value).toBe('`▰▰▰▰▰▰▰▰`\nGrukka')
    expect(embed.fields[1]!.name).toBe('💚 Healer  1/1 ✓')
    expect(embed.fields[1]!.value).toContain('Mira\\_Moon')
    expect(embed.fields[2]!.value).toBe('`▱▱▱▱▱▱▱▱`') // a maybe isn't listed
    expect(embed.color).toBe(0x7fd1b4)
    expect(embed.description).toContain('Roster full')
  })

  it('cuts a long list of names short', () => {
    const signups = Array.from({ length: 15 }, (_, i) => ({ role: 'dps' as const, status: 'in' as const, name: `P${i}` }))
    const value = eventMessage(event({ signups }), SITE, before).embeds[0]!.fields[2]!.value
    expect(value.split('\n')).toHaveLength(14)
    expect(value).toContain('+3 more')
  })

  it('leaves out an empty description', () => {
    const m = eventMessage(event({ description: '  ', signups: [] }), SITE, before)
    expect(m.embeds[0]!.description).not.toContain('>>>')
    expect(m.embeds[0]!.footer.text).toBe('Press a role below to sign up')
  })

  it('greys the post and its buttons out once the event is over', () => {
    const m = eventMessage(event(), SITE, Date.parse('2026-11-11T06:01:00Z'))
    expect(m.components[0]!.components.filter((b) => 'custom_id' in b).every((b) => 'disabled' in b && b.disabled)).toBe(true)
    expect(m.embeds[0]!.color).toBe(0x4f545c)
    expect(m.embeds[0]!.footer.text).toContain('This event is over')
  })
})

describe('bar', () => {
  it('fills by share, shows anyone at all, and is full past the need', () => {
    expect(bar(0, 4)).toBe('▱▱▱▱▱▱▱▱')
    expect(bar(1, 40)).toBe('▰▱▱▱▱▱▱▱')
    expect(bar(2, 4)).toBe('▰▰▰▰▱▱▱▱')
    expect(bar(9, 4)).toBe('▰▰▰▰▰▰▰▰')
    expect(bar(0, 0)).toBe('▱▱▱▱▱▱▱▱')
  })

  it('escapes Discord markdown in what people type', () => {
    expect(plain('*a_b~c`d|e>f\\')).toBe('\\*a\\_b\\~c\\`d\\|e\\>f\\\\')
  })
})

describe('eventUrl', () => {
  it('works with or without a trailing slash or hash', () => {
    expect(eventUrl('https://a.io/ff', 'x')).toBe('https://a.io/ff/#/events/x')
    expect(eventUrl('https://a.io/ff/#/roster', 'x')).toBe('https://a.io/ff/#/events/x')
  })
})

describe('buttonReply', () => {
  it('says each outcome in one line', () => {
    expect(buttonReply({ result: 'in', title: 'Molten Core', role: 'healer' }, SITE)).toBe("You're in as Healer for Molten Core.")
    expect(buttonReply({ result: 'in', title: 'Molten Core', role: 'tank', character: 'Grukk' }, SITE)).toBe("You're in as Tank on Grukk for Molten Core.")
    expect(buttonReply({ result: 'out', title: 'Molten Core' }, SITE)).toBe('Marked as not coming to Molten Core.')
    expect(buttonReply({ result: 'not_member' }, SITE)).toContain(SITE)
    expect(buttonReply({ result: 'waiting' }, SITE)).toContain('approve')
    expect(buttonReply({ result: 'no_character' }, SITE)).toContain(`${SITE}#/me`)
    for (const r of ['in', 'out', 'over', 'no_event', 'not_member', 'waiting', 'no_character'] as const) {
      expect(buttonReply({ result: r }, SITE)).not.toContain('\n')
    }
  })
})

describe('reminders', () => {
  const people = [
    { role: 'dps' as const, name: 'Ash', discord_id: '111' },
    { role: 'tank' as const, name: 'Bo', discord_id: '222' },
    { role: 'dps' as const, name: 'Cy', discord_id: null },
    { role: 'tank' as const, name: 'Di', discord_id: '444' },
  ]

  it('groups mentions by role, tanks first, a name when there is no Discord id', () => {
    expect(reminderLines(people)).toEqual(['🛡️ **Tank** (2): <@222> <@444>', '⚔️ **DPS** (2): <@111> Cy'])
  })

  it('replies to the post, pings only the people going, never everyone', () => {
    const m = reminderMessage({ id: ID, title: 'Molten Core', starts_at: '2026-11-11T03:00:00Z', message_id: '999', people })
    expect(m.content.split('\n')[0]).toBe(`⏰ **Molten Core** starts <t:${Date.parse('2026-11-11T03:00:00Z') / 1000}:R>. Time to log in!`)
    expect(m.allowed_mentions).toEqual({ parse: [], users: ['111', '222', '444'], replied_user: false })
    expect(m.message_reference).toEqual({ message_id: '999', fail_if_not_exists: false })
  })

  it('says so when nobody has signed up, and stays inside 2000 characters', () => {
    expect(reminderMessage({ id: ID, title: 'X', starts_at: '2026-11-11T03:00:00Z', message_id: null, people: [] }).content).toContain('Nobody has signed up yet.')
    const crowd = Array.from({ length: 150 }, (_, i) => ({ role: 'dps' as const, name: `P${i}`, discord_id: `1${String(i).padStart(17, '0')}` }))
    const m = reminderMessage({ id: ID, title: 'X', starts_at: '2026-11-11T03:00:00Z', message_id: null, people: crowd })
    expect(m.content.length).toBeLessThanOrEqual(2000)
    expect(m.allowed_mentions.users).toHaveLength(100)
  })
})

describe('kill on sight', () => {
  const KOS = '7c1d2e3f-4a5b-4c6d-8e9f-a0b1c2d3e4f5'
  const mark = (o: Partial<KosView> = {}): KosView => ({
    id: KOS, name: 'Itz Shifty', level: 32, race: 'nightelf', class_id: 'druid', guild: 'DYNASTY', zone: 'The Barrens',
    reason: 'ganks lowbies at the Crossroads', danger: 3, created_at: '2026-11-12T20:00:00Z', updated_at: '2026-11-12T20:00:00Z',
    cleared_at: null, marked_by: 'Azujin', cleared_by: null, discord_message_id: null, guild_name: 'Fantasy Force', ...o,
  })

  it('knows every class and race the site does', () => {
    expect(CLASS_NAME).toEqual(Object.fromEntries(CLASSES.map((c) => [c.id, c.name])))
    expect(RACE_NAME).toEqual(Object.fromEntries(RACES.map((r) => [r.id, r.name])))
  })

  it('says who they are with what is known', () => {
    expect(kosWho(mark())).toBe('Level 32 Night Elf Druid')
    expect(kosWho(mark({ level: null, race: '', class_id: 'rogue' }))).toBe('Rogue')
    expect(kosWho(mark({ level: null, race: '', class_id: '' }))).toBe('')
  })

  it('gives the addon command, without anything that breaks it', () => {
    expect(kosCommand(mark())).toBe('/ff kos Itz Shifty - ganks lowbies at the Crossroads')
    expect(kosCommand(mark({ reason: '' }))).toBe('/ff kos Itz Shifty')
    expect(kosCommand(mark({ reason: 'a `b`\nc' }))).toBe('/ff kos Itz Shifty - a b c')
  })

  it('posts a red, skull-marked broadcast with threat, place, marker and the addon command', () => {
    const m = kosMessage(mark(), SITE, { post: true })
    const e = m.embeds[0]!
    expect(m.content).toBe('🚨 **Itz Shifty** is now kill on sight.')
    expect(e.author.name).toBe('KILL ON SIGHT')
    expect(e.author.icon_url).toBe(`${SITE}discord/kos.png`)
    expect(e.title).toBe('ITZ SHIFTY')
    expect(e.url).toBe(`${SITE}#/kos/${KOS}`)
    expect(e.color).toBe(threat(3).colour)
    expect(e.description).toBe('**Level 32 Night Elf Druid**  <DYNASTY>\n>>> ganks lowbies at the Crossroads')
    expect(e.thumbnail).toEqual({ url: `${SITE}discord/kos.png` })
    expect(e.fields.map((f) => f.value)).toEqual(['☠️☠️☠️ **Public enemy**', 'The Barrens', 'Azujin', '`/ff kos Itz Shifty - ganks lowbies at the Crossroads`'])
    expect(e.footer.text).toBe('Fantasy Force · Kill on sight list')
    expect(e.timestamp).toBe('2026-11-12T20:00:00Z')
    expect(m.allowed_mentions).toEqual({ parse: [], roles: [] })
  })

  it('pings the role on the first post only', () => {
    expect(kosMessage(mark({ danger: 2 }), SITE, { post: true, roleId: '555' })).toMatchObject({
      content: '<@&555> ☠️ **Itz Shifty** is now kill on sight.', allowed_mentions: { parse: [], roles: ['555'] },
    })
    expect(kosMessage(mark(), SITE, { post: false, roleId: '555' }).allowed_mentions).toEqual({ parse: [], roles: [] })
  })

  it('greys a cleared mark out and says who cleared it', () => {
    const m = kosMessage(mark({ cleared_at: '2026-11-13T01:00:00Z', cleared_by: 'Mira' }), SITE, { post: false, roleId: '555' })
    const e = m.embeds[0]!
    expect(m.content).toBe('✅ ~~**Itz Shifty**~~ is no longer kill on sight.')
    expect(e.title).toBe('Itz Shifty (cleared)')
    expect(e.color).toBe(0x4f545c)
    expect(e).not.toHaveProperty('thumbnail')
    expect(e.fields[0]).toEqual({ name: 'Cleared by', value: 'Mira', inline: true })
  })

  it('copes with a mark that says almost nothing', () => {
    const e = kosMessage(mark({ level: null, race: '', class_id: '', guild: '', zone: '', reason: '', danger: 0 }), SITE, { post: true }).embeds[0]!
    expect(e.description).toBe('*Unknown level, race and class*')
    expect(e.fields[0]!.value).toContain('Menace')
    expect(e.fields[1]!.value).toBe('*Somewhere out there*')
  })
})
