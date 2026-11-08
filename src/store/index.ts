import { DemoStore } from './demo'
import { SupabaseStore } from './supabase'
import type { Store } from './store'

// With VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY set (see .env.example) the site is live; without them it's the demo.
const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

export const store: Store = url && key ? new SupabaseStore(url, key) : new DemoStore()
export const demo: DemoStore | null = store instanceof DemoStore ? store : null
export type { Store }
