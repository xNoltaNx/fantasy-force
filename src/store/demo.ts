import type { GuildData, Viewer } from '../types'
import { seedData } from './seed'
import { mergeImport, mergeRaid, viewerFrom, type Store } from './store'

// The demo: an example guild kept in this browser's storage. "Viewing as" picks who you are, so every
// view (visitor, member, officer, someone waiting for approval) can be tried without Supabase. It hides
// what Supabase's row rules would hide, so the demo shows what each person really sees.

const DATA_KEY = 'guild-roster-demo-forever-3'
const VIEWER_KEY = 'guild-roster-demo-viewer'

export class DemoStore implements Store {
  mode = 'demo' as const
  private listeners = new Set<() => void>()

  private read(): GuildData {
    const raw = localStorage.getItem(DATA_KEY)
    if (raw) return JSON.parse(raw) as GuildData
    const fresh = seedData()
    this.write(fresh)
    return fresh
  }

  private write(d: GuildData) {
    localStorage.setItem(DATA_KEY, JSON.stringify(d))
  }

  private change(fn: (d: GuildData) => void) {
    const d = this.read()
    fn(d)
    this.write(d)
  }

  private me(): string | null {
    return localStorage.getItem(VIEWER_KEY)
  }

  viewAs(memberId: string | null) {
    if (memberId) localStorage.setItem(VIEWER_KEY, memberId)
    else localStorage.removeItem(VIEWER_KEY)
    this.listeners.forEach((l) => l())
  }

  reset() {
    localStorage.removeItem(DATA_KEY)
    this.listeners.forEach((l) => l())
  }

  allMembers() {
    const d = this.read()
    return { members: d.members, ranks: d.ranks }
  }

  async viewer(): Promise<Viewer | null> {
    const id = this.me()
    return id ? viewerFrom(id, this.read()) : null
  }

  onAuthChange(cb: () => void) {
    this.listeners.add(cb)
    return () => void this.listeners.delete(cb)
  }

  async signIn() {
    this.viewAs('m1')
  }

  async signOut() {
    this.viewAs(null)
  }

  async load(): Promise<GuildData> {
    const d = this.read()
    const v = this.me() ? viewerFrom(this.me()!, d) : null
    if (v?.isOfficer) return d
    const visible = new Set(d.members.filter((m) => m.rank_id !== null || m.id === v?.id).map((m) => m.id))
    return {
      ...d,
      members: d.members.filter((m) => visible.has(m.id)),
      characters: d.characters.filter((c) => visible.has(c.member_id)),
      availability: d.availability.filter((a) => visible.has(a.member_id)),
      officerNotes: [],
      inGame: v?.isApproved ? d.inGame ?? null : null,
      bank: v?.isApproved ? d.bank ?? null : null,
      raids: v?.isApproved ? d.raids ?? [] : [],
    }
  }

  async updateMember(memberId: string, patch: Partial<GuildData['members'][number]>) {
    this.change((d) => {
      const m = d.members.find((x) => x.id === memberId)
      if (m) Object.assign(m, patch)
    })
  }

  async removeMember(memberId: string) {
    this.change((d) => {
      d.members = d.members.filter((m) => m.id !== memberId)
      d.characters = d.characters.filter((c) => c.member_id !== memberId)
      d.availability = d.availability.filter((a) => a.member_id !== memberId)
      d.signups = d.signups.filter((s) => s.member_id !== memberId)
      d.officerNotes = d.officerNotes.filter((n) => n.member_id !== memberId)
    })
  }

  async saveCharacter(c: Parameters<Store['saveCharacter']>[0]) {
    this.change((d) => {
      const id = c.id ?? `c${Date.now()}`
      const mine = d.characters.filter((x) => x.member_id === c.member_id)
      const row = { ...c, id, is_main: c.is_main || mine.length === 0 }
      if (row.is_main) mine.forEach((x) => (x.is_main = false))
      const i = d.characters.findIndex((x) => x.id === id)
      if (i >= 0) d.characters[i] = row
      else d.characters.push(row)
    })
  }

