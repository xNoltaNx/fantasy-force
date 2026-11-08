import { StrictMode, useEffect } from 'react'
import { createRoot } from 'react-dom/client'
import { AppProvider, useApp, useRoute } from './app'
import { Avatar } from './bits'
import { Availability } from './pages/Availability'
import { Balance } from './pages/Balance'
import { Events } from './pages/Events'
import { MyCharacters } from './pages/MyCharacters'
import { Officers } from './pages/Officers'
import { Roster } from './pages/Roster'
import { demo, store } from './store'
import '@fontsource/fredoka/500.css'
import '@fontsource/fredoka/600.css'
import '@fontsource/nunito/400.css'
import '@fontsource/nunito/600.css'
import '@fontsource/nunito/700.css'
import '@fontsource/nunito/800.css'
import './styles.css'

// The guild's logo, in public/. Swap the file to change it.
const LOGO = `${import.meta.env.BASE_URL}logo-480.webp`

const PAGES = [
  { id: 'roster', name: 'Roster' },
  { id: 'events', name: 'Events' },
  { id: 'availability', name: 'Availability' },
  { id: 'balance', name: 'Class balance' },
  { id: 'me', name: 'My characters', signedIn: true },
  { id: 'officers', name: 'Officers', officer: true },
]

function Shell() {
  const { data, viewer, act } = useApp()
  const [page = 'roster', arg] = useRoute()
  const pending = data.members.filter((m) => m.rank_id === null).length
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
        {PAGES.filter((p) => (!p.signedIn || viewer) && (!p.officer || viewer?.isOfficer)).map((p) => (
          <a key={p.id} href={`#/${p.id}`} className={page === p.id ? 'on' : ''}>
            {p.name}{p.id === 'officers' && pending > 0 ? <span className="count">{pending}</span> : null}
          </a>
        ))}
      </nav>
      <main>
        {page === 'roster' && <Roster />}
        {page === 'events' && <Events />}
        {page === 'availability' && <Availability />}
        {page === 'balance' && <Balance />}
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
