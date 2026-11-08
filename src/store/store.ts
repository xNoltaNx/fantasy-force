import type { ImportedCharacter } from '../addonFile'
import type { Character, Guild, GuildData, GuildEvent, InGameRoster, Member, Rank, Signup, Viewer } from '../types'

/** The rows an import writes: existing characters (by name, any case) updated, new ones added. */
export function mergeImport(existing: Character[], memberId: string, chars: ImportedCharacter[]): CharacterInput[] {
  const hasMain = existing.some((c) => c.is_main)
  return chars.map((c, i) => {
    const old = existing.find((e) => e.name.toLowerCase() === c.name.toLowerCase())
    // The game can't tell a bear from a cat Druid: a Feral pick made on the site stays.
    const keep = !!old && old.class_id === c.class_id && /^Feral/.test(old.spec) && /^Feral/.test(c.spec)
    return {
      ...(old ? { id: old.id } : {}),
      member_id: memberId,
      name: c.name,
      race: c.race || old?.race || '',
      class_id: c.class_id,
      spec: keep ? old!.spec : c.spec,
      role: keep ? old!.role : c.role,
      is_main: old ? old.is_main : !hasMain && i === 0,
      level: c.level,
      // Recipes only refresh when a profession window is opened in game: keep the site's when the file has none.
      professions: c.professions.map((p) => {
        const before = old?.professions.find((x) => x.name === p.name)
        return p.recipes?.length || !before?.recipes?.length ? p : { ...p, recipes: before.recipes }
      }),
      note: old?.note ?? '',
    }
  })
}

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

  /** Add or update a member's characters from the addon's file, matched by name; their main stays their main. */
  importCharacters(memberId: string, chars: ImportedCharacter[]): Promise<void>
  saveInGameRoster(r: InGameRoster): Promise<void>

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
