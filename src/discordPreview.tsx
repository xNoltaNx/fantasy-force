// The bot's message as Discord shows it, drawn from the very payload the bot sends (the builders in
// supabase/functions/_shared/message.ts), so what the site previews is what lands in the channel.
// Only what the bot uses is drawn: one embed's parts, link and role buttons, and the bits of Discord's
// markdown it writes (bold, italics, strikethrough, code, >>> quotes, timestamps and role mentions).
import type { ReactNode } from 'react'

interface Embed {
  author?: { name: string; icon_url?: string; url?: string }
  title?: string
  url?: string
  color?: number
  description?: string
  thumbnail?: { url: string }
  fields?: { name: string; value: string; inline?: boolean }[]
  footer?: { text: string; icon_url?: string }
  timestamp?: string
}
interface Button { style: number; label?: string; emoji?: { name: string }; url?: string; disabled?: boolean }
export interface DiscordPayload {
  content?: string
  embeds?: Embed[]
  components?: { components: Button[] }[]
}

/** The site's own address: the preview's pictures come from here (public/discord), as the bot's do. */
export const previewSite = () => new URL(import.meta.env.BASE_URL, window.location.href).href

const hex = (n?: number) => (n == null ? '#1e1f22' : `#${n.toString(16).padStart(6, '0')}`)

function stamp(unix: number, style: string): string {
  const d = new Date(unix * 1000)
  if (style === 'R') {
    const secs = (d.getTime() - Date.now()) / 1000
    const units: [Intl.RelativeTimeFormatUnit, number][] = [['year', 31536000], ['month', 2592000], ['day', 86400], ['hour', 3600], ['minute', 60]]
    const rtf = new Intl.RelativeTimeFormat([], { numeric: 'auto' })
    for (const [unit, size] of units) if (Math.abs(secs) >= size) return rtf.format(Math.round(secs / size), unit)
    return rtf.format(Math.round(secs), 'second')
  }
  if (style === 'F') return d.toLocaleString([], { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' })
  return d.toLocaleString([], { month: 'long', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' })
}

const INLINE = /\\([\\*_~`|>[\]])|\*\*(.+?)\*\*|~~(.+?)~~|\*(.+?)\*|`([^`]+)`|<t:(\d+):([a-zA-Z])>|<@&(\d+)>|<@!?(\d+)>/g

/** One line of Discord markdown, as React. */
function inline(s: string): ReactNode[] {
  const out: ReactNode[] = []
  let last = 0
  let k = 0
  for (const m of s.matchAll(INLINE)) {
    if (m.index! > last) out.push(s.slice(last, m.index))
    const [, esc, bold, strike, em, code, ts, tsStyle, role, user] = m
    if (esc) out.push(esc)
    else if (bold) out.push(<strong key={k++}>{inline(bold)}</strong>)
    else if (strike) out.push(<s key={k++}>{inline(strike)}</s>)
    else if (em) out.push(<em key={k++}>{inline(em)}</em>)
    else if (code) out.push(<code key={k++}>{code}</code>)
    else if (ts) out.push(<span key={k++} className="dc-stamp">{stamp(Number(ts), tsStyle!)}</span>)
    else if (role) out.push(<span key={k++} className="dc-mention">@role</span>)
    else if (user) out.push(<span key={k++} className="dc-mention">@someone</span>)
    last = m.index! + m[0].length
  }
  if (last < s.length) out.push(s.slice(last))
  return out
}

/** Lines, with ">>> " quoting the rest and "> " quoting one line. */
function Markdown({ text }: { text: string }) {
  const at = text.indexOf('>>> ')
  const [plain, quoted] = at >= 0 && (at === 0 || text[at - 1] === '\n') ? [text.slice(0, at), text.slice(at + 4)] : [text, '']
  const lines = plain.replace(/\n$/, '').split('\n')
  return (
    <>
      {plain && lines.map((l, i) => (l.startsWith('> ')
        ? <blockquote key={i} className="dc-quote">{inline(l.slice(2))}</blockquote>
        : <div key={i} className="dc-line">{l ? inline(l) : ' '}</div>))}
      {quoted && <blockquote className="dc-quote">{quoted.split('\n').map((l, i) => <div key={i} className="dc-line">{l ? inline(l) : ' '}</div>)}</blockquote>}
    </>
  )
}

const BUTTON = ['', 'primary', 'secondary', 'success', 'danger', 'secondary'] // 5: a link, grey

/** A message from the bot, in Discord's own dark look whatever the site's theme. */
export function DiscordMessage({ msg, botName, avatar }: { msg: DiscordPayload; botName: string; avatar: string }) {
  const now = new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
  return (
    <div className="dc" aria-label="Preview of the Discord post">
      <img className="dc-avatar" src={avatar} alt="" width={40} height={40} />
      <div className="dc-body">
        <div className="dc-head"><span className="dc-name">{botName}</span><span className="dc-app">APP</span><span className="dc-time">Today at {now}</span></div>
        {msg.content && <div className="dc-content"><Markdown text={msg.content} /></div>}
        {msg.embeds?.map((e, i) => <EmbedView key={i} e={e} />)}
        {msg.components?.map((row, i) => (
          <div key={i} className="dc-buttons">
            {row.components.map((b, j) => (
              <span key={j} className={`dc-button ${BUTTON[b.style] ?? 'secondary'} ${b.disabled ? 'disabled' : ''}`}>
                {b.emoji && <span aria-hidden="true">{b.emoji.name}</span>}
                {b.label}
                {b.url && <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" aria-hidden="true"><path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5" /></svg>}
              </span>
            ))}
          </div>
        ))}
      </div>
    </div>
  )
}

function EmbedView({ e }: { e: Embed }) {
  // Discord puts up to three inline fields side by side; a field that isn't inline takes the whole row.
  const fields = e.fields ?? []
  return (
    <div className="dc-embed" style={{ borderLeftColor: hex(e.color) }}>
      <div className="dc-embed-main">
        {e.author && (
          <div className="dc-author">
            {e.author.icon_url && <img src={e.author.icon_url} alt="" width={24} height={24} />}
            <span>{e.author.name}</span>
          </div>
        )}
        {e.title && <div className="dc-title">{e.url ? <a href={e.url} target="_blank" rel="noreferrer">{e.title}</a> : e.title}</div>}
        {e.description && <div className="dc-desc"><Markdown text={e.description} /></div>}
        {fields.length > 0 && (
          <div className="dc-fields">
            {fields.map((f, i) => (
              <div key={i} className={`dc-field ${f.inline ? '' : 'wide'}`}>
                <div className="dc-field-name">{inline(f.name)}</div>
                <div className="dc-field-value"><Markdown text={f.value} /></div>
              </div>
            ))}
          </div>
        )}
        {(e.footer || e.timestamp) && (
          <div className="dc-footer">
            {e.footer?.icon_url && <img src={e.footer.icon_url} alt="" width={20} height={20} />}
            <span>{[e.footer?.text, e.timestamp && stamp(Date.parse(e.timestamp) / 1000, 'f')].filter(Boolean).join(' • ')}</span>
          </div>
        )}
      </div>
      {e.thumbnail && <img className="dc-thumb" src={e.thumbnail.url} alt="" width={80} height={80} />}
    </div>
  )
}
