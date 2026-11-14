import { describe, expect, it } from 'vitest'
import { announceRequest, handleAnnounce, parseAnnounceBody, type AnnounceDeps } from './announce.ts'
import type { EventView, KosView } from './message.ts'
import { DiscordError } from './rest.ts'

const ID = '0b6f8e2c-1d3a-4c5b-9e7f-112233445566'
const NOW = Date.parse('2026-11-10T00:00:00Z')

const view = (o: Partial<EventView> = {}): EventView => ({
  id: ID, title: 'Molten Core', starts_at: '2026-11-11T03:00:00Z', duration_minutes: 180, description: '',
  need_tank: 2, need_healer: 3, need_dps: 15, discord_message_id: null, signups: [], ...o,
})

type Rpc = (args: Record<string, unknown>) => unknown

function fake(rpcs: Record<string, Rpc>, discordAnswer: (method: string, path: string) => unknown = () => ({ id: 'm1' })) {
  const log: string[] = []
  const sleeps: number[] = []
  const deps: AnnounceDeps = {
    db: {
      rpc: async <T,>(name: string, args: Record<string, unknown>) => {
        log.push(`db ${name} ${JSON.stringify(args)}`)
        const f = rpcs[name]
        return (f ? f(args) : null) as T
      },
    },
    discord: {
      request: async <T,>(method: string, path: string) => {
        log.push(`discord ${method} ${path}`)
        const a = discordAnswer(method, path)
        if (a instanceof Error) throw a
        return a as T
      },
    },
    channelId: 'c1', kosChannelId: 'k1', siteUrl: 'https://site/', now: () => NOW, sleep: async (ms) => void sleeps.push(ms), log: () => {},
  }
  return { deps, log, sleeps }
}

const claims = (...answers: unknown[]) => () => answers.shift()

describe('sync', () => {
  it('posts a new event and remembers the message', async () => {
    const { deps, log } = fake({ discord_claim_sync: claims({ action: 'now', post: true }), discord_event_view: () => view() })
    await handleAnnounce(deps, { kind: 'event', event_id: ID })
    expect(log).toEqual([
      `db discord_claim_sync {"p_event":"${ID}","p_post":true,"p_waiter":false}`,
      `db discord_event_view {"p_event":"${ID}"}`,
      'discord POST /channels/c1/messages',
      `db discord_set_message {"p_event":"${ID}","p_message":"m1"}`,
      `db discord_sync_done {"p_event":"${ID}"}`,
    ])
  })

  it('edits the post when a sign-up changes', async () => {
    const { deps, log } = fake({ discord_claim_sync: claims({ action: 'now', post: false }), discord_event_view: () => view({ discord_message_id: 'm9' }) })
    await handleAnnounce(deps, { kind: 'counts', event_id: ID })
    expect(log.filter((l) => l.startsWith('discord'))).toEqual(['discord PATCH /channels/c1/messages/m9'])
  })

  it('waits its turn inside a burst, then edits once', async () => {
    const { deps, log, sleeps } = fake({
      discord_claim_sync: claims({ action: 'wait', wait_ms: 3200 }, { action: 'now', post: false }),
      discord_event_view: () => view({ discord_message_id: 'm9' }),
    })
    await handleAnnounce(deps, { kind: 'counts', event_id: ID })
    expect(sleeps).toEqual([3200])
    expect(log[1]).toContain('"p_waiter":true')
    expect(log.filter((l) => l.startsWith('discord'))).toHaveLength(1)
  })

  it('does nothing when another call is already waiting', async () => {
    const { deps, log } = fake({ discord_claim_sync: claims({ action: 'skip' }) })
    await handleAnnounce(deps, { kind: 'counts', event_id: ID })
    expect(log).toHaveLength(1)
  })

  it('a sign-up never posts: a post deleted in Discord is forgotten', async () => {
    const { deps, log } = fake(
      { discord_claim_sync: claims({ action: 'now', post: false }), discord_event_view: () => view({ discord_message_id: 'm9' }) },
      () => new DiscordError(404, '{"code":10008}'),
    )
    await handleAnnounce(deps, { kind: 'counts', event_id: ID })
    expect(log.filter((l) => !l.includes('claim_sync') && !l.includes('event_view'))).toEqual([
      'discord PATCH /channels/c1/messages/m9',
      `db discord_set_message {"p_event":"${ID}","p_message":null}`,
      `db discord_sync_done {"p_event":"${ID}"}`,
    ])
  })

  it('an edit on the site posts it again', async () => {
    const { deps, log } = fake(
      { discord_claim_sync: claims({ action: 'now', post: true }), discord_event_view: () => view({ discord_message_id: 'm9' }) },
      (method) => (method === 'PATCH' ? new DiscordError(404, '') : { id: 'm10' }),
    )
    await handleAnnounce(deps, { kind: 'event', event_id: ID })
    expect(log.filter((l) => l.startsWith('discord') || l.includes('set_message'))).toEqual([
      'discord PATCH /channels/c1/messages/m9',
      `db discord_set_message {"p_event":"${ID}","p_message":null}`,
      'discord POST /channels/c1/messages',
      `db discord_set_message {"p_event":"${ID}","p_message":"m10"}`,
    ])
  })

  it('never posts an event that is over', async () => {
    const { deps, log } = fake({ discord_claim_sync: claims({ action: 'now', post: true }), discord_event_view: () => view({ starts_at: '2026-11-01T00:00:00Z' }) })
    await handleAnnounce(deps, { kind: 'event', event_id: ID })
    expect(log.some((l) => l.startsWith('discord'))).toBe(false)
  })

  it('frees the event even when Discord fails', async () => {
    const { deps, log } = fake(
      { discord_claim_sync: claims({ action: 'now', post: false }), discord_event_view: () => view({ discord_message_id: 'm9' }) },
      () => new DiscordError(500, 'oops'),
    )
    await expect(handleAnnounce(deps, { kind: 'counts', event_id: ID })).rejects.toThrow('Discord 500')
    expect(log.at(-1)).toContain('discord_sync_done')
  })
})

