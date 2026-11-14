import { useCallback, useEffect, useState } from 'react'
import { kosCommand, kosMessage, kosWho, threat, THREATS, type KosView } from '../../supabase/functions/_shared/message'
import { readAddonFile, type ImportedKos } from '../addonFile'
import { useApp } from '../app'
import { DiscordMark, memberName } from '../bits'
import { DiscordMessage, previewSite } from '../discordPreview'
import { SAVED_FILE_READABLE } from '../SavedFileSync'
import { allowed, recall } from '../savedFile'
import { store } from '../store'
import { activeKos, type KosInput } from '../store/store'
import type { GuildData, KosMark } from '../types'
import { classById, CLASSES, raceName, racesFor } from '../wow'

// Kill on sight: the guild's list of enemy players to attack on sight. Marking one here broadcasts it to the
// guild's Discord (supabase/functions, the kos kind); the post follows every change, and a clear greys it out.
// The addon keeps its own list in game: each post and card gives the /ff kos line that adds the mark there.

const SKULL = `${import.meta.env.BASE_URL}discord/kos.png`
const AVATAR = `${import.meta.env.BASE_URL}discord/logo.jpg`

// Where they were seen: the open world's zones and towns, offered as the place is typed (anything else is fine).
const ZONES = [
  'Alterac Mountains', 'Arathi Highlands', 'Ashenvale', 'Azshara', 'Badlands', 'Blackrock Mountain', 'Blasted Lands',
  'Burning Steppes', 'Darkshore', 'Desolace', 'Dun Morogh', 'Duskwood', 'Dustwallow Marsh', 'Eastern Plaguelands',
  'Elwynn Forest', 'Felwood', 'Feralas', 'Hillsbrad Foothills', 'Loch Modan', 'Moonglade', 'Mulgore', 'Orgrimmar',
  'Redridge Mountains', 'Searing Gorge', 'Silithus', 'Silverpine Forest', 'Stonetalon Mountains', 'Stranglethorn Vale',
  'Swamp of Sorrows', 'Tanaris', 'Teldrassil', 'The Barrens', 'The Barrens, Crossroads', 'The Hinterlands', "Thousand Needles",
  'Thunder Bluff', 'Tirisfal Glades', 'Un\'Goro Crater', 'Undercity', 'Western Plaguelands', 'Westfall', 'Wetlands',
  'Winterspring', 'Booty Bay', 'Gadgetzan', 'Southshore', 'Tarren Mill', 'Ratchet',
]

/** The form's state: what a member types (the level as typed). */
interface Draft {
  id?: string
  name: string
  level: string
  race: string
  class_id: string
  guild: string
  zone: string
  reason: string
  danger: 1 | 2 | 3
}

const blank = (): Draft => ({ name: '', level: '', race: '', class_id: '', guild: '', zone: '', reason: '', danger: 2 })
const fromMark = (k: KosMark, keepId: boolean): Draft => ({
  ...(keepId ? { id: k.id } : {}), name: k.name, level: k.level ? String(k.level) : '', race: k.race, class_id: k.class_id,
  guild: k.guild, zone: k.zone, reason: k.reason, danger: k.danger,
})
const fromAddon = (k: ImportedKos): Draft => ({
  name: k.name, level: k.level ? String(k.level) : '', race: k.race, class_id: k.class_id, guild: k.guild, zone: '', reason: k.reason, danger: 2,
})

function ago(iso: string): string {
  const min = Math.round((Date.now() - Date.parse(iso)) / 60000)
  if (min < 1) return 'just now'
  if (min < 60) return `${min} min ago`
  const h = Math.round(min / 60)
  if (h < 48) return `${h} h ago`
  return `${Math.round(h / 24)} days ago`
}

/** Who marked or cleared a mark: their main, else their name, as the Discord post says it. */
function whoName(data: GuildData, id: string | null): string {
  if (!id) return 'Someone'
  return data.characters.find((c) => c.member_id === id && c.is_main)?.name ?? memberName(data, id)
}

const tidy = (s: string) => s.trim().replace(/\s+/g, ' ')

/** The threat as small skulls (the site's fonts have no skull of their own; Discord shows its emoji). */
function Skulls({ n, size = 14 }: { n: number; size?: number }) {
  return <span className="skull-row" aria-hidden="true">{Array.from({ length: n }, (_, i) => <img key={i} src={SKULL} alt="" width={size} height={size} />)}</span>
}

