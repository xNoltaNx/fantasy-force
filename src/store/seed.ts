import type { Availability, Character, GuildData, GuildEvent, Member, Signup } from '../types'
import { roleFor } from '../wow'

// Example guild for the demo: made-up players, mains and alts, availability and two events.

const PLAYERS: [string, string, number, string][] = [
  // display name, Discord name, rank id, time zone
  ['Thornwick', 'thornwick', 1, 'America/Los_Angeles'],
  ['Maelis', 'maelis.', 2, 'America/New_York'],
  ['Brakka', 'brakkasmash', 2, 'America/Chicago'],
  ['Sunniva', 'sunniva', 3, 'Europe/London'],
  ['Kettle', 'kettle_wow', 3, 'America/Denver'],
  ['Vashir', 'vashir', 3, 'America/Los_Angeles'],
  ['Orla', 'orla.heals', 3, 'America/New_York'],
  ['Pip', 'pipsqueak', 3, 'America/Chicago'],
  ['Dunmore', 'dunmore', 3, 'America/Los_Angeles'],
  ['Yseth', 'yseth', 3, 'Australia/Sydney'],
  ['Grell', 'grellgrell', 4, 'America/New_York'],
  ['Marrow', 'marrowbones', 4, 'America/Phoenix'],
  ['Tamsin', 'tamsin', 4, 'Europe/Berlin'],
  ['Hobb', 'hobb', 5, 'America/Los_Angeles'],
  ['Liora', 'liora', 5, 'America/Chicago'],
  ['Quill', 'quill.ink', 5, 'America/New_York'],
]

// Main then alts: [character name, class id, spec, item level]
const CHARS: [string, string, string, number][][] = [
  [['Thornwick', 'warrior', 'Protection', 684], ['Thornheal', 'priest', 'Holy', 662]],
  [['Maelis', 'priest', 'Discipline', 681], ['Maelstrike', 'rogue', 'Outlaw', 670], ['Maeflame', 'mage', 'Fire', 655]],
  [['Brakka', 'deathknight', 'Blood', 683], ['Brakkashot', 'hunter', 'Marksmanship', 668]],
  [['Sunniva', 'paladin', 'Holy', 680], ['Sunclaw', 'druid', 'Feral', 660]],
  [['Kettle', 'monk', 'Windwalker', 679]],
  [['Vashir', 'demonhunter', 'Havoc', 682], ['Vashvoke', 'evoker', 'Augmentation', 671], ['Vashtank', 'demonhunter', 'Vengeance', 664]],
  [['Orla', 'shaman', 'Restoration', 678], ['Orlabolt', 'shaman', 'Elemental', 660]],
  [['Pip', 'mage', 'Frost', 681]],
  [['Dunmore', 'warlock', 'Affliction', 677], ['Dunbrew', 'monk', 'Brewmaster', 669]],
  [['Yseth', 'evoker', 'Preservation', 676]],
  [['Grell', 'hunter', 'Beast Mastery', 674], ['Grellock', 'warlock', 'Destruction', 652]],
  [['Marrow', 'deathknight', 'Unholy', 675]],
  [['Tamsin', 'druid', 'Balance', 673], ['Tamsmite', 'priest', 'Shadow', 650]],
  [['Hobb', 'rogue', 'Subtlety', 665]],
  [['Liora', 'demonhunter', 'Devourer', 668]],
  [['Quill', 'warrior', 'Fury', 663]],
]

// Usual play windows in each player's own evening, as [first local hour, last local hour, weekdays (0=Mon)].
const WINDOWS: [number, number, number[]][] = [
  [18, 22, [1, 2, 3, 5]], [19, 23, [0, 1, 3, 6]], [19, 22, [1, 3, 4]], [19, 23, [1, 2, 3, 6]],
  [18, 21, [1, 3, 5, 6]], [17, 22, [1, 2, 3]], [20, 23, [0, 1, 3]], [19, 22, [1, 3, 5]],
  [18, 21, [1, 2, 3, 4]], [9, 13, [2, 4, 5]], [20, 23, [1, 3, 6]], [17, 20, [1, 3, 5, 6]],
  [20, 23, [1, 2, 6]], [18, 22, [1, 3]], [19, 22, [1, 3, 6]], [20, 23, [1, 3, 4]],
]