describe('delete and reminders', () => {
  it('deletes the post, and shrugs if it is already gone', async () => {
    const { deps, log } = fake({}, () => new DiscordError(404, ''))
    await handleAnnounce(deps, { kind: 'delete', message_id: 'm9' })
    expect(log).toEqual(['discord DELETE /channels/c1/messages/m9'])
  })

  it('posts each due reminder, and hands back one that failed', async () => {
    const due = [
      { id: 'a', title: 'A', starts_at: '2026-11-10T01:00:00Z', message_id: 'm1', people: [] },
      { id: 'b', title: 'B', starts_at: '2026-11-10T01:00:00Z', message_id: 'm2', people: [] },
    ]
    let n = 0
    const { deps, log } = fake({ discord_claim_reminders: () => due }, () => (n++ === 1 ? new DiscordError(403, 'Missing Access') : { id: 'r' }))
    await handleAnnounce(deps, { kind: 'reminders' })
    expect(log).toEqual([
      'db discord_claim_reminders {}',
      'discord POST /channels/c1/messages',
      'discord POST /channels/c1/messages',
      'db discord_unclaim_reminder {"p_event":"b"}',
    ])
  })
})

describe('kill on sight', () => {
  const KOS = '7c1d2e3f-4a5b-4c6d-8e9f-a0b1c2d3e4f5'
  const mark = (o: Partial<KosView> = {}): KosView => ({
    id: KOS, name: 'Itz Shifty', level: 32, race: 'nightelf', class_id: 'druid', guild: '', zone: '', reason: '', danger: 2,
    created_at: '2026-11-12T20:00:00Z', updated_at: '2026-11-12T20:00:00Z', cleared_at: null, marked_by: 'Azujin', cleared_by: null,
    discord_message_id: null, ...o,
  })
  const posted = (log: string[]) => log.filter((l) => l.startsWith('discord') || l.includes('set_kos') || l.includes('claim_kos'))

  it('posts a new mark in its own channel and remembers the post', async () => {
    const { deps, log } = fake({ discord_kos_view: () => mark(), discord_claim_kos_post: () => true }, () => ({ id: 'p1' }))
    await handleAnnounce(deps, { kind: 'kos', kos_id: KOS })
    expect(posted(log)).toEqual([
      `db discord_claim_kos_post {"p_kos":"${KOS}"}`,
      'discord POST /channels/k1/messages',
      `db discord_set_kos_message {"p_kos":"${KOS}","p_message":"p1"}`,
    ])
  })

  it('posts nothing when another call is already posting it', async () => {
    const { deps, log } = fake({ discord_kos_view: () => mark(), discord_claim_kos_post: () => false })
    await handleAnnounce(deps, { kind: 'kos', kos_id: KOS })
    expect(log.some((l) => l.startsWith('discord'))).toBe(false)
  })

  it('edits in a change made while it was posting', async () => {
    const views = [mark(), mark({ updated_at: '2026-11-12T20:00:03Z', reason: 'camping the flight master' })]
    const { deps, log } = fake({ discord_kos_view: () => views.shift(), discord_claim_kos_post: () => true }, () => ({ id: 'p1' }))
    await handleAnnounce(deps, { kind: 'kos', kos_id: KOS })
    expect(log.filter((l) => l.startsWith('discord'))).toEqual(['discord POST /channels/k1/messages', 'discord PATCH /channels/k1/messages/p1'])
  })

  it('edits the post of a changed or cleared mark, and never posts a cleared one', async () => {
    const edit = fake({ discord_kos_view: () => mark({ discord_message_id: 'p1', cleared_at: '2026-11-13T00:00:00Z' }) })
    await handleAnnounce(edit.deps, { kind: 'kos', kos_id: KOS })
    expect(posted(edit.log)).toEqual(['discord PATCH /channels/k1/messages/p1'])
    const never = fake({ discord_kos_view: () => mark({ cleared_at: '2026-11-13T00:00:00Z' }) })
    await handleAnnounce(never.deps, { kind: 'kos', kos_id: KOS })
    expect(posted(never.log)).toEqual([])
  })

  it('posts again when the post was deleted in Discord', async () => {
    const { deps, log } = fake(
      { discord_kos_view: () => mark({ discord_message_id: 'p1' }), discord_claim_kos_post: () => true },
      (method) => (method === 'PATCH' ? new DiscordError(404, '') : { id: 'p2' }),
    )
    await handleAnnounce(deps, { kind: 'kos', kos_id: KOS })
    expect(posted(log)).toEqual([
      'discord PATCH /channels/k1/messages/p1',
      `db discord_set_kos_message {"p_kos":"${KOS}","p_message":null}`,
      `db discord_claim_kos_post {"p_kos":"${KOS}"}`,
      'discord POST /channels/k1/messages',
      `db discord_set_kos_message {"p_kos":"${KOS}","p_message":"p2"}`,
    ])
  })

  it('frees the claim when Discord refuses the post', async () => {
    const { deps, log } = fake({ discord_kos_view: () => mark(), discord_claim_kos_post: () => true }, () => new DiscordError(403, 'Missing Access'))
    await expect(handleAnnounce(deps, { kind: 'kos', kos_id: KOS })).rejects.toThrow('Discord 403')
    expect(log.at(-1)).toBe(`db discord_set_kos_message {"p_kos":"${KOS}","p_message":null}`)
  })

  it('deletes a deleted mark’s post from its channel', async () => {
    const { deps, log } = fake({})
    await handleAnnounce(deps, { kind: 'kos_delete', message_id: 'p1' })
    expect(log).toEqual(['discord DELETE /channels/k1/messages/p1'])
    expect(parseAnnounceBody({ kind: 'kos', kos_id: KOS })).toEqual({ kind: 'kos', kos_id: KOS })
    expect(parseAnnounceBody({ kind: 'kos' })).toBeNull()
  })
})

