import { describe, expect, it } from 'vitest'
import { buttonReply, customId, eventMessage, eventUrl, parseCustomId, reminderLines, reminderMessage, roleCounts, type EventView } from './message.ts'

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

  it('has the title, link, both Discord timestamps, counts and four buttons', () => {
    const m = eventMessage(event(), SITE, before)
    const t = Date.parse('2026-11-11T03:00:00Z') / 1000
    const embed = m.embeds[0]!
    expect(embed.title).toBe('Molten Core')
    expect(embed.url).toBe(`${SITE}#/events/${ID}`)
    expect(embed.description).toContain(`<t:${t}:F>`)
    expect(embed.description).toContain(`<t:${t}:R>`)
    expect(embed.description).toContain('3 hours')
    expect(embed.description).toContain('Bring fire resistance.')
    expect(embed.fields).toEqual([
      { name: 'Tank', value: '1/2', inline: true },
      { name: 'Healer', value: '2/3', inline: true },
      { name: 'DPS', value: '1/15', inline: true },
    ])
    expect(embed.footer).toEqual({ text: "Maybe 1 · Can't make it 1" })
    const buttons = m.components[0]!.components
    expect(buttons.map((b) => b.label)).toEqual(['Tank', 'Healer', 'DPS', "Can't make it"])
    expect(buttons.map((b) => parseCustomId(b.custom_id)?.choice)).toEqual(['tank', 'healer', 'dps', 'out'])
    expect(buttons.every((b) => !b.disabled)).toBe(true)
    expect(m.allowed_mentions).toEqual({ parse: [] })
  })

  it('leaves out an empty description and footer', () => {
    const m = eventMessage(event({ description: '  ', signups: [] }), SITE, before)
    expect(m.embeds[0]!.description).not.toContain('\n')
    expect(m.embeds[0]).not.toHaveProperty('footer')
  })

  it('greys the buttons out once the event is over', () => {
    const m = eventMessage(event(), SITE, Date.parse('2026-11-11T06:01:00Z'))
    expect(m.components[0]!.components.every((b) => b.disabled)).toBe(true)
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
    expect(reminderLines(people)).toEqual(['**Tank** (2): <@222> <@444>', '**DPS** (2): <@111> Cy'])
  })

  it('replies to the post, pings only the people going, never everyone', () => {
    const m = reminderMessage({ id: ID, title: 'Molten Core', starts_at: '2026-11-11T03:00:00Z', message_id: '999', people })
    expect(m.content.split('\n')[0]).toBe(`**Molten Core** starts <t:${Date.parse('2026-11-11T03:00:00Z') / 1000}:R>.`)
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
