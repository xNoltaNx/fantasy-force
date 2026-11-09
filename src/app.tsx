import { createContext, useCallback, useContext, useEffect, useState } from 'react'
import type { GuildData, Viewer } from './types'
import { store } from './store'
import { myTimeZone, zoneToAdopt } from './week'

interface AppState {
  data: GuildData
  viewer: Viewer | null
  /** Run a change, then reload everything; shows the error if it fails. */
  act: (fn: () => Promise<unknown>) => Promise<boolean>
}

const Ctx = createContext<AppState | null>(null)

export function useApp(): AppState {
  const v = useContext(Ctx)
  if (!v) throw new Error('useApp outside AppProvider')
  return v
}

export function AppProvider({ children }: { children: (s: AppState | null, error: string | null) => React.ReactNode }) {
  const [state, setState] = useState<{ data: GuildData; viewer: Viewer | null } | null>(null)
  const [error, setError] = useState<string | null>(null)

  const reload = useCallback(async () => {
    try {
      const [viewer, data] = await Promise.all([store.viewer(), store.load()])
      const m = viewer?.member
      const flag = m ? `guild-roster-zone-adopted-2-${m.id}` : ''
      const zone = m ? zoneToAdopt(m.timezone, myTimeZone(), localStorage.getItem(flag) === '1') : null
      if (m && zone) {
        localStorage.setItem(flag, '1')
        await store.updateMember(m.id, { timezone: zone })
        return void (await reload())
      }
      if (flag) localStorage.setItem(flag, '1')
      setState({ data, viewer })
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    void reload()
    return store.onAuthChange(() => void reload())
  }, [reload])

  const act = useCallback(async (fn: () => Promise<unknown>) => {
    try {
      await fn()
      await reload()
      return true
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      return false
    }
  }, [reload])

  const value = state ? { ...state, act } : null
  return <Ctx.Provider value={value}>{children(value, error)}</Ctx.Provider>
}

/** The current hash route, e.g. '#/events' gives ['events']. */
export function useRoute(): string[] {
  const read = () => window.location.hash.replace(/^#\/?/, '').split('/').filter(Boolean)
  const [route, setRoute] = useState(read)
  useEffect(() => {
    const on = () => setRoute(read())
    window.addEventListener('hashchange', on)
    return () => window.removeEventListener('hashchange', on)
  }, [])
  return route
}
