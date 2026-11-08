import type { Character, Guild, GuildData, GuildEvent, Member, Rank, Signup, Viewer } from '../types'

export type CharacterInput = Omit<Character, 'id'> & { id?: string }
export type EventInput = Omit<GuildEvent, 'id' | 'created_by'> & { id?: string }
export type MemberPatch = Partial<Pick<Member, 'display_name' | 'timezone' | 'about' | 'rank_id' | 'joined_at'>>

/** One data layer, two backends: the demo (this browser's storage) and the live Supabase one. */
export interface Store {
  mode: 'demo' | 'live'
  viewer(): Promise<Viewer | null>
  onAuthChange(cb: () => void): () => void
  signIn(): Promise<void>
  signOut(): Promise<void>
  load(): Promise<GuildData>

  updateMember(memberId: string, patch: MemberPatch): Promise<void>
  removeMember(memberId: string): Promise<void>
  saveCharacter(c: CharacterInput): Promise<void>
  deleteCharacter(id: string): Promise<void>
  setMain(memberId: string, characterId: string): Promise<void>
  saveAvailability(memberId: string, slots: number[]): Promise<void>

  saveEvent(e: EventInput): Promise<void>
  deleteEvent(id: string): Promise<void>
  saveSignup(s: Signup): Promise<void>
  deleteSignup(eventId: string, memberId: string): Promise<void>

  saveOfficerNote(memberId: string, note: string): Promise<void>
  saveRank(r: Omit<Rank, 'id'> & { id?: number }): Promise<void>
  deleteRank(id: number): Promise<void>
  updateGuild(g: Guild): Promise<void>
}

export function viewerFrom(id: string, data: Pick<GuildData, 'members' | 'ranks'>): Viewer {
  const member = data.members.find((m) => m.id === id) ?? null
  const rank = data.ranks.find((r) => r.id === member?.rank_id)
  return { id, member, isOfficer: !!rank?.is_officer, isApproved: !!rank }
}