/** UTC hour-of-week for a local day/hour in a time zone (good enough for example data: uses today's offset). */
function utcSlot(tz: string, day: number, hour: number): number {
  const now = new Date()
  const asTz = new Date(now.toLocaleString('en-US', { timeZone: tz }))
  const offsetHours = Math.round((asTz.getTime() - new Date(now.toLocaleString('en-US', { timeZone: 'UTC' })).getTime()) / 3600000)
  return (((day * 24 + hour - offsetHours) % 168) + 168) % 168
}

function nextWeekday(weekday: number, hourLocal: number): string {
  const d = new Date()
  d.setHours(hourLocal, 0, 0, 0)
  const add = ((weekday - d.getDay() + 7) % 7) || 7
  d.setDate(d.getDate() + add)
  return d.toISOString()
}

export function seedData(): GuildData {
  const members: Member[] = PLAYERS.map(([name, discord, rank, tz], i) => ({
    id: `m${i + 1}`,
    display_name: name,
    discord_name: discord,
    avatar_url: null,
    rank_id: rank,
    timezone: tz,
    joined_at: new Date(Date.now() - (400 - i * 23) * 86400000).toISOString().slice(0, 10),
    about: '',
  }))
  members.push({ id: 'm-new', display_name: 'Fenwick', discord_name: 'fenwick_', avatar_url: null, rank_id: null,
    timezone: 'America/New_York', joined_at: new Date().toISOString().slice(0, 10), about: 'Saw your post on the realm forum!' })

  const characters: Character[] = []
  CHARS.forEach((list, i) => list.forEach(([name, classId, spec, ilvl], j) => {
    characters.push({ id: `c${i + 1}-${j}`, member_id: `m${i + 1}`, name, realm: 'Moon Guard', class_id: classId, spec,
      role: roleFor(classId, spec), is_main: j === 0, item_level: ilvl, note: '' })
  }))
  characters.push({ id: 'c-new', member_id: 'm-new', name: 'Fenwick', realm: 'Wyrmrest Accord', class_id: 'paladin',
    spec: 'Protection', role: 'tank', is_main: true, item_level: 640, note: '' })

  const availability: Availability[] = members.slice(0, 16).map((m, i) => {
    const [from, to, days] = WINDOWS[i]
    const slots = days.flatMap((d) => Array.from({ length: to - from }, (_, k) => utcSlot(m.timezone, d, from + k)))
    return { member_id: m.id, slots }
  })

  const events: GuildEvent[] = [
    { id: 'e1', title: 'Raid night: Heroic progression', starts_at: nextWeekday(2, 19), duration_minutes: 180,
      description: 'Bring flasks and food. Pulls start at 7:15 sharp.', need_tank: 2, need_healer: 4, need_dps: 14, created_by: 'm1' },
    { id: 'e2', title: 'Mythic+ push night', starts_at: nextWeekday(5, 20), duration_minutes: 150,
      description: 'Groups formed in Discord. Alts welcome.', need_tank: 3, need_healer: 3, need_dps: 9, created_by: 'm2' },
  ]

  const signups: Signup[] = []
  const status = ['in', 'in', 'in', 'maybe', 'in', 'in', 'out', 'in', 'in', 'maybe', 'in', 'in', 'in'] as const
  for (let i = 0; i < 13; i++) {
    const main = characters.find((c) => c.member_id === `m${i + 1}` && c.is_main)!
    signups.push({ event_id: 'e1', member_id: main.member_id, character_id: main.id, role: main.role, status: status[i], comment: '' })
  }
  signups[6].comment = 'Work trip, sorry!'

  return {
    guild: { name: 'Lanterns of the Vale', region: 'us', realm: 'Moon Guard', about: 'A relaxed raiding guild. Raids Tue and Thu, 7 to 10 pm Pacific.' },
    ranks: [
      { id: 1, name: 'Guild Master', sort: 0, is_officer: true },
      { id: 2, name: 'Officer', sort: 1, is_officer: true },
      { id: 3, name: 'Raider', sort: 2, is_officer: false },
      { id: 4, name: 'Member', sort: 3, is_officer: false },
      { id: 5, name: 'Trial', sort: 4, is_officer: false },
    ],
    members, characters, availability, events, signups,
    officerNotes: [
      { member_id: 'm14', note: 'Trial since last month. Solid on mechanics, ask about raid attendance.', updated_at: new Date().toISOString() },
      { member_id: 'm16', note: 'Great attitude. Gear is a bit behind, help with M+.', updated_at: new Date().toISOString() },
    ],
  }
}
