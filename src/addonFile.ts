// Reads the Fantasy Force addon's saved file (WTF\Account\<ACCOUNT>\SavedVariables\FantasyForce.lua).
// It's a Lua table, read here as data only: a small parser that understands tables, strings, numbers,
// booleans and nil, and refuses anything else, so no file can run code on the site.
import type { GuildBank, Raid, Recipe } from './types'
import { CLASSES, roleFor, type Role } from './wow'

type Lua = string | number | boolean | null | Lua[] | { [k: string]: Lua }

export function parseLuaTable(src: string): Lua {
  let i = 0
  const fail = (what: string): never => { throw new Error(`Couldn't read the file near character ${i}: ${what}`) }

  const skip = () => {
    for (;;) {
      while (i < src.length && /\s/.test(src[i]!)) i++
      if (src.startsWith('--[[', i)) { const e = src.indexOf(']]', i); i = e < 0 ? src.length : e + 2; continue }
      if (src.startsWith('--', i)) { const e = src.indexOf('\n', i); i = e < 0 ? src.length : e + 1; continue }
      return
    }
  }

  const str = (): string => {
    const q = src[i++]
    let out = ''
    // The file arrives already decoded as UTF-8, so its letters (Vel'ári) are kept as they are. Only \ddd escapes
    // are raw bytes: a run of them is decoded as UTF-8 together (\195\161 is á), else read one byte per letter.
    let bytes: number[] = []
    const flush = () => {
      if (!bytes.length) return
      try { out += new TextDecoder('utf-8', { fatal: true }).decode(Uint8Array.from(bytes)) } catch { out += String.fromCharCode(...bytes) }
      bytes = []
    }
    while (i < src.length && src[i] !== q) {
      let ch = src[i++]!
      if (ch === '\\') {
        const e = src[i++]!
        if (/[0-9]/.test(e)) {
          let digits = e
          while (digits.length < 3 && /[0-9]/.test(src[i]!)) digits += src[i++]
          bytes.push(Number(digits) & 0xff)
          continue
        }
        ch = ({ n: '\n', t: '\t', r: '\r', a: '\x07', b: '\b', f: '\f', v: '\v' } as Record<string, string>)[e] ?? e
      }
      flush()
      out += ch
    }
    flush()
    if (src[i] !== q) fail('a string never ends')
    i++
    return out
  }

  const value = (): Lua => {
    skip()
    const c = src[i]
    if (c === '{') return table()
    if (c === '"' || c === "'") return str()
    const m = /^-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+)/.exec(src.slice(i))
    if (m) { i += m[0].length; return Number(m[0]) }
    for (const [word, v] of [['true', true], ['false', false], ['nil', null]] as const) {
      if (src.startsWith(word, i) && !/\w/.test(src[i + word.length] ?? '')) { i += word.length; return v }
    }
    return fail('expected a value')
  }

  const table = (): Lua => {
    i++ // {
    const obj: Record<string, Lua> = {}
    let n = 0
    for (;;) {
      skip()
      if (src[i] === '}') { i++; break }
      let key: string
      if (src[i] === '[') {
        i++
        const k = value()
        skip()
        if (src[i++] !== ']') fail('expected ]')
        key = String(k)
        skip()
        if (src[i++] !== '=') fail('expected =')
      } else {
        const m = /^[A-Za-z_]\w*\s*=(?!=)/.exec(src.slice(i))
        if (m) { key = m[0].replace(/\s*=$/, ''); i += m[0].length } else key = String(++n)
      }
      obj[key] = value()
      skip()
      if (src[i] === ',' || src[i] === ';') i++
      else if (src[i] !== '}') fail('expected , or }')
    }
    const keys = Object.keys(obj)
    if (keys.every((k, j) => k === String(j + 1))) return keys.map((k) => obj[k]!)
    return obj
  }

  skip()
  const v = value()
  skip()
  if (i < src.length) fail('extra text after the table')
  return v
}

