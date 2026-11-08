import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Availability, Character, Guild, GuildData, GuildEvent, InGameRoster, Member, OfficerNote, Rank, Signup, Viewer } from '../types'
import { mergeImport, viewerFrom, type Store } from './store'

// The live site: Supabase holds the data, Discord signs people in, and the row rules in
// supabase/schema.sql decide who may read and change what. Nothing here is trusted for that.

export class SupabaseStore implements Store {
  mode = 'live' as const
  private db: SupabaseClient

  constructor(url: string, anonKey: string) {
    this.db = createClient(url, anonKey)
  }

  private async ok<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<T> {
    const { data, error } = await p
    if (error) throw new Error(error.message)
    return data
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private async rows<R>(p: PromiseLike<{ data: any[] | null; error: { message: string } | null }>): Promise<R[]> {
    return ((await this.ok(p)) ?? []) as R[]
  }

  async viewer(): Promise<Viewer | null> {
    const { data } = await this.db.auth.getSession()
    const id = data.session?.user.id
    if (!id) return null
    const [members, ranks] = await Promise.all([
      this.rows<Member>(this.db.from('members').select('*').eq('id', id)),
      this.rows<Rank>(this.db.from('ranks').select('*')),
    ])
    return viewerFrom(id, { members, ranks })
  }

  onAuthChange(cb: () => void) {
    const { data } = this.db.auth.onAuthStateChange(() => cb())
    return () => data.subscription.unsubscribe()
  }

  async signIn() {
    const redirectTo = window.location.origin + window.location.pathname
    const { error } = await this.db.auth.signInWithOAuth({ provider: 'discord', options: { redirectTo } })
    if (error) throw new Error(error.message)
  }

  async signOut() {
    await this.db.auth.signOut()
  }

  async load(): Promise<GuildData> {
    const t = <R,>(name: string) => this.rows<R>(this.db.from(name).select('*'))
    const [guilds, ranks, members, characters, availability, events, signups, officerNotes, inGame] = await Promise.all([
      t<Guild>('guild'), t<Rank>('ranks'), t<Member>('members'), t<Character>('characters'), t<Availability>('availability'),
      t<GuildEvent>('events'), t<Signup>('signups'), t<OfficerNote>('officer_notes'), t<InGameRoster>('ingame_roster'),
    ])
    if (!guilds[0]) throw new Error('The guild table is empty: run supabase/schema.sql in your Supabase project.')
    return { guild: guilds[0], ranks, members, characters, availability, events, signups, officerNotes, inGame: inGame[0] ?? null }
  }

  async updateMember(memberId: string, patch: object) {
    await this.ok(this.db.from('members').update(patch).eq('id', memberId))
  }

  async removeMember(memberId: string) {
    await this.ok(this.db.rpc('remove_member', { target: memberId }))
  }

  async saveCharacter(c: Parameters<Store['saveCharacter']>[0]) {
    if (c.is_main) await this.ok(this.db.from('characters').update({ is_main: false }).eq('member_id', c.member_id))
    await this.ok(this.db.from('characters').upsert(c))
  }

  async deleteCharacter(id: string) {
    await this.ok(this.db.from('characters').delete().eq('id', id))
  }

  async setMain(memberId: string, characterId: string) {
    await this.ok(this.db.from('characters').update({ is_main: false }).eq('member_id', memberId))
    await this.ok(this.db.from('characters').update({ is_main: true }).eq('id', characterId))
  }

  async saveAvailability(memberId: string, slots: number[]) {
    await this.ok(this.db.from('availability').upsert({ member_id: memberId, slots }))
  }

  async saveEvent(e: Parameters<Store['saveEvent']>[0]) {
    await this.ok(this.db.from('events').upsert(e))
  }

  async deleteEvent(id: string) {
    await this.ok(this.db.from('events').delete().eq('id', id))
  }

  async saveSignup(s: Parameters<Store['saveSignup']>[0]) {
    await this.ok(this.db.from('signups').upsert(s))
  }

  async deleteSignup(eventId: string, memberId: string) {
    await this.ok(this.db.from('signups').delete().eq('event_id', eventId).eq('member_id', memberId))
  }

  async importCharacters(memberId: string, chars: Parameters<Store['importCharacters']>[1]) {
    const existing = await this.rows<Character>(this.db.from('characters').select('*').eq('member_id', memberId))
    const rows = mergeImport(existing, memberId, chars)
    const fresh = rows.filter((r) => !r.id)
    const known = rows.filter((r) => r.id)
    if (known.length) await this.ok(this.db.from('characters').upsert(known))
    if (fresh.length) await this.ok(this.db.from('characters').insert(fresh))
  }

  async saveInGameRoster(r: Parameters<Store['saveInGameRoster']>[0]) {
    await this.ok(this.db.from('ingame_roster').upsert({ id: 1, ...r }))
  }

  async saveOfficerNote(memberId: string, note: string) {
    if (note.trim()) await this.ok(this.db.from('officer_notes').upsert({ member_id: memberId, note }))
    else await this.ok(this.db.from('officer_notes').delete().eq('member_id', memberId))
  }

  async saveRank(r: Parameters<Store['saveRank']>[0]) {
    await this.ok(this.db.from('ranks').upsert(r))
  }

  async deleteRank(id: number) {
    await this.ok(this.db.from('ranks').delete().eq('id', id))
  }

  async updateGuild(g: GuildData['guild']) {
    await this.ok(this.db.from('guild').update(g).eq('id', 1))
  }
}
