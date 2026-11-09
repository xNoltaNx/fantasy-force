// The two things the bot talks to, over plain fetch: the guild's database (its discord_* SQL functions,
// through PostgREST with the service key) and Discord's REST API (as the bot). Both are handed in, so the
// tests use fakes.

export type Fetch = (input: string, init?: RequestInit) => Promise<Response>

export interface Db {
  rpc<T>(name: string, args: Record<string, unknown>): Promise<T>
}

export interface Discord {
  /** Throws a DiscordError on anything but 2xx (after one wait-and-retry on a 429). */
  request<T>(method: 'GET' | 'POST' | 'PATCH' | 'DELETE', path: string, body?: unknown): Promise<T>
}

export class DiscordError extends Error {
  constructor(readonly status: number, readonly body: string) {
    super(`Discord ${status}: ${body.slice(0, 300)}`)
  }
}

/** The project's service key from the Edge Function's environment: the legacy service_role JWT, else the new secret key. */
export function serviceKey(env: (name: string) => string | undefined): string {
  const legacy = env('SUPABASE_SERVICE_ROLE_KEY')
  if (legacy) return legacy
  const keys = env('SUPABASE_SECRET_KEYS') // JSON {name: key} on projects using the new API keys
  if (keys) {
    try {
      const parsed = JSON.parse(keys) as Record<string, string>
      const key = parsed.default ?? Object.values(parsed)[0]
      if (key) return key
    } catch { /* not JSON */ }
  }
  const own = env('GUILD_SERVICE_KEY') // a secret the Director can set by hand if neither is there
  if (own) return own
  throw new Error('No service key in the function environment (SUPABASE_SERVICE_ROLE_KEY)')
}

export function supabaseDb(fetchFn: Fetch, url: string, key: string): Db {
  const headers: Record<string, string> = { apikey: key, 'Content-Type': 'application/json' }
  if (key.startsWith('eyJ')) headers.Authorization = `Bearer ${key}` // a JWT; the new sb_secret_ keys go in apikey only
  return {
    async rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
      const res = await fetchFn(`${url.replace(/\/$/, '')}/rest/v1/rpc/${name}`, { method: 'POST', headers, body: JSON.stringify(args) })
      const text = await res.text()
      if (!res.ok) throw new Error(`Database ${name} ${res.status}: ${text.slice(0, 300)}`)
      return (text ? JSON.parse(text) : null) as T
    },
  }
}

const API = 'https://discord.com/api/v10'

export function discordApi(fetchFn: Fetch, botToken: string, sleep: (ms: number) => Promise<void>): Discord {
  return {
    async request<T>(method: string, path: string, body?: unknown): Promise<T> {
      for (let attempt = 0; ; attempt++) {
        const res = await fetchFn(`${API}${path}`, {
          method,
          headers: {
            Authorization: `Bot ${botToken}`,
            'User-Agent': 'DiscordBot (https://github.com/xNoltaNx/fantasy-force, 1.0)',
            ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
          },
          ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        })
        const text = await res.text()
        if (res.status === 429 && attempt === 0) {
          let after = Number(res.headers.get('retry-after') ?? 1)
          try { after = Number((JSON.parse(text) as { retry_after?: number }).retry_after ?? after) } catch { /* not JSON */ }
          await sleep(Math.min(10, Math.max(0.1, after || 1)) * 1000)
          continue
        }
        if (!res.ok) throw new DiscordError(res.status, text)
        return (text ? JSON.parse(text) : null) as T
      }
    },
  }
}