describe('announceRequest', () => {
  const req = (body: unknown, secret = 's3cret') =>
    new Request('https://x/functions/v1/discord-announce', { method: 'POST', headers: { 'x-hook-secret': secret }, body: JSON.stringify(body) })

  it('only our database may call it', async () => {
    const { deps } = fake({ discord_hook_ok: (a) => a.p_secret === 's3cret' })
    expect((await announceRequest(deps, req({ kind: 'reminders' }, 'guess'))).response.status).toBe(401)
    expect((await announceRequest(deps, req({ kind: 'reminders' }, ''))).response.status).toBe(401)
  })

  it('answers at once and does the work after', async () => {
    const { deps, log } = fake({ discord_hook_ok: () => true, discord_claim_reminders: () => [] })
    const { response, work } = await announceRequest(deps, req({ kind: 'reminders' }))
    expect(response.status).toBe(202)
    await work
    expect(log.at(-1)).toBe('db discord_claim_reminders {}')
  })

  it('refuses a body it does not know', async () => {
    const { deps } = fake({ discord_hook_ok: () => true })
    expect((await announceRequest(deps, req({ kind: 'nuke' }))).response.status).toBe(400)
    expect(parseAnnounceBody({ kind: 'event' })).toBeNull()
    expect(parseAnnounceBody({ kind: 'counts', event_id: ID })).toEqual({ kind: 'counts', event_id: ID })
  })
})
