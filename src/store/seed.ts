import type { Availability, Character, GuildBank, GuildData, GuildEvent, InGameRoster, KosMark, Member, Raid, Recipe, Signup } from '../types'
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

// Main then alts: [character name (Forever has first and last names), race, class id, spec, level, professions]
type P = [string, number]
const CHARS: [string, string, string, string, number, P[]][][] = [
  [['Grukka Stonefist', 'orc', 'warrior', 'Protection', 60, [['Blacksmithing', 300], ['Mining', 300]]],
    ['Ashka Stonefist', 'troll', 'priest', 'Holy', 34, [['Tailoring', 165], ['First Aid', 225]]]],
  [['Morwen Hollowmere', 'undead', 'priest', 'Discipline', 60, [['Alchemy', 300], ['Herbalism', 300]]],
    ['Silt Hollowmere', 'undead', 'rogue', 'Combat', 47, [['Skinning', 220], ['Leatherworking', 210]]],
    ['Ember Hollowmere', 'undead', 'mage', 'Fire', 19, [['Enchanting', 90]]]],
  [['Brakka Ironhide', 'tauren', 'druid', 'Feral (bear)', 60, [['Leatherworking', 300], ['Skinning', 300]]],
    ['Brakka Longsight', 'orc', 'hunter', 'Marksmanship', 52, [['Engineering', 240], ['Mining', 245]]]],
  [['Sunniva Windcaller', 'skyborne', 'shaman', 'Restoration', 60, [['Herbalism', 300], ['Alchemy', 295], ['Cooking', 300]]],
    ['Sunclaw Windcaller', 'tauren', 'druid', 'Feral (cat)', 41, [['Fishing', 180]]]],
  [['Kettle Brewgut', 'orc', 'hunter', 'Beast Mastery', 60, [['Engineering', 300], ['Mining', 280]]]],
  [['Vashir Nightshade', 'troll', 'rogue', 'Assassination', 60, [['Alchemy', 260], ['Herbalism', 270]]],
    ['Vashir Dreadmoor', 'undead', 'warlock', 'Affliction', 38, [['Tailoring', 180]]],
    ['Vashtusk Grimhorn', 'tauren', 'warrior', 'Protection', 26, [['Mining', 110]]]],
  [['Orla Tidesong', 'troll', 'shaman', 'Restoration', 60, [['Herbalism', 300], ['First Aid', 300]]],
    ['Orla Stormcrest', 'skyborne', 'shaman', 'Elemental', 44, [['Enchanting', 200], ['Tailoring', 210]]]],
  [['Pip Ashwhistle', 'undead', 'mage', 'Frost', 60, [['Tailoring', 300], ['Enchanting', 290]]]],
  [['Dunmore Blackthorn', 'undead', 'warlock', 'Destruction', 60, [['Tailoring', 285], ['Enchanting', 300]]],
    ['Dunmore Ruttusk', 'orc', 'warrior', 'Fury', 30, [['Blacksmithing', 140], ['Mining', 150]]]],
  [['Yseth Moonhoof', 'tauren', 'druid', 'Restoration', 60, [['Herbalism', 300], ['Alchemy', 300]]]],
  [['Grell Bonechewer', 'troll', 'hunter', 'Survival', 58, [['Skinning', 280], ['Leatherworking', 270]]],
    ['Grell Hexmoor', 'troll', 'priest', 'Shadow', 27, []]],
  [['Marrow Gravelkin', 'undead', 'warrior', 'Arms', 60, [['Mining', 300], ['Blacksmithing', 290], ['Fishing', 300]]]],
  [['Tamsin Duskhorn', 'tauren', 'druid', 'Balance', 56, [['Cooking', 260], ['Fishing', 240]]],
    ['Tamsin Wraithe', 'undead', 'priest', 'Shadow', 33, [['Tailoring', 160]]]],
  [['Hobb Quickfingers', 'undead', 'rogue', 'Subtlety', 49, [['Engineering', 205], ['Mining', 215]]]],
  [['Liora Skywhisper', 'skyborne', 'shaman', 'Enhancement', 42, [['Skinning', 190], ['Leatherworking', 185]]]],
  [['Quill Redmane', 'orc', 'warrior', 'Fury', 37, [['Mining', 160], ['Blacksmithing', 155]]]],
]