  async deleteCharacter(id: string) {
    this.change((d) => {
      const gone = d.characters.find((c) => c.id === id)
      d.characters = d.characters.filter((c) => c.id !== id)
      d.signups = d.signups.filter((s) => s.character_id !== id)
      if (gone?.is_main) {
        const next = d.characters.find((c) => c.member_id === gone.member_id)
        if (next) next.is_main = true
      }
    })
  }

  async setMain(memberId: string, characterId: string) {
    this.change((d) => d.characters.forEach((c) => {
      if (c.member_id === memberId) c.is_main = c.id === characterId
    }))
  }

  async saveAvailability(memberId: string, slots: number[]) {
    this.change((d) => {
      d.availability = d.availability.filter((a) => a.member_id !== memberId)
      d.availability.push({ member_id: memberId, slots })
    })
  }

  async saveEvent(e: Parameters<Store['saveEvent']>[0]) {
    this.change((d) => {
      const i = d.events.findIndex((x) => x.id === e.id)
      if (i >= 0) d.events[i] = { ...d.events[i], ...e, id: d.events[i].id }
      else d.events.push({ ...e, id: `e${Date.now()}`, created_by: this.me() ?? '' })
    })
  }

  async deleteEvent(id: string) {
    this.change((d) => {
      d.events = d.events.filter((e) => e.id !== id)
      d.signups = d.signups.filter((s) => s.event_id !== id)
    })
  }

  async saveSignup(s: Parameters<Store['saveSignup']>[0]) {
    this.change((d) => {
      d.signups = d.signups.filter((x) => !(x.event_id === s.event_id && x.member_id === s.member_id))
      d.signups.push(s)
    })
  }

  async deleteSignup(eventId: string, memberId: string) {
    this.change((d) => {
      d.signups = d.signups.filter((x) => !(x.event_id === eventId && x.member_id === memberId))
    })
  }

  async importCharacters(memberId: string, chars: Parameters<Store['importCharacters']>[1]) {
    const rows = mergeImport(this.read().characters.filter((c) => c.member_id === memberId), memberId, chars)
    for (const r of rows) await this.saveCharacter(r)
  }

  async saveInGameRoster(r: Parameters<Store['saveInGameRoster']>[0]) {
    this.change((d) => (d.inGame = r))
  }

  async saveBank(b: Parameters<Store['saveBank']>[0]) {
    this.change((d) => (d.bank = b))
  }

  async importRaids(raids: Parameters<Store['importRaids']>[0]) {
    this.change((d) => {
      const all = [...(d.raids ?? [])]
      for (const r of raids) {
        const i = all.findIndex((x) => x.key === r.key)
        if (i >= 0) all[i] = mergeRaid(all[i]!, r)
        else all.push(r)
      }
      d.raids = all
    })
  }

  async saveOfficerNote(memberId: string, note: string) {
    this.change((d) => {
      d.officerNotes = d.officerNotes.filter((n) => n.member_id !== memberId)
      if (note.trim()) d.officerNotes.push({ member_id: memberId, note, updated_at: new Date().toISOString() })
    })
  }

  async saveRank(r: Parameters<Store['saveRank']>[0]) {
    this.change((d) => {
      if (r.id) d.ranks = d.ranks.map((x) => (x.id === r.id ? { ...x, ...r, id: x.id } : x))
      else d.ranks.push({ ...r, id: Math.max(0, ...d.ranks.map((x) => x.id)) + 1 })
    })
  }

  async deleteRank(id: number) {
    this.change((d) => {
      d.ranks = d.ranks.filter((r) => r.id !== id)
      d.members.forEach((m) => { if (m.rank_id === id) m.rank_id = null })
    })
  }

  async updateGuild(g: GuildData['guild']) {
    this.change((d) => (d.guild = g))
  }
}
