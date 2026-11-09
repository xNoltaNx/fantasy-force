// Both functions' wiring from the Edge Function's environment (Supabase dashboard: Edge Functions > Secrets).
// SUPABASE_URL and the service key are there on their own; the DISCORD_* ones the Director adds.

import type { AnnounceDeps } from './announce.ts'
import type { InteractionDeps } from './interactions.ts'
import { discordApi, serviceKey, supabaseDb, type Fetch } from './rest.ts'

type Env = (name: string) => string | undefined

export const DEFAULT_SITE_URL = 'https://xnoltanx.github.io/fantasy-force/'

function need(env: Env, name: string): string {
  const v = env(name)?.trim()
  if (!v) throw new Error(`Missing the ${name} secret (Supabase: Edge Functions > Secrets)`)
  return v
}

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms))
const log = (...a: unknown[]) => console.error(...a)

function db(env: Env, fetchFn: Fetch) {
  return supabaseDb(fetchFn, need(env, 'SUPABASE_URL'), serviceKey(env))
}

export function announceDeps(env: Env, fetchFn: Fetch): AnnounceDeps {
  return {
    db: db(env, fetchFn),
    discord: discordApi(fetchFn, need(env, 'DISCORD_BOT_TOKEN'), sleep),
    channelId: need(env, 'DISCORD_CHANNEL_ID'),
    siteUrl: env('SITE_URL')?.trim() || DEFAULT_SITE_URL,
    now: () => Date.now(),
    sleep,
    log,
  }
}

export function interactionDeps(env: Env, fetchFn: Fetch): InteractionDeps {
  return {
    publicKey: need(env, 'DISCORD_PUBLIC_KEY'),
    applicationId: env('DISCORD_APPLICATION_ID')?.trim() || undefined,
    db: db(env, fetchFn),
    siteUrl: env('SITE_URL')?.trim() || DEFAULT_SITE_URL,
    log,
  }
}
