import type { Role } from './wow'

export interface Guild {
  name: string
  region: string // 'us' | 'eu' | 'kr' | 'tw'
  realm: string // the guild's home realm, the default for new characters
  about: string
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
  realm: string
  class_id: string
  spec: string
  role: Role
  is_main: boolean
  item_level: number | null
  note: string
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
}

export interface Viewer {
  id: string
  member: Member | null
  isOfficer: boolean
  isApproved: boolean
}