export interface ImportedCharacter {
  name: string
  level: number | null
  class_id: string
  race: string
  spec: string // '' when the game gave none the site knows (no talents yet): the site keeps what it had
  role: Role
  rolePicked?: boolean // the player picked roles in game: their pick beats the spec's usual role
  professions: { name: string; skill: number; max: number; recipes?: Recipe[] }[]
  inGuild: boolean
  guild: string
  /** Chosen in game with /ff main, for the guild it's in. */
  main?: boolean
}

export interface ImportedGuildMember {
  name: string
  rank: string
  rank_index: number
  level: number | null
  class_id: string
  note: string
  online: boolean
  last_online_days: number | null
}

export interface AddonFile {
  characters: ImportedCharacter[]
  guild: { name: string; updated: number; by: string; members: ImportedGuildMember[] } | null
  bank: GuildBank | null
  raids: Raid[]
}

const iso = (secs: number | null): string => new Date((secs ?? 0) * 1000).toISOString()
const names = (v: Lua | undefined): string[] => list(v).map((x) => text(x)).filter(Boolean)

function readBank(b: Record<string, Lua>): GuildBank | null {
  if (!Array.isArray(b.tabs) && !(b.tabs && typeof b.tabs === 'object')) return null
  return {
    source: text(b.source) === 'guild' ? 'guild' : 'alt',
    updated_at: iso(num(b.updated)),
    recorded_by: text(b.by),
    money: num(b.money),
    tabs: list(b.tabs).map((t) => rec(t)).map((t) => ({
      name: text(t.name),
      items: list(t.items).map((i) => rec(i)).filter((i) => text(i.name))
        .map((i) => ({ id: num(i.id) ?? 0, name: text(i.name), count: num(i.count) ?? 1, quality: num(i.quality) ?? 1 })),
    })),
  }
}

function readRaid(r: Record<string, Lua>): Raid {
  return {
    key: text(r.key) || `${text(r.zone)} ${iso(num(r.started)).slice(0, 10)}`,
    zone: text(r.zone),
    started_at: iso(num(r.started)),
    ended_at: iso(num(r.ended) ?? num(r.started)),
    recorded_by: text(r.by),
    attendees: names(r.attendees),
    bosses: list(r.bosses).map((x) => rec(x)).map((x) => ({ name: text(x.name), killed_at: iso(num(x.killed)), attendees: names(x.attendees) })),
    loot: list(r.loot).map((x) => rec(x)).filter((x) => text(x.name)).map((x) => ({
      item_id: num(x.id) ?? 0, name: text(x.name), quality: num(x.quality) ?? 4, to: text(x.to), at: iso(num(x.at)), boss: text(x.boss),
    })),
  }
}

const RACE_FILES: Record<string, string> = { scourge: 'undead', undead: 'undead', nightelf: 'nightelf' }

function raceId(file: string): string {
  const k = file.toLowerCase().replace(/[^a-z]/g, '')
  return RACE_FILES[k] ?? k
}

function classId(file: string): string {
  const k = String(file ?? '').toLowerCase().replace(/[^a-z]/g, '')
  return CLASSES.some((c) => c.id === k) ? k : ''
}

/** The site's spec name for what the game reports: Druids' Feral tree is split into bear and cat here. */
function specFor(cls: string, spec: string): string {
  const specs = CLASSES.find((c) => c.id === cls)?.specs ?? []
  if (/^feral/i.test(spec) && cls === 'druid') return 'Feral (cat)'
  if (/^combat|^outlaw/i.test(spec) && cls === 'rogue') return 'Combat'
  // No talents yet, the addon writes the class name ("Priest"): no spec, rather than the class's first one.
  return specs.find((s) => s.name.toLowerCase() === spec.toLowerCase())?.name ?? ''
}

/** The site's one role: the spec's usual role when the player's in-game pick includes it, else the first pick. */
function roleOf(cls: string, spec: string, c: Record<string, Lua>): { role: Role; rolePicked: boolean } {
  const usual = roleFor(cls, spec)
  const picks = c.rolesSet === true ? list(c.roles).filter((r): r is Role => r === 'tank' || r === 'healer' || r === 'dps') : []
  if (!picks.length) return { role: usual, rolePicked: false }
  return { role: spec && picks.includes(usual) ? usual : picks[0]!, rolePicked: true }
}

