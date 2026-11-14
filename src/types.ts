import type { Faction, Role } from './wow'

export interface Guild {
  name: string
  region: string // 'us' | 'eu' | 'kr' | 'tw'
  ruleset: string // Forever has one mega-realm per ruleset and region: Normal, PvP, RP, RP-PvP, Hardcore
  faction: Faction | '' // '' until set: every race is offered
  about: string
  rules: string // guild rules, plain text, shown on the Links page
  loot_policy: string // how loot is handed out, plain text
  links: GuildLink[] // Discord invite, guides, anything handy
}

export interface Rank {
  id: number
  name: string
  sort: number
  is_officer: boolean
}

export interface Member {
  id: string
  display_name: string
  discord_name: string
  avatar_url: string | null
  rank_id: number | null // null: signed in but not yet approved by an officer
  timezone: string
  joined_at: string // yyyy-mm-dd
  about: string
}

export interface Character {
  id: string
  member_id: string
  name: string
  race: string // '' when not given
  class_id: string
  spec: string
  role: Role
  is_main: boolean
  level: number | null
  professions: Profession[]
  note: string
}

export interface Profession {
  name: string
  skill: number
  max: number
  recipes?: Recipe[] // from the addon once the profession's window has been opened in game
}

/** A known recipe: its spell id and the item it makes, when the game gave them (for icons and Wowhead tooltips). */
export interface Recipe {
  name: string
  spell?: number
  item?: number
}

/** One line of the guild's in-game roster, as the addon last saw it. */
export interface InGameMember {
  name: string
  rank: string
  rank_index: number
  level: number | null
  class_id: string
  note: string
  online: boolean
  last_online_days: number | null
}

export interface InGameRoster {
  updated_at: string // when the addon recorded it
  recorded_by: string // the character it was recorded on
  members: InGameMember[]
}

/** Hours of the week a member usually plays, as UTC hour-of-week (0 = Monday 00:00 UTC, 167 = Sunday 23:00 UTC). */
export interface Availability {
  member_id: string
  slots: number[]
}

export interface GuildEvent {
  id: string
  title: string
  starts_at: string // ISO, UTC
  duration_minutes: number
  description: string
  need_tank: number
  need_healer: number
  need_dps: number
  created_by: string
  discord_message_id?: string | null // its post in the guild's Discord channel, once the bot has posted it (live site only)
}

export type SignupStatus = 'in' | 'maybe' | 'out'

export interface Signup {
  event_id: string
  member_id: string
  character_id: string
  role: Role
  status: SignupStatus
  comment: string
}

export interface OfficerNote {
  member_id: string
  note: string
  updated_at: string
}

export interface BankItem {
  id: number
  name: string
  count: number
  quality: number // 0 poor … 4 epic, 5 legendary
}

/** The guild bank (or a bank alt's bags and bank), as an officer's addon last saw it. */
export interface GuildBank {
  source: 'guild' | 'alt'
  updated_at: string
  recorded_by: string
  money: number | null // copper
  tabs: { name: string; items: BankItem[] }[]
}

export interface RaidLoot {
  item_id: number
  name: string
  quality: number
  to: string // character name
  at: string
  boss: string // the last boss killed before it dropped; '' if none
}

/** One raid night in one zone, from the addon: who was there, what died, what dropped to whom. */
export interface Raid {
  key: string // zone and date, e.g. "Molten Core 2026-11-10"
  zone: string
  started_at: string
  ended_at: string
  recorded_by: string
  attendees: string[] // character names
  bosses: { name: string; killed_at: string; attendees: string[] }[]
  loot: RaidLoot[]
}

/** An enemy player on the guild's kill-on-sight list (members only). Each one is broadcast to Discord. */
export interface KosMark {
  id: string
  name: string
  level: number | null
  race: string // a race id from wow.ts, '' unknown
  class_id: string // '' unknown
  guild: string
  zone: string // where they were last seen
  reason: string
  danger: 1 | 2 | 3 // 1 pest, 2 menace, 3 public enemy
  created_by: string | null
  created_at: string
  updated_at: string
  cleared_at: string | null // cleared: no longer kill on sight, kept for the record
  cleared_by: string | null
  discord_message_id?: string | null // its post in Discord, once the bot has posted it (live site only)
}

export interface GuildLink {
  title: string
  url: string
  note: string
}

/** Everything the signed-in viewer may see, loaded at once (a guild is small). */
export interface GuildData {
  guild: Guild
  ranks: Rank[]
  members: Member[]
  characters: Character[]
  availability: Availability[]
  events: GuildEvent[]
  signups: Signup[]
  officerNotes: OfficerNote[] // empty unless the viewer is an officer
  inGame: InGameRoster | null // the in-game guild list from the addon; members and officers only
  bank: GuildBank | null // members and officers only
  raids: Raid[] // members and officers only
  kos: KosMark[] // members and officers only, newest first
}

export interface Viewer {
  id: string
  member: Member | null
  isOfficer: boolean
  isApproved: boolean
}