// Recipes for the example crafters, roughly low to high skill: a character knows the share their skill reaches.
// [name, item it makes] for crafts (item ids from 2004); [name, 0, spell] for enchants.
type R = [string, number, number?]
const RECIPES: Record<string, R[]> = {
  Blacksmithing: [['Rough Sharpening Stone', 2862], ['Copper Chain Belt', 2851], ['Heavy Sharpening Stone', 2871], ['Mithril Spurs', 7969],
    ['Dense Weightstone', 12643], ['Dark Iron Plate', 11604], ['Lionheart Helm', 12640], ['Arcanite Reaper', 12784]],
  Alchemy: [['Minor Healing Potion', 118], ['Swiftness Potion', 2459], ['Elixir of Fortitude', 3825], ['Greater Fire Protection Potion', 13457],
    ['Elixir of the Mongoose', 13452], ['Major Healing Potion', 13446], ['Major Mana Potion', 13444], ['Transmute: Arcanite', 12360], ['Flask of the Titans', 13510]],
  Enchanting: [['Enchant Boots - Minor Speed', 0, 13890], ['Enchant Bracer - Superior Stamina', 0, 20011], ['Enchant Gloves - Greater Agility', 0, 20012],
    ['Enchant Chest - Major Health', 0, 20026], ['Enchant Weapon - Crusader', 0, 20034]],
  Tailoring: [['Linen Bag', 4238], ['Bolt of Runecloth', 14048], ['Runecloth Bag', 14046], ['Mooncloth Bag', 14155], ['Truefaith Vestments', 14154], ['Robe of the Archmage', 14152]],
  Leatherworking: [['Light Armor Kit', 2304], ['Rugged Armor Kit', 15564], ['Devilsaur Gauntlets', 15063], ['Devilsaur Leggings', 15062], ['Core Armor Kit', 18251]],
  Engineering: [['Rough Dynamite', 4358], ['Hi-Explosive Bomb', 10562], ['Thorium Grenade', 15993], ['Goblin Sapper Charge', 10646], ['Arcanite Dragonling', 16022]],
  Cooking: [['Grilled Squid', 13928], ['Nightfin Soup', 13931], ['Smoked Desert Dumplings', 20452], ['Dragonbreath Chili', 12217]],
  'First Aid': [['Linen Bandage', 1251], ['Heavy Mageweave Bandage', 8545], ['Heavy Runecloth Bandage', 14530]],
}