export function Kos({ pick }: { pick?: string }) {
  const { data, viewer } = useApp()
  const picked = data.kos.find((k) => k.id === pick)
  const [tab, setTab] = useState<'active' | 'cleared'>(picked?.cleared_at ? 'cleared' : 'active')
  const [form, setForm] = useState<{ draft: Draft; n: number } | null>(null)
  const [q, setQ] = useState('')
  useEffect(() => {
    if (pick) document.getElementById(`kos-${pick}`)?.scrollIntoView({ block: 'center' })
  }, [pick])

  if (!viewer?.isApproved) return <p className="muted">The kill-on-sight list is for guild members. Sign in, and once an officer approves you it's here.</p>

  const open = (draft: Draft) => {
    setForm((f) => ({ draft, n: (f?.n ?? 0) + 1 }))
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }
  const active = data.kos.filter((k) => !k.cleared_at).sort((a, b) => b.danger - a.danger || b.created_at.localeCompare(a.created_at))
  const cleared = data.kos.filter((k) => k.cleared_at).sort((a, b) => b.cleared_at!.localeCompare(a.cleared_at!))
  const words = q.toLowerCase().split(/\s+/).filter(Boolean)
  const list = (tab === 'active' ? active : cleared).filter((k) => {
    const hay = [k.name, k.guild, k.zone, k.reason, kosWho(k), whoName(data, k.created_by)].join(' ').toLowerCase()
    return words.every((w) => hay.includes(w))
  })

  return (
    <section className="kos-page">
      <header className="kos-hero">
        <img className="kos-hero-skull" src={SKULL} alt="" width={96} height={96} />
        <div className="kos-hero-text">
          <h2>Kill on sight</h2>
          <p>Enemy players the guild attacks on sight. Mark one and it goes out to the guild's Discord with a skull on it. The post updates when the mark changes, and greys out when it's cleared.</p>
        </div>
        <button className="button kos-button" onClick={() => open(blank())}><Skulls n={1} size={18} /> Mark someone</button>
      </header>

      <FromAddon onPick={(k) => open(fromAddon(k))} />
      {form && <KosForm key={form.n} draft={form.draft} done={() => setForm(null)} switchTo={open} />}

      <div className="filters">
        <div className="segmented">
          <button className={tab === 'active' ? 'on' : ''} onClick={() => setTab('active')}>Wanted ({active.length})</button>
          <button className={tab === 'cleared' ? 'on' : ''} onClick={() => setTab('cleared')}>Cleared ({cleared.length})</button>
        </div>
        <input placeholder="Search names, guilds, places, reasons" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Search the list" />
      </div>
      {list.length === 0 && (
        <p className="muted">{q ? 'Nobody matches that.' : tab === 'active' ? 'Nobody is kill on sight. Peaceful times.' : 'No cleared marks yet.'}</p>
      )}
      <div className="wanted-grid">
        {list.map((k) => (
          <Wanted key={k.id} k={k} picked={k.id === pick} onEdit={() => open(fromMark(k, true))} onAgain={() => open(fromMark(k, false))} />
        ))}
      </div>
    </section>
  )
}

/** Marks in the member's own addon (its remembered saved file) that aren't on the site yet: one click to broadcast. */
function FromAddon({ onPick }: { onPick: (k: ImportedKos) => void }) {
  const { data, viewer } = useApp()
  const memberId = viewer?.member?.id
  const [marks, setMarks] = useState<ImportedKos[]>([])
  const read = useCallback(async () => {
    const r = memberId ? await recall(memberId) : null
    // Not allowed yet: the bar at the top (SavedFileSync) asks, and says when it may be read.
    if (!r || !(await allowed(r.handle, false))) return setMarks([])
    try { setMarks(readAddonFile(await (await r.handle.getFile()).text()).kos) } catch { setMarks([]) }
  }, [memberId])
  useEffect(() => {
    void read()
    const again = () => void read()
    window.addEventListener(SAVED_FILE_READABLE, again)
    return () => window.removeEventListener(SAVED_FILE_READABLE, again)
  }, [read])

  const fresh = marks.filter((m) => !activeKos(data.kos, m.name)).slice(0, 12)
  if (!fresh.length) return null
  return (
    <div className="card kos-addon">
      <h3>Marked in your addon, not broadcast yet</h3>
      <p className="muted small">From your saved file, as the game last wrote it (on logging out or /reload). Pick one to send it to Discord.</p>
      <div className="kos-chips">
        {fresh.map((m) => (
          <button key={m.name} className="kos-chip" onClick={() => onPick(m)} style={{ '--cls': classById(m.class_id)?.color ?? 'var(--muted)' } as React.CSSProperties}>
            <img src={SKULL} alt="" width={18} height={18} />
            <b className="cls-name">{m.name}</b>
            {kosWho(m) && <span className="muted">{kosWho(m)}</span>}
          </button>
        ))}
      </div>
    </div>
  )
}

