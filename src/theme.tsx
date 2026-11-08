import { useState } from 'react'

// Light or dark: dark until someone picks light, then their pick, kept on this device.
const KEY = 'guild-roster-theme'
type Theme = 'light' | 'dark'

function initial(): Theme {
  return localStorage.getItem(KEY) === 'light' ? 'light' : 'dark'
}

/** Set before the first render so the page never flashes the wrong colours. */
export function applyTheme(t: Theme = initial()) {
  document.documentElement.dataset.theme = t
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', t === 'dark' ? '#1d1524' : '#fff6ea')
}

export function ThemeButton() {
  const [theme, setTheme] = useState<Theme>(initial)
  const next: Theme = theme === 'dark' ? 'light' : 'dark'
  const label = next === 'dark' ? 'Dark mode' : 'Light mode'
  return (
    <button className="icon-button" title={label} aria-label={label} onClick={() => {
      localStorage.setItem(KEY, next)
      applyTheme(next)
      setTheme(next)
    }}>
      {next === 'dark' ? (
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z" />
        </svg>
      ) : (
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
          <circle cx="12" cy="12" r="4.5" />
          <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
        </svg>
      )}
    </button>
  )
}
