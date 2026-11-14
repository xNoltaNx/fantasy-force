// What the bot says in Discord: the event post with its buttons, the button's custom id, the one-line
// replies to a press, the reminder, and the kill-on-sight broadcast. Plain functions, no I/O and no imports:
// the Edge Functions, the tests and the site's Discord preview (src/discordPreview.tsx) all share them.

export type Role = 'tank' | 'healer' | 'dps'
export type Status = 'in' | 'maybe' | 'out'
export type Choice = Role | 'out'

export const ROLES: Role[] = ['tank', 'healer', 'dps']
// The site's own names (src/wow.ts ROLES), so Discord and the Events page read the same.
export const ROLE_NAME: Record<Role, string> = { tank: 'Tank', healer: 'Healer', dps: 'DPS' }
export const ROLE_EMOJI: Record<Role, string> = { tank: '🛡️', healer: '💚', dps: '⚔️' }

/** An event as the database hands it to the bot (public.discord_event_view). */
export interface EventView {
  id: string
  title: string
  starts_at: string
  duration_minutes: number
  description: string
  need_tank: number
  need_healer: number
  need_dps: number
  discord_message_id: string | null
  /** name: the character signed up (else the member's name); absent from a database older than the names. */
  signups: { role: Role; status: Status; name?: string }[]
  guild_name?: string
}

/** One event due a reminder, with who's going (public.discord_claim_reminders). */
export interface ReminderView {
  id: string
  title: string
  starts_at: string
  message_id: string | null
  people: { role: Role; name: string; discord_id: string | null }[]
}

export const unix = (iso: string) => Math.floor(Date.parse(iso) / 1000)

export const isOver = (e: Pick<EventView, 'starts_at' | 'duration_minutes'>, nowMs: number) =>
  Date.parse(e.starts_at) + e.duration_minutes * 60000 < nowMs

/** The site's address with one trailing slash and no #route. */
export function siteBase(siteUrl: string): string {
  return siteUrl.replace(/#.*$/, '').replace(/\/?$/, '/')
}

/** The event's place on the site: the Events page scrolled to it. */
export function eventUrl(siteUrl: string, eventId: string): string {
  return `${siteBase(siteUrl)}#/events/${eventId}`
}

/** Pictures the posts show, served with the site (public/discord, public/favicon.png). */
export function artUrl(siteUrl: string, file: 'logo' | 'icon' | 'kos'): string {
  const path = { logo: 'discord/logo.jpg', icon: 'favicon.png', kos: 'discord/kos.png' }[file]
  return `${siteBase(siteUrl)}${path}`
}

/** Going (status in) per role, and how many said maybe or can't make it. */
export function roleCounts(signups: EventView['signups']) {
  const going: Record<Role, number> = { tank: 0, healer: 0, dps: 0 }
  let maybe = 0
  let out = 0
  for (const s of signups) {
    if (s.status === 'in') going[s.role]++
    else if (s.status === 'maybe') maybe++
    else out++
  }
  return { going, maybe, out }
}

// ---------- Text helpers ----------

const clip = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1)}…` : s)

/** Someone's typing shown as plain text: Discord's markdown characters escaped. */
export function plain(s: string): string {
  return s.replace(/([\\*_~`|>[\]])/g, '\\$1')
}

/** A progress bar of `width` segments; anyone at all shows at least one. */
export function bar(have: number, need: number, width = 8): string {
  const filled = need <= 0 ? (have > 0 ? width : 0) : Math.min(width, Math.max(have > 0 ? 1 : 0, Math.round((have / need) * width)))
  return '▰'.repeat(filled) + '▱'.repeat(width - filled)
}

// ---------- Button ids ----------

const CHOICES: Choice[] = ['tank', 'healer', 'dps', 'out']
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** "ff:<event id>:<tank|healer|dps|out>", well inside Discord's 100 characters. */
export function customId(eventId: string, choice: Choice): string {
  return `ff:${eventId}:${choice}`
}

