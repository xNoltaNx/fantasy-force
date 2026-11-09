import { describe, expect, it } from 'vitest'
import { discordApi, DiscordError, serviceKey, supabaseDb, type Fetch } from './rest.ts'

describe('serviceKey', () => {
  it('takes the legacy key, else the new default secret key, else a hand-set one', () => {
    expect(serviceKey((n) => ({ SUPABASE_SERVICE_ROLE_KEY: 'eyJold' })[n])).toBe('eyJold')
    expect(serviceKey((n) => ({ SUPABASE_SECRET_KEYS: '{"default":"sb_secret_x"}' })[n])).toBe('sb_secret_x')
    expect(serviceKey((n) => ({ GUILD_SERVICE_KEY: 'mine' })[n])).toBe('mine')
    expect(() => serviceKey(() => undefined)).toThrow()
  })
})

describe('supabaseDb', () => {
  it('calls the SQL function with the key', async () => {
    const seen: { url: string; init?: RequestInit }[] = []
    const f: Fetch = async (url, init) => { seen.push({ url, init }); return new Response('true') }
    expect(await supabaseDb(f, 'https://p.supabase.co/', 'sb_secret_x').rpc('discord_hook_ok', { p_secret: 'a' })).toBe(true)
    expect(seen[0]!.url).toBe('https://p.supabase.co/rest/v1/rpc/discord_hook_ok')
    const h = seen[0]!.init!.headers as Record<string, string>
    expect(h.apikey).toBe('sb_secret_x')
    expect(h.Authorization).toBeUndefined()
    await supabaseDb(f, 'https://p.supabase.co', 'eyJjwt').rpc('x', {})
    expect((seen[1]!.init!.headers as Record<string, string>).Authorization).toBe('Bearer eyJjwt')
  })
})

describe('discordApi', () => {
  it('waits out one rate limit, then retries', async () => {
    const answers = [new Response('{"retry_after":1.5}', { status: 429 }), new Response('{"id":"m1"}')]
    const sleeps: number[] = []
    const api = discordApi(async () => answers.shift()!, 'tok', async (ms) => void sleeps.push(ms))
    expect(await api.request('POST', '/channels/c/messages', {})).toEqual({ id: 'm1' })
    expect(sleeps).toEqual([1500])
  })

  it('throws a DiscordError with the status', async () => {
    const api = discordApi(async () => new Response('{"code":10008}', { status: 404 }), 'tok', async () => {})
    await expect(api.request('PATCH', '/x', {})).rejects.toBeInstanceOf(DiscordError)
  })

  it('sends the bot token', async () => {
    let auth = ''
    const api = discordApi(async (_url, init) => { auth = (init!.headers as Record<string, string>).Authorization!; return new Response(null, { status: 204 }) }, 'tok', async () => {})
    expect(await api.request('DELETE', '/x')).toBeNull()
    expect(auth).toBe('Bot tok')
  })
})
