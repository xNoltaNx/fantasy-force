import { StrictMode, useEffect, useState } from 'react'
import { useWowheadRefresh } from './wowhead'
import { createRoot } from 'react-dom/client'
import { AppProvider, useApp, useRoute } from './app'
import { Avatar } from './bits'
import { Availability } from './pages/Availability'
import { Balance } from './pages/Balance'
import { Events } from './pages/Events'
import { MyCharacters } from './pages/MyCharacters'
import { Officers } from './pages/Officers'
import { Professions } from './pages/Professions'
import { Bank } from './pages/Bank'
import { Links } from './pages/Links'
import { Raids } from './pages/Raids'
import { Roster } from './pages/Roster'
import { demo, store } from './store'
import '@fontsource/fredoka/500.css'
import '@fontsource/fredoka/600.css'
import '@fontsource/nunito/400.css'
import '@fontsource/nunito/600.css'
import '@fontsource/nunito/700.css'
import '@fontsource/nunito/800.css'
import './styles.css'
import { applyTheme, ThemeButton } from './theme'

applyTheme()

// The guild's logo, in public/. Swap the file to change it.
const LOGO = `${import.meta.env.BASE_URL}logo-480.webp`

const PAGES: { id: string; name: string; signedIn?: boolean; member?: boolean; officer?: boolean }[] = [
  { id: 'roster', name: 'Roster' },
  { id: 'events', name: 'Events' },
  { id: 'raids', name: 'Raids', member: true },
  { id: 'availability', name: 'Availability' },
  { id: 'professions', name: 'Professions' },
  { id: 'bank', name: 'Guild bank', member: true },
  { id: 'balance', name: 'Class balance' },
  { id: 'links', name: 'Links' },
  { id: 'me', name: 'My characters', signedIn: true },
  { id: 'officers', name: 'Officers', officer: true },
]

function Shell() {
  const { data, viewer, act } = useApp()
  const [page = 'roster', arg] = useRoute()
  const pending = data.members.filter((m) => m.rank_id === null).length
  const [clicks, setClicks] = useState(0)
  useWowheadRefresh(`${page}/${arg}/${clicks}/${JSON.stringify(data).length}`)
  useEffect(() => { document.title = data.guild.name }, [data.guild.name])

  return (
    <>
      {demo && <DemoBar />}
      <div className="rainbow" />
      <header className="top">
        <div className="brand">
          <img className="logo" src={LOGO} alt={`${data.guild.name} logo`} width={200} height={200} />
          <h1>{data.guild.name}</h1>
          <p className="tagline">{data.guild.about}</p>
        </div>
        <div className="who">
          <ThemeButton />
          {viewer?.member ? (
            <>
              <Avatar m={viewer.member} size={28} />
              <span>{viewer.member.display_name}</span>
              <button className="button ghost small" onClick={() => act(() => store.signOut())}>Sign out</button>
            </>
          ) : (
            <button className="button discord" onClick={() => act(() => store.signIn())}>Sign in with Discord</button>
          )}
        </div>
      </header>
      <nav className="tabs">
        {PAGES.filter((p) => (!p.signedIn || viewer) && (!p.member || viewer?.isApproved) && (!p.officer || viewer?.isOfficer)).map((p) => (
          <a key={p.id} href={`#/${p.id}`} className={page === p.id ? 'on' : ''}>
            {p.name}{p.id === 'officers' && pending > 0 ? <span className="count">{pending}</span> : null}
          </a>
        ))}
      </nav>
      {/* any click or typing may reveal new item links (an opened list, a search); have Wowhead look again */}
      <main onClick={() => setClicks((n) => n + 1)} onInput={() => setClicks((n) => n + 1)}>
        {page === 'roster' && <Roster />}
        {page === 'events' && <Events pick={arg} />}
        {page === 'availability' && <Availability />}
        {page === 'balance' && <Balance />}
        {page === 'professions' && <Professions pick={arg} />}
        {page === 'raids' && <Raids />}
        {page === 'bank' && <Bank />}
        {page === 'links' && <Links />}
        {page === 'me' && <MyCharacters key={arg ?? 'me'} memberId={arg} />}
        {page === 'officers' && <Officers />}
      </main>
    </>
  )
}

function DemoBar() {
  const { viewer } = useApp() // re-renders with the data, so approvals and resets show in the picker
  const list = demo!.allMembers()
  return (
    <div className="demo-bar">
      <b>Demo</b> <span className="muted">Example guild, saved only in this browser.</span>
      <label>Viewing as{' '}
        <select value={viewer?.id ?? ''} onChange={(e) => demo!.viewAs(e.target.value || null)}>
          <option value="">A visitor (not signed in)</option>
          {list.members.map((m) => (
            <option key={m.id} value={m.id}>{m.display_name} ({list.ranks.find((r) => r.id === m.rank_id)?.name ?? 'waiting for approval'})</option>
          ))}
        </select>
      </label>
      <button className="button ghost small" onClick={() => confirm('Put the example guild back as it started?') && demo!.reset()}>Reset demo</button>
    </div>
  )
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <AppProvider>
      {(state, error) => (
        <>
          {error && <div className="error">Something went wrong: {error}</div>}
          {state ? <Shell /> : !error && <p className="loading">Loading…</p>}
        </>
      )}
    </AppProvider>
  </StrictMode>,
)
