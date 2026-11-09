// discord-announce: the guild's own database calls it (a trigger through pg_net, and the reminder cron job)
// whenever an event or its sign-ups change. It keeps one Discord post per event in step with the site.
//
// Bursts are coalesced in the database (public.discord_claim_sync): at most one post or edit per event every
// few seconds; a change inside that gap makes one caller wait and then edit with everything, the rest skip.

import { eventMessage, isOver, reminderMessage, type EventView, type ReminderView } from './message.ts'
import { DiscordError, type Db, type Discord } from './rest.ts'

export type AnnounceBody =
  | { kind: 'event'; event_id: string } // created or edited on the site: post it if it isn't up yet
  | { kind: 'counts'; event_id: string } // a sign-up changed: edit the post's counts
  | { kind: 'delete'; message_id: string } // deleted on the site
  | { kind: 'reminders' } // the cron job saw an event starting soon

export interface AnnounceDeps {
  db: Db
  discord: Discord
  channelId: string
  siteUrl: string
  now: () => number
  sleep: (ms: number) => Promise<void>
  log: (...a: unknown[]) => void
}

type Claim = { action: 'now'; post: boolean } | { action: 'wait'; wait_ms: number } | { action: 'skip' }

const MAX_WAITS = 5

export function parseAnnounceBody(x: unknown): AnnounceBody | null {
  if (!x || typeof x !== 'object') return null
  const b = x as Record<string, unknown>
  const str = (v: unknown) => typeof v === 'string' && v.length > 0 && v.length < 100
  if ((b.kind === 'event' || b.kind === 'counts') && str(b.event_id)) return { kind: b.kind, event_id: b.event_id as string }
  if (b.kind === 'delete' && str(b.message_id)) return { kind: 'delete', message_id: b.message_id as string }
  if (b.kind === 'reminders') return { kind: 'reminders' }
  return null
}

/** Checks the caller is our database, then answers at once; the work carries on in `work`. */
export async function announceRequest(deps: AnnounceDeps, req: Request): Promise<{ response: Response; work?: Promise<void> }> {
  if (req.method !== 'POST') return { response: new Response('POST only', { status: 405 }) }
  const secret = req.headers.get('x-hook-secret') ?? ''
  if (!secret || !(await deps.db.rpc<boolean>('discord_hook_ok', { p_secret: secret }))) return { response: new Response('Unauthorized', { status: 401 }) }
  let body: AnnounceBody | null = null
  try { body = parseAnnounceBody(await req.json()) } catch { /* not JSON */ }
  if (!body) return { response: new Response('Bad request', { status: 400 }) }
  const work = handleAnnounce(deps, body).catch((e) => deps.log('discord-announce failed', body, e))
  return { response: new Response('Accepted', { status: 202 }), work }
}

export async function handleAnnounce(deps: AnnounceDeps, body: AnnounceBody): Promise<void> {
  if (body.kind === 'delete') return remove(deps, body.message_id)
  if (body.kind === 'reminders') return remind(deps)
  return sync(deps, body.event_id, body.kind === 'event')
}

async function sync(deps: AnnounceDeps, eventId: string, post: boolean): Promise<void> {
  for (let waits = 0; waits <= MAX_WAITS; waits++) {
    const claim = await deps.db.rpc<Claim>('discord_claim_sync', { p_event: eventId, p_post: post, p_waiter: waits > 0 })
    if (claim.action === 'skip') return
    if (claim.action === 'wait') {
      await deps.sleep(Math.min(20000, Math.max(250, claim.wait_ms)))
      continue
    }
    try {
      await syncNow(deps, eventId, claim.post)
    } finally {
      await deps.db.rpc('discord_sync_done', { p_event: eventId })
    }
    return
  }
  deps.log('discord-announce gave up waiting for its turn', eventId)
}

const gone = (e: unknown) => e instanceof DiscordError && e.status === 404

/** Make the event's post match the site: edit it, or post it when it isn't up (and the change allows posting). */
async function syncNow(deps: AnnounceDeps, eventId: string, mayPost: boolean): Promise<void> {
  const e = await deps.db.rpc<EventView | null>('discord_event_view', { p_event: eventId })
  if (!e) return
  const msg = eventMessage(e, deps.siteUrl, deps.now())
  if (e.discord_message_id) {
    try {
      await deps.discord.request('PATCH', `/channels/${deps.channelId}/messages/${e.discord_message_id}`, msg)
      return
    } catch (err) {
      if (!gone(err)) throw err
      // The post was deleted in Discord (or the channel changed): forget it; an edit on the site posts it again.
      await deps.db.rpc('discord_set_message', { p_event: eventId, p_message: null })
    }
  }
  if (!mayPost || isOver(e, deps.now())) return
  const sent = await deps.discord.request<{ id: string }>('POST', `/channels/${deps.channelId}/messages`, msg)
  await deps.db.rpc('discord_set_message', { p_event: eventId, p_message: sent.id })
}

async function remove(deps: AnnounceDeps, messageId: string): Promise<void> {
  try {
    await deps.discord.request('DELETE', `/channels/${deps.channelId}/messages/${messageId}`)
  } catch (err) {
    if (!gone(err)) throw err
  }
}

async function remind(deps: AnnounceDeps): Promise<void> {
  const due = await deps.db.rpc<ReminderView[] | null>('discord_claim_reminders', {})
  for (const r of due ?? []) {
    try {
      await deps.discord.request('POST', `/channels/${deps.channelId}/messages`, reminderMessage(r))
    } catch (err) {
      deps.log('reminder failed', r.id, err)
      await deps.db.rpc('discord_unclaim_reminder', { p_event: r.id }) // the next tick tries again, until it starts
    }
  }
}