const num = (v: Lua | undefined): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null)
const text = (v: Lua | undefined): string => (typeof v === 'string' ? v : '')
const list = (v: Lua | undefined): Lua[] => (Array.isArray(v) ? v : v && typeof v === 'object' ? Object.values(v) : [])
const rec = (v: Lua | undefined): Record<string, Lua> => (v && typeof v === 'object' && !Array.isArray(v) ? v : {})

/** Recipes come per profession name; each joins its profession, or adds it when the skill list didn't name it. */
function withRecipes(profs: ImportedCharacter['professions'], recipes: Record<string, Lua>): ImportedCharacter['professions'] {
  const out = profs.map((p) => ({ ...p }))
  for (const [name, raw] of Object.entries(recipes)) {
    const byName = new Map<string, Recipe>()
    for (const r of list(raw)) {
      const x = typeof r === 'string' ? { name: r } : rec(r)
      const n = typeof r === 'string' ? r : text((x as Record<string, Lua>).name)
      if (!n || byName.has(n)) continue
      const spell = typeof r === 'string' ? null : num((x as Record<string, Lua>).id)
      const item = typeof r === 'string' ? null : num((x as Record<string, Lua>).item)
      byName.set(n, { name: n, ...(spell ? { spell } : {}), ...(item ? { item } : {}) })
    }
    const found = [...byName.values()].sort((a, b) => a.name.localeCompare(b.name))
    if (!found.length) continue
    const p = out.find((x) => x.name.toLowerCase() === name.toLowerCase())
    if (p) p.recipes = found
    else out.push({ name, skill: 0, max: 0, recipes: found })
  }
  return out
}

export function readAddonFile(src: string): AddonFile {
  // The addon's own code is also called FantasyForce.lua (in Interface\AddOns): easy to pick by mistake.
  if (/\bCreateFrame\b|^\s*local\s+function\b/m.test(src)) {
    throw new Error("That's the addon's code (Interface\\AddOns\\FantasyForce), not its saved file. Choose FantasyForce.lua in WTF\\Account\\<your account>\\SavedVariables instead.")
  }
  const m = /^\s*FantasyForceDB\s*=/m.exec(src)
  if (!m) throw new Error("This isn't the Fantasy Force addon's file. Look for FantasyForce.lua in WTF\\Account\\<your account>\\SavedVariables.")
  const db = rec(parseLuaTable(src.slice(m.index + m[0].length)))
  const mains = rec(db.mains) // /ff main: { [guild] = character name }
  const characters = list(db.characters).map((raw) => {
    const c = rec(raw)
    const cls = classId(text(c.class))
    const spec = specFor(cls, text(c.spec))
    const guild = text(c.guild)
    const main = !!guild && text(mains[guild]).toLowerCase() === text(c.name).toLowerCase()
    return {
      main,
      name: text(c.name),
      level: num(c.level),
      class_id: cls,
      race: c.race ? raceId(text(c.race)) : '',
      spec,
      ...roleOf(cls, spec, c),
      professions: withRecipes(
        list(c.professions).map((p) => rec(p)).filter((p) => text(p.name))
          .map((p) => ({ name: text(p.name), skill: num(p.skill) ?? 0, max: num(p.max) ?? 0 })),
        rec(c.recipes),
      ),
      inGuild: !!guild,
      guild,
    }
  }).filter((c) => c.name && c.class_id)

  const g = rec(db.guild)
  const guild = text(g.name) ? {
    name: text(g.name),
    updated: num(g.updated) ?? 0,
    by: text(g.by),
    members: list(g.members).map((raw) => {
      const x = rec(raw)
      return {
        name: text(x.name),
        rank: text(x.rank),
        rank_index: num(x.rankIndex) ?? 99,
        level: num(x.level),
        class_id: classId(text(x.class)),
        note: text(x.note),
        online: x.online === true,
        last_online_days: num(x.lastOnline),
      }
    }).filter((x) => x.name),
  } : null

  const bank = db.bank ? readBank(rec(db.bank)) : null
  const raids = list(db.raids).map((r) => readRaid(rec(r))).filter((r) => r.zone)
  return { characters, guild, bank, raids }
}
