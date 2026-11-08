import type { ImportedCharacter } from '../addonFile'
import type { Character, Guild, GuildBank, GuildData, GuildEvent, InGameRoster, Member, Raid, Rank, Signup, Viewer } from '../types'

const union = (a: string[], b: string[]) => [...new Set([...a, ...b])]

/** Two recordings of the same raid night (two officers' addons) joined: everyone seen, every boss, each drop once. */
export function mergeRaid(a: Raid, b: Raid): Raid {
  const bosses = [...a.bosses]
  for (const x of b.bosses) {
    const same = bosses.findIndex((y) => y.name === x.name)
    if (same >= 0) bosses[same] = { ...bosses[same]!, attendees: union(bosses[same]!.attendees, x.attendees) }
    else bosses.push(x)
  }
  const lootKey = (l: Raid['loot'][number]) => `${l.item_id}|${l.name}|${l.to}|${l.at.slice(0, 16)}`
  const seen = new Set(a.loot.map(lootKey))
  return {
    ...a,
    started_at: a.started_at < b.started_at ? a.started_at : b.started_at,
    ended_at: a.ended_at > b.ended_at ? a.ended_at : b.ended_at,
    attendees: union(a.attendees, b.attendees),
    bosses: bosses.sort((x, y) => x.killed_at.localeCompare(y.killed_at)),
    loot: [...a.loot, ...b.loot.filter((l) => !seen.has(lootKey(l)))].sort((x, y) => x.at.localeCompare(y.at)),
  }
}

/** The rows an import writes: existing characters (by name, any case) updated, new ones added. */
export function mergeImport(existing: Character[], memberId: string, chars: ImportedCharacter[]): CharacterInput[] {
  // The main: one chosen in game with /ff main wins; else the site's stays; else the highest level, as the addon picks.
  const chosen = chars.find((c) => c.main)
  const hasMain = existing.some((c) => c.is_main)
  const highest = chars.reduce((best, c, i) => ((c.level ?? 0) > (chars[best]?.level ?? 0) ? i : best), 0)
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
      is_main: chosen ? c === chosen : old ? old.is_main : !hasMain && i === highest,
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
  saveBank(b: GuildBank): Promise<void>
  /** Add raids from the addon; a night already on the site is joined with the new recording (mergeRaid). */
  importRaids(raids: Raid[]): Promise<void>

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