function KosForm({ draft, done, switchTo }: { draft: Draft; done: () => void; switchTo: (d: Draft) => void }) {
  const { data, viewer, act } = useApp()
  const [f, setF] = useState(draft)
  const set = <K extends keyof Draft>(k: K, v: Draft[K]) => setF((x) => ({ ...x, [k]: v }))
  const enemy = data.guild.faction === 'horde' ? 'alliance' : data.guild.faction === 'alliance' ? 'horde' : ''
  const races = racesFor(enemy)
  const original = data.kos.find((k) => k.id === f.id)

  const name = tidy(f.name)
  const level = f.level.trim() ? Number(f.level) : null
  const levelOk = level === null || (Number.isInteger(level) && level >= 1 && level <= 63)
  const clash = name.length >= 2 ? activeKos(data.kos, name) : undefined
  const blocked = !!clash && clash.id !== f.id
  const ok = name.length >= 2 && levelOk && !blocked

  const input: KosInput = {
    ...(f.id ? { id: f.id } : {}),
    name, level: levelOk ? level : null, race: f.race, class_id: f.class_id,
    guild: tidy(f.guild), zone: tidy(f.zone), reason: f.reason.trim(), danger: f.danger,
  }
  const view: KosView = {
    ...input, id: f.id ?? '00000000-0000-4000-8000-000000000000', name: name || 'Their name',
    created_at: original?.created_at ?? new Date().toISOString(), updated_at: '', cleared_at: null, cleared_by: null,
    marked_by: whoName(data, original?.created_by ?? viewer?.id ?? null), discord_message_id: null, guild_name: data.guild.name,
  }
  const save = async () => {
    if (ok && (await act(() => store.saveKos(input)))) done()
  }

  return (
    <div className="card form kos-form">
      <div className="kos-form-grid">
        <div>
          <h2>{f.id ? `Change the mark on ${original?.name ?? name}` : 'Mark someone kill on sight'}</h2>
          <label>Name
            <input autoFocus value={f.name} maxLength={48} onChange={(e) => set('name', e.target.value)} placeholder="Their character's name" />
          </label>
          {blocked && (
            <p className="error-line row">
              <span>{clash.name} is already kill on sight.</span>
              <button className="button ghost small" onClick={() => switchTo(fromMark(clash, true))}>Change that mark</button>
            </p>
          )}
          <div className="row">
            <label className="kos-level">Level
              <input type="number" min={1} max={63} value={f.level} onChange={(e) => set('level', e.target.value)} placeholder="??" aria-invalid={!levelOk} />
            </label>
            <label>Race
              <select value={f.race} onChange={(e) => set('race', e.target.value)}>
                <option value="">Not sure</option>
                {races.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
                {f.race && !races.some((r) => r.id === f.race) && <option value={f.race}>{raceName(f.race) || f.race}</option>}
              </select>
            </label>
            <label>Class
              <select value={f.class_id} onChange={(e) => set('class_id', e.target.value)}>
                <option value="">Not sure</option>
                {CLASSES.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
            </label>
          </div>
          <div className="row">
            <label>Their guild <input value={f.guild} maxLength={48} onChange={(e) => set('guild', e.target.value)} placeholder="None, or the name" /></label>
            <label>Last seen <input value={f.zone} maxLength={80} list="kos-zones" onChange={(e) => set('zone', e.target.value)} placeholder="The Barrens, Crossroads" /></label>
          </div>
          <div className="kos-threat-label">Threat</div>
          <div className="kos-threat" role="radiogroup" aria-label="Threat">
            {THREATS.map((t) => (
              <button key={t.level} type="button" role="radio" aria-checked={f.danger === t.level}
                className={`threat-pick threat-${t.level} ${f.danger === t.level ? 'on' : ''}`} onClick={() => set('danger', t.level)}>
                <Skulls n={t.level} size={18} />{t.name}
              </button>
            ))}
          </div>
          <label>Why
            <textarea rows={3} maxLength={500} value={f.reason} onChange={(e) => set('reason', e.target.value)} placeholder="Ganks lowbies at the Crossroads flight master" />
          </label>
          <div className="row">
            <button className="button kos-button" disabled={!ok} onClick={save}>{f.id ? 'Save and update the post' : <><Skulls n={1} size={18} /> Broadcast to Discord</>}</button>
            <button className="button ghost" onClick={done}>Cancel</button>
            {store.mode === 'demo' && <span className="muted small">Demo: kept in this browser, nothing goes to Discord.</span>}
          </div>
        </div>
        <div className="kos-preview">
          <div className="kos-preview-label">{f.id ? 'The post, once saved' : 'What lands in Discord'}</div>
          <DiscordMessage msg={kosMessage(view, previewSite(), { post: !f.id })} botName={data.guild.name} avatar={AVATAR} />
        </div>
      </div>
      <datalist id="kos-zones">{ZONES.map((z) => <option key={z} value={z} />)}</datalist>
    </div>
  )
}

function Wanted({ k, picked, onEdit, onAgain }: { k: KosMark; picked: boolean; onEdit: () => void; onAgain: () => void }) {
  const { data, viewer, act } = useApp()
  const [copied, setCopied] = useState(false)
  const t = threat(k.danger)
  const cls = classById(k.class_id)
  const mayDelete = viewer?.isOfficer || (!!k.created_by && k.created_by === viewer?.id)
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(kosCommand(k))
      setCopied(true)
      setTimeout(() => setCopied(false), 1800)
    } catch { /* no clipboard: the title shows the line */ }
  }

  return (
    <article id={`kos-${k.id}`} className={`wanted threat-${k.danger} ${k.cleared_at ? 'cleared' : ''} ${picked ? 'picked' : ''}`}
      style={{ '--cls': cls?.color ?? '#a08a98' } as React.CSSProperties}>
      <div className="wanted-badge"><img src={SKULL} alt="" width={60} height={60} /></div>
      <div className="wanted-body">
        <div className="wanted-top">
          <h3 className="cls-name">{k.name}</h3>
          <span className="wanted-threat" title={`Threat: ${t.name}`}><Skulls n={t.level} /> {t.name}</span>
        </div>
        <div className="wanted-who">
          {kosWho(k) || <span className="muted">Level, race and class unknown</span>}
          {k.guild && <span className="wanted-guild"> &lt;{k.guild}&gt;</span>}
        </div>
        {k.reason && <p className="wanted-reason">{k.reason}</p>}
        <div className="wanted-meta">
          {k.zone && <span>📍 {k.zone}</span>}
          <span>Marked by <b>{whoName(data, k.created_by)}</b> {ago(k.created_at)}</span>
          {k.cleared_at && <span>Cleared by <b>{whoName(data, k.cleared_by)}</b> {ago(k.cleared_at)}</span>}
          {store.mode === 'live' && <DiscordMark posted={!!k.discord_message_id} />}
        </div>
        <div className="wanted-actions">
          {!k.cleared_at && <button className="button ghost small" onClick={onEdit}>Change</button>}
          {!k.cleared_at && (
            <button className="button ghost small" onClick={() => confirm(`Clear ${k.name}? They're no longer kill on sight, and the Discord post greys out.`) && act(() => store.clearKos(k.id))}>Clear</button>
          )}
          {k.cleared_at && !activeKos(data.kos, k.name) && <button className="button ghost small" onClick={onAgain}>Mark again</button>}
          {!k.cleared_at && (
            <button className="button ghost small" onClick={copy} title={`Copy the line that adds this mark to your addon: ${kosCommand(k)}`}>
              {copied ? 'Copied' : 'Copy /ff kos'}
            </button>
          )}
          {mayDelete && (
            <button className="button ghost small" onClick={() => confirm(`Delete the mark on ${k.name}? Its Discord post is deleted too.`) && act(() => store.deleteKos(k.id))}>Delete</button>
          )}
        </div>
      </div>
    </article>
  )
}
