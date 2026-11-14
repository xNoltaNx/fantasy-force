// Kill-on-sight marks a member makes in game go out to Discord by themselves: each time the site reads their
// saved file (SavedFileSync), marks they made since auto-sending began that the site doesn't know yet are
// added to the list, which broadcasts them. Marks synced in from guildmates' addons are left to their makers,
// and anything older stays a one-click chip on the Kill on sight page.
import type { ImportedKos } from './addonFile'
import { kosKey, type KosInput } from './store/store'
import type { GuildData } from './types'

/** What a sent mark is remembered by, so it goes out once even if it's deleted on the site after. */
export const sentKey = (k: ImportedKos) => `${kosKey(k.name)}@${k.added}`

/** A character name as the addon writes it, without a realm. */
const bare = (s: string) => kosKey(s.split('-')[0] ?? '')

/** The marks to send now: made by one of the member's characters after `since` (unix seconds), not sent before,
 *  and newer than anything the site has on that name (a mark there, made or cleared since, wins). */
export function marksToSend(marks: ImportedKos[], data: GuildData, memberId: string, since: number, sent: string[]): ImportedKos[] {
  const mine = new Set(data.characters.filter((c) => c.member_id === memberId).map((c) => bare(c.name)))
  return marks.filter((k) => {
    if (k.added <= since || !mine.has(bare(k.by)) || sent.includes(sentKey(k))) return false
    const at = k.added * 1000
    return !data.kos.some((m) => kosKey(m.name) === kosKey(k.name) && (!m.cleared_at || Date.parse(m.created_at) >= at || Date.parse(m.cleared_at) >= at))
  })
}

export const kosInput = (k: ImportedKos): KosInput => ({
  name: k.name, level: k.level, race: k.race, class_id: k.class_id, guild: k.guild, zone: '', reason: k.reason, danger: 2,
})