export function parseCustomId(id: string): { eventId: string; choice: Choice } | null {
  const [tag, eventId, choice, ...rest] = id.split(':')
  if (tag !== 'ff' || rest.length || !eventId || !UUID.test(eventId) || !CHOICES.includes(choice as Choice)) return null
  return { eventId: eventId.toLowerCase(), choice: choice as Choice }
}

// ---------- The event post ----------

export const COLOUR = {
  event: 0xcf3f7d, // the site's accent
  full: 0x7fd1b4, // every role filled: the site's mint
  over: 0x4f545c, // Discord's grey
}

const MAX_NAMES = 12 // per role field, then "+3 more"

function hours(minutes: number): string {
  const h = minutes / 60
  return `${Number.isInteger(h) ? h : h.toFixed(1)} ${h === 1 ? 'hour' : 'hours'}`
}

function roleField(role: Role, have: number, need: number, names: string[]) {
  const full = need > 0 && have >= need
  const shown = names.slice(0, MAX_NAMES).map(plain)
  if (names.length > MAX_NAMES) shown.push(`*+${names.length - MAX_NAMES} more*`)
  return {
    name: `${ROLE_EMOJI[role]} ${ROLE_NAME[role]}  ${have}/${need}${full ? ' ✓' : ''}`,
    value: [`\`${bar(have, need)}\``, ...shown].join('\n'),
    inline: true,
  }
}

/** The message body for POST/PATCH /channels/{id}/messages. Nobody is pinged by it. */
export function eventMessage(e: EventView, siteUrl: string, nowMs: number) {
  const t = unix(e.starts_at)
  const { going, maybe, out } = roleCounts(e.signups)
  const need: Record<Role, number> = { tank: e.need_tank, healer: e.need_healer, dps: e.need_dps }
  const over = isOver(e, nowMs)
  const needTotal = need.tank + need.healer + need.dps
  const goingTotal = going.tank + going.healer + going.dps
  const full = needTotal > 0 && ROLES.every((r) => going[r] >= need[r])
  const namesFor = (r: Role) => e.signups.filter((s) => s.status === 'in' && s.role === r && s.name).map((s) => s.name!)
  const details = clip(e.description.trim(), 3000)

  const description = [
    `🗓️ **<t:${t}:F>** · <t:${t}:R>`,
    `⏳ ${hours(e.duration_minutes)} · 👥 **${goingTotal}** going${needTotal ? ` of ${needTotal}` : ''}${full && !over ? ' · ✅ **Roster full**' : ''}`,
    ...(details ? ['', `>>> ${details}`] : []),
  ].join('\n')
  const footer = [
    ...(maybe ? [`Maybe ${maybe}`] : []),
    ...(out ? [`Can't make it ${out}`] : []),
    over ? 'This event is over' : 'Press a role below to sign up',
  ].join(' · ')

  const button = (choice: Choice, label: string, emoji: string, style: number) =>
    ({ type: 2, style, label, emoji: { name: emoji }, custom_id: customId(e.id, choice), disabled: over })
  return {
    content: '',
    embeds: [{
      author: { name: `${e.guild_name || 'Guild'} · Guild event`, icon_url: artUrl(siteUrl, 'icon'), url: `${siteBase(siteUrl)}#/events` },
      title: clip(e.title, 256),
      url: eventUrl(siteUrl, e.id),
      color: over ? COLOUR.over : full ? COLOUR.full : COLOUR.event,
      description,
      thumbnail: { url: artUrl(siteUrl, 'logo') },
      fields: ROLES.map((r) => roleField(r, going[r], need[r], namesFor(r))),
      footer: { text: footer },
    }],
    components: [{
      type: 1,
      components: [
        button('tank', ROLE_NAME.tank, ROLE_EMOJI.tank, 1), // blurple
        button('healer', ROLE_NAME.healer, ROLE_EMOJI.healer, 3), // green
        button('dps', ROLE_NAME.dps, ROLE_EMOJI.dps, 4), // red
        button('out', "Can't make it", '✖️', 2), // grey
        { type: 2, style: 5, label: 'Details', url: eventUrl(siteUrl, e.id) }, // a link
      ],
    }],
    allowed_mentions: { parse: [] as string[] },
  }
}

// ---------- A press, answered ----------