function recipesAt(name: string, skill: number): Recipe[] | undefined {
  const all = RECIPES[name]
  if (!all) return undefined
  return all.slice(0, Math.max(1, Math.round((skill / 300) * all.length)))
    .map(([n, item, spell]) => ({ name: n, ...(item ? { item } : {}), ...(spell ? { spell } : {}) }))
    .sort((a, b) => a.name.localeCompare(b.name))
}

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
  CHARS.forEach((list, i) => list.forEach(([name, race, classId, spec, level, profs], j) => {
    characters.push({ id: `c${i + 1}-${j}`, member_id: `m${i + 1}`, name, race, class_id: classId, spec,
      role: roleFor(classId, spec), is_main: j === 0, level, note: '',
      professions: profs.map(([n, skill]) => ({ name: n, skill, max: 300, recipes: recipesAt(n, skill) })) })
  }))
  characters.push({ id: 'c-new', member_id: 'm-new', name: 'Fenwick Tallgrass', race: 'tauren', class_id: 'warrior',
    spec: 'Protection', role: 'tank', is_main: true, level: 51, note: '', professions: [['Mining', 230], ['Blacksmithing', 225]].map(([n, s]) => ({ name: n as string, skill: s as number, max: 300 })) })

  // The in-game guild list, as an officer's addon last saw it: some people aren't on the site yet.
  const inGame: InGameRoster = {
    updated_at: new Date(Date.now() - 3 * 3600000).toISOString(),
    recorded_by: 'Grukka Stonefist',
    members: [
      ...characters.filter((c) => c.member_id !== 'm-new').map((c) => {
        const m = members.find((x) => x.id === c.member_id)!
        const rankName = ['Guild Master', 'Officer', 'Raider', 'Member', 'Trial'][(m.rank_id ?? 4) - 1]!
        return { name: c.name, rank: c.is_main ? rankName : 'Alt', rank_index: c.is_main ? (m.rank_id ?? 5) - 1 : 5,
          level: c.level, class_id: c.class_id, note: c.is_main ? '' : `alt of ${characters.find((x) => x.member_id === c.member_id && x.is_main)!.name.split(' ')[0]}`,
          online: c.name.startsWith('Pip') || c.name.startsWith('Orla T'), last_online_days: c.is_main ? 0 : 2 }
      }),
      { name: 'Zug Bramblehoof', rank: 'Member', rank_index: 3, level: 60, class_id: 'shaman', note: 'returning player', online: false, last_online_days: 1 },
      { name: 'Krenn Saltfang', rank: 'Member', rank_index: 3, level: 45, class_id: 'mage', note: '', online: true, last_online_days: 0 },
      { name: 'Nyx Thistlewhip', rank: 'Trial', rank_index: 4, level: 33, class_id: 'warlock', note: 'from trade chat', online: false, last_online_days: 6 },
    ],
  }

  const availability: Availability[] = members.slice(0, 16).map((m, i) => {
    const [from, to, days] = WINDOWS[i]
    const slots = days.flatMap((d) => Array.from({ length: to - from }, (_, k) => utcSlot(m.timezone, d, from + k)))
    return { member_id: m.id, slots }
  })

  const events: GuildEvent[] = [
    { id: 'e1', title: 'Molten Core', starts_at: nextWeekday(2, 19), duration_minutes: 180,
      description: 'Bring fire resistance and flasks. Pulls start at 7:15 sharp.', need_tank: 3, need_healer: 9, need_dps: 28, created_by: 'm1' },
    { id: 'e2', title: 'Dungeon night: Blackrock Depths', starts_at: nextWeekday(5, 20), duration_minutes: 150,
      description: 'Groups formed in Discord. Alts and levellers welcome.', need_tank: 2, need_healer: 2, need_dps: 6, created_by: 'm2' },
  ]

  const signups: Signup[] = []
  const status = ['in', 'in', 'in', 'maybe', 'in', 'in', 'out', 'in', 'in', 'maybe', 'in', 'in', 'in'] as const
  for (let i = 0; i < 13; i++) {
    const main = characters.find((c) => c.member_id === `m${i + 1}` && c.is_main)!
    signups.push({ event_id: 'e1', member_id: main.member_id, character_id: main.id, role: main.role, status: status[i], comment: '' })
  }
  signups[6].comment = 'Work trip, sorry!'

  // The bank alt's bags and bank, as the addon records them.
  const it = (id: number, name: string, count: number, quality = 1) => ({ id, name, count, quality })
  const bank: GuildBank = {
    source: 'alt', updated_at: new Date(Date.now() - 26 * 3600000).toISOString(), recorded_by: 'Fantasy Bankalt', money: 4_821_537,
    tabs: [
      { name: 'Consumables', items: [it(13446, 'Major Healing Potion', 60), it(13444, 'Major Mana Potion', 45), it(13457, 'Greater Fire Protection Potion', 38),
        it(13452, 'Elixir of the Mongoose', 12), it(13510, 'Flask of the Titans', 3), it(12404, 'Dense Sharpening Stone', 80)] },
      { name: 'Materials', items: [it(12359, 'Thorium Bar', 140), it(12360, 'Arcanite Bar', 6, 2), it(14047, 'Runecloth', 420), it(14342, 'Mooncloth', 9),
        it(7078, 'Essence of Fire', 24, 2), it(7068, 'Elemental Fire', 51), it(17010, 'Fiery Core', 7, 2), it(17011, 'Lava Core', 11, 2),
        it(13468, 'Black Lotus', 4, 2), it(14344, 'Large Brilliant Shard', 15, 3), it(15417, 'Devilsaur Leather', 8), it(12811, 'Righteous Orb', 3, 2)] },
    ],
  }

  // Three Molten Core nights: who came, what died, what dropped to whom.
  const mains = characters.filter((c) => c.is_main && c.member_id !== 'm-new' && (c.level ?? 0) >= 56).map((c) => c.name)
  const BOSSES = ['Lucifron', 'Magmadar', 'Gehennas', 'Garr', 'Baron Geddon', 'Shazzrah', 'Sulfuron Harbinger', 'Golemagg the Incinerator', 'Majordomo Executus', 'Ragnaros']
  const night = (daysAgo: number, kills: number, absent: number[], loot: [number, string, number, number][]): Raid => {
    const start = new Date(); start.setDate(start.getDate() - daysAgo); start.setHours(19, 15, 0, 0)
    const at = (m: number) => new Date(start.getTime() + m * 60000).toISOString()
    const here = mains.filter((_, i) => !absent.includes(i))
    return {
      key: `Molten Core ${start.toISOString().slice(0, 10)}`, zone: 'Molten Core', recorded_by: 'Grukka Stonefist',
      started_at: at(0), ended_at: at(20 + kills * 17), attendees: here,
      bosses: BOSSES.slice(0, kills).map((name, i) => ({ name, killed_at: at(20 + i * 17), attendees: here })),
      loot: loot.map(([item_id, name, boss, who]) => ({ item_id, name, quality: 4, to: here[who % here.length]!, at: at(22 + boss * 17), boss: BOSSES[boss]! })),
    }
  }
  const raids: Raid[] = [
    night(12, 6, [9], [[16800, 'Arcanist Boots', 0, 7], [16862, 'Sabatons of Might', 2, 0], [17065, 'Medallion of Steadfast Might', 3, 2]]),
    night(9, 8, [4, 10], [[16796, 'Arcanist Leggings', 1, 6], [16849, "Giantstalker's Boots", 2, 3], [16837, 'Earthfury Boots', 4, 1], [16859, 'Lawbringer Boots', 6, 5]]),
    night(5, 10, [], [[16805, 'Felheart Gloves', 0, 8], [16829, 'Cenarion Boots', 2, 4], [17109, 'Choker of Enlightenment', 7, 1], [19147, 'Ring of Spell Power', 8, 9], [16826, 'Nightslayer Gloves', 3, 5]]),
  ]

  const hoursAgo = (h: number) => new Date(Date.now() - h * 3600000).toISOString()
  const kos: KosMark[] = [
    { id: 'k1', name: 'Itz Shifty', level: 32, race: 'nightelf', class_id: 'druid', guild: 'DYNASTY', zone: 'The Barrens, Crossroads',
      reason: 'Ganks lowbies at the Crossroads flight master, then hides in cat form.', danger: 3,
      created_by: 'm3', created_at: hoursAgo(5), updated_at: hoursAgo(5), cleared_at: null, cleared_by: null },
    { id: 'k2', name: 'Lord Bonkington', level: 60, race: 'human', class_id: 'warrior', guild: 'Stormwind Bonk Squad', zone: 'Blackrock Mountain',
      reason: 'Camps the Molten Core entrance on raid nights.', danger: 2,
      created_by: 'm1', created_at: hoursAgo(50), updated_at: hoursAgo(50), cleared_at: null, cleared_by: null },
    { id: 'k3', name: 'Sneakypete', level: 41, race: 'gnome', class_id: 'rogue', guild: '', zone: 'Stranglethorn Vale',
      reason: 'Saps people at the fishing contest.', danger: 1,
      created_by: 'm5', created_at: hoursAgo(120), updated_at: hoursAgo(120), cleared_at: null, cleared_by: null },
    { id: 'k4', name: 'Mooncrash', level: 58, race: 'dwarf', class_id: 'paladin', guild: 'Ironforge Irregulars', zone: 'Tarren Mill',
      reason: 'Corpse camped Mira for an hour.', danger: 2,
      created_by: 'm2', created_at: hoursAgo(400), updated_at: hoursAgo(30), cleared_at: hoursAgo(30), cleared_by: 'm1' },
  ]

  return {
    guild: {
      name: 'Fantasy Force', region: 'us', ruleset: 'RP-PvP', faction: 'horde', about: 'A relaxed Horde raiding guild on RP-PvP. Raids Tue and Thu, 7 to 10 pm Pacific.',
      rules: 'Be kind in guild chat and Discord.\nSign up for raids by the day before.\nBring your own flasks and food; the bank covers potions.\nNo ninja looting in dungeons or raids.',
      loot_policy: 'Loot council: officers decide, favouring attendance and who it helps most. Main-spec before off-spec; alts roll after mains.',
      links: [
        { title: 'Discord', url: 'https://discord.gg/example', note: 'Voice for raids, and where groups are formed' },
        { title: 'Wowhead: WoW Forever', url: 'https://www.wowhead.com/forever', note: 'Items, quests, recipes and maps' },
        { title: 'Icy Veins: WoW Forever guides', url: 'https://www.icy-veins.com/wow-forever/', note: 'Class guides and talent builds' },
        { title: 'Fantasy Force addon', url: 'https://www.curseforge.com/wow/addons', note: 'Install it, then bring your characters in on My characters' },
      ],
    },
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
      { member_id: 'm16', note: 'Great attitude. Still levelling, help with dungeons.', updated_at: new Date().toISOString() },
    ],
    inGame,
    bank,
    raids,
    kos,
  }
}
