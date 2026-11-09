// What the bot says in Discord: the event post with its buttons, the button's custom id, the one-line
// replies to a press, and the reminder. Plain functions, no I/O: the Edge Functions and the tests share them.

export type Role = 'tank' | 'healer' | 'dps'
export type Status = 'in' | 'maybe' | 'out'
export type Choice = Role | 'out'

export const ROLES: Role[] = ['tank', 'healer', 'dps']
// The site's own names (src/wow.ts ROLES), so Discord and the Events page read the same.
export const ROLE_NAME: Record<Role, string> = { tank: 'Tank', healer: 'Healer', dps: 'DPS' }

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
  signups: { role: Role; status: Status }[]
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

/** The event's place on the site: the Events page scrolled to it. */
export function eventUrl(siteUrl: string, eventId: string): string {
  return `${siteUrl.replace(/#.*$/, '').replace(/\/?$/, '/')}#/events/${eventId}`
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

const COLOUR = 0xcf3f7d // the site's accent
const clip = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1)}…` : s)

function hours(minutes: number): string {
  const h = minutes / 60
  return `${Number.isInteger(h) ? h : h.toFixed(1)} ${h === 1 ? 'hour' : 'hours'}`
}

/** The message body for POST/PATCH /channels/{id}/messages. Nobody is pinged by it. */
export function eventMessage(e: EventView, siteUrl: string, nowMs: number) {
  const t = unix(e.starts_at)
  const { going, maybe, out } = roleCounts(e.signups)
  const need: Record<Role, number> = { tank: e.need_tank, healer: e.need_healer, dps: e.need_dps }
  const over = isOver(e, nowMs)
  const others = [maybe ? `Maybe ${maybe}` : '', out ? `Can't make it ${out}` : ''].filter(Boolean).join(' · ')
  const button = (choice: Choice, label: string, style: number) => ({ type: 2, style, label, custom_id: customId(e.id, choice), disabled: over })
  return {
    content: '',
    embeds: [{
      title: clip(e.title, 256),
      url: eventUrl(siteUrl, e.id),
      color: COLOUR,
      description: [`<t:${t}:F> (<t:${t}:R>), ${hours(e.duration_minutes)}`, clip(e.description.trim(), 3000)].filter(Boolean).join('\n\n'),
      fields: ROLES.map((r) => ({ name: ROLE_NAME[r], value: `${going[r]}/${need[r]}`, inline: true })),
      ...(others ? { footer: { text: others } } : {}),
    }],
    components: [{
      type: 1,
      components: [
        ...ROLES.map((r) => button(r, ROLE_NAME[r], 1)),
        button('out', "Can't make it", 2),
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
    return group.length ? [`**${ROLE_NAME[r]}** (${group.length}): ${group.map((p) => (p.discord_id ? `<@${p.discord_id}>` : p.name)).join(' ')}`] : []
  })
}

/** The reminder, a reply to the event's post that pings only the people going. */
export function reminderMessage(r: ReminderView) {
  const head = `**${r.title}** starts <t:${unix(r.starts_at)}:R>.`
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