/** What public.discord_button did. */
export interface ButtonResult {
  result: 'in' | 'out' | 'no_event' | 'over' | 'not_member' | 'waiting' | 'no_character'
  title?: string
  role?: Role
  character?: string
}

/** The one ephemeral line a press gets back. */
export function buttonReply(r: ButtonResult, siteUrl: string): string {
  const site = siteUrl.replace(/#.*$/, '')
  const title = r.title ?? 'the event'
  switch (r.result) {
    case 'in': return `You're in as ${ROLE_NAME[r.role ?? 'dps']}${r.character ? ` on ${r.character}` : ''} for ${title}.`
    case 'out': return `Marked as not coming to ${title}.`
    case 'over': return `${title} is over.`
    case 'no_event': return 'That event is no longer on the guild site.'
    case 'not_member': return `Sign in on the guild site with Discord first, then press the button again: ${site}`
    case 'waiting': return `An officer still has to approve you on the guild site. Once they have, press the button again: ${site}`
    case 'no_character': return `Add a character on the guild site first, then press the button again: ${site.replace(/\/?$/, '/')}#/me`
  }
}

// ---------- The reminder ----------

const MAX_CONTENT = 2000 // Discord's limit
const MAX_MENTIONS = 100 // allowed_mentions.users holds at most 100

/** Who's going, by role, as mentions (a name when someone has no Discord sign-in). */
export function reminderLines(people: ReminderView['people']): string[] {
  return ROLES.flatMap((r) => {
    const group = people.filter((p) => p.role === r)
    return group.length ? [`${ROLE_EMOJI[r]} **${ROLE_NAME[r]}** (${group.length}): ${group.map((p) => (p.discord_id ? `<@${p.discord_id}>` : plain(p.name))).join(' ')}`] : []
  })
}

/** The reminder, a reply to the event's post that pings only the people going. */
export function reminderMessage(r: ReminderView) {
  const head = `⏰ **${r.title}** starts <t:${unix(r.starts_at)}:R>. Time to log in!`
  const lines = reminderLines(r.people)
  let content = [head, ...(lines.length ? lines : ['Nobody has signed up yet.'])].join('\n')
  if (content.length > MAX_CONTENT) content = `${content.slice(0, content.lastIndexOf(' ', MAX_CONTENT - 2))} …` // never half a mention
  const users = [...new Set(r.people.map((p) => p.discord_id).filter((id): id is string => !!id))].slice(0, MAX_MENTIONS)
  return {
    content,
    allowed_mentions: { parse: [] as string[], users, replied_user: false },
    ...(r.message_id ? { message_reference: { message_id: r.message_id, fail_if_not_exists: false } } : {}),
  }
}

// ---------- Kill on sight ----------

/** A kill-on-sight mark as the database hands it to the bot (public.discord_kos_view). */
export interface KosView {
  id: string
  name: string
  level: number | null
  race: string // the site's race id (src/wow.ts RACES), '' unknown
  class_id: string // the site's class id, '' unknown
  guild: string
  zone: string
  reason: string
  danger: number // 1 to 3
  created_at: string
  updated_at: string
  cleared_at: string | null
  marked_by: string // the marker's main character, else their name
  cleared_by: string | null
  discord_message_id: string | null
  guild_name?: string
}

// The same as src/wow.ts (a test keeps them in step); the functions can't reach the site's files.
export const CLASS_NAME: Record<string, string> = {
  druid: 'Druid', hunter: 'Hunter', mage: 'Mage', paladin: 'Paladin', priest: 'Priest',
  rogue: 'Rogue', shaman: 'Shaman', warlock: 'Warlock', warrior: 'Warrior',
}
export const RACE_NAME: Record<string, string> = {
  human: 'Human', dwarf: 'Dwarf', gnome: 'Gnome', nightelf: 'Night Elf', orc: 'Orc',
  undead: 'Undead', tauren: 'Tauren', troll: 'Troll', skyborne: 'Skyborne',
}

export const THREATS = [
  { level: 1, name: 'Pest', skulls: '☠️', colour: 0xe8833a },
  { level: 2, name: 'Menace', skulls: '☠️☠️', colour: 0xd1202f },
  { level: 3, name: 'Public enemy', skulls: '☠️☠️☠️', colour: 0x9b111e },
] as const

export function threat(danger: number) {
  return THREATS[Math.min(3, Math.max(1, Math.round(danger || 2))) - 1]!
}

/** "Level 32 Night Elf Druid", as much as is known. */
export function kosWho(k: Pick<KosView, 'level' | 'race' | 'class_id'>): string {
  return [k.level ? `Level ${k.level}` : '', RACE_NAME[k.race] ?? '', CLASS_NAME[k.class_id] ?? ''].filter(Boolean).join(' ')
}

export function kosUrl(siteUrl: string, id: string): string {
  return `${siteBase(siteUrl)}#/kos/${id}`
}

/** What a guildmate types to put the mark on their own addon (it's then shared with everyone else's). */
export function kosCommand(k: Pick<KosView, 'name' | 'reason'>): string {
  const why = clip(k.reason.replace(/[`\s]+/g, ' ').trim(), 80)
  return `/ff kos ${k.name.replace(/`/g, '')}${why ? ` - ${why}` : ''}`
}

/**
 * The broadcast. `post`: a new message (the role, when set, is pinged once; an edit never pings).
 * A cleared mark stays in the channel, greyed and struck through.
 */
export function kosMessage(k: KosView, siteUrl: string, opts: { roleId?: string; post: boolean }) {
  const cleared = !!k.cleared_at
  const t = threat(k.danger)
  const name = clip(k.name, 48)
  const who = kosWho(k)
  const guild = k.guild.trim() ? `<${plain(clip(k.guild.trim(), 48))}>` : ''
  const ping = opts.roleId && !cleared ? `<@&${opts.roleId}> ` : ''
  const headline = [who ? `**${who}**` : '', guild].filter(Boolean).join('  ')
  const reason = clip(k.reason.trim(), 1000)

  const fields = cleared
    ? [
        { name: 'Cleared by', value: plain(k.cleared_by || 'Someone'), inline: true },
        { name: 'Cleared', value: `<t:${unix(k.cleared_at!)}:R>`, inline: true },
        { name: 'Was marked by', value: plain(k.marked_by || 'Someone'), inline: true },
      ]
    : [
        { name: 'Threat', value: `${t.skulls} **${t.name}**`, inline: true },
        { name: '📍 Last seen', value: k.zone.trim() ? plain(clip(k.zone.trim(), 80)) : '*Somewhere out there*', inline: true },
        { name: '🎯 Marked by', value: plain(k.marked_by || 'Someone'), inline: true },
        { name: 'Mark it in your addon', value: `\`${kosCommand(k)}\``, inline: false },
      ]

  return {
    content: cleared
      ? `✅ ~~**${plain(name)}**~~ is no longer kill on sight.`
      : `${ping}${k.danger >= 3 ? '🚨' : '☠️'} **${plain(name)}** is now kill on sight.`,
    embeds: [{
      author: { name: cleared ? 'CLEARED · No longer kill on sight' : 'KILL ON SIGHT', icon_url: artUrl(siteUrl, 'kos') },
      title: cleared ? `${name} (cleared)` : name.toUpperCase(),
      url: kosUrl(siteUrl, k.id),
      color: cleared ? COLOUR.over : t.colour,
      description: [cleared ? `~~${headline || 'Unknown'}~~` : headline || '*Unknown level, race and class*', ...(reason ? [`>>> ${reason}`] : [])].join('\n'),
      ...(cleared ? {} : { thumbnail: { url: artUrl(siteUrl, 'kos') } }),
      fields,
      footer: { text: `${k.guild_name || 'Guild'} · Kill on sight list`, icon_url: artUrl(siteUrl, 'icon') },
      timestamp: k.created_at,
    }],
    components: [{ type: 1, components: [{ type: 2, style: 5, label: 'Kill on sight list', emoji: { name: '☠️' }, url: kosUrl(siteUrl, k.id) }] }],
    allowed_mentions: { parse: [] as string[], roles: opts.post && ping ? [opts.roleId!] : [] as string[] },
  }
}
