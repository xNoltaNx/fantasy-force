import { useEffect } from 'react'

// Game icons and hover tooltips come from Wowhead's tooltip script (loaded in index.html): any link to a
// wowhead.com/forever item or spell page gets its icon, and hovering it shows the in-game tooltip.
// One shared link for items, recipes, bank and loot alike.

const BASE = 'https://www.wowhead.com/forever'

export function wowheadUrl(t: { item?: number; spell?: number; name: string }): string {
  if (t.spell) return `${BASE}/spell=${t.spell}`
  if (t.item) return `${BASE}/item=${t.item}`
  return `${BASE}/search?q=${encodeURIComponent(t.name)}`
}

/** An item or recipe: game icon and Wowhead tooltip when its id is known, a Wowhead search otherwise. */
export function GameLink({ item, spell, name, className }: { item?: number; spell?: number; name: string; className?: string }) {
  const known = !!(item || spell)
  return (
    <a className={`game-link ${known ? '' : 'unknown'} ${className ?? ''}`} href={wowheadUrl({ item, spell, name })} target="_blank" rel="noreferrer"
      {...(known ? { 'data-wowhead': `${spell ? `spell=${spell}` : `item=${item}`}&domain=forever` } : { title: `Look up ${name} on Wowhead` })}>
      {name}
    </a>
  )
}

declare global {
  interface Window { $WowheadPower?: { refreshLinks?: () => void } }
}

/** Wowhead only scans links once; call after new ones render so they get icons too. */
export function useWowheadRefresh(dep: unknown) {
  useEffect(() => {
    const t = setTimeout(() => window.$WowheadPower?.refreshLinks?.(), 50)
    return () => clearTimeout(t)
  }, [dep])
}
