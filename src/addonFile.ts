// Reads the Fantasy Force addon's saved file (WTF\Account\<ACCOUNT>\SavedVariables\FantasyForce.lua).
// It's a Lua table, read here as data only: a small parser that understands tables, strings, numbers,
// booleans and nil, and refuses anything else, so no file can run code on the site.
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
    while (i < src.length && src[i] !== q) {
      let ch = src[i++]!
      if (ch === '\\') {
        const e = src[i++]!
        if (/[0-9]/.test(e)) {
          let digits = e
          while (digits.length < 3 && /[0-9]/.test(src[i]!)) digits += src[i++]
          ch = String.fromCharCode(Number(digits))
        } else ch = ({ n: '\n', t: '\t', r: '\r', a: '\x07', b: '\b', f: '\f', v: '\v' } as Record<string, string>)[e] ?? e
      }
      out += ch
    }
    if (src[i] !== q) fail('a string never ends')
    i++
    // Lua strings are bytes; WoW writes UTF-8. Decode them so names like Vel'ári read right.
    try { return new TextDecoder().decode(Uint8Array.from(out, (c) => c.charCodeAt(0) & 0xff)) } catch { return out }
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
  spec: string
  role: Role
  professions: { name: string; skill: number; max: number }[]
  inGuild: boolean
  guild: string
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
  return specs.find((s) => s.name.toLowerCase() === spec.toLowerCase())?.name ?? specs[0]?.name ?? ''
}

const num = (v: Lua | undefined): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null)
const text = (v: Lua | undefined): string => (typeof v === 'string' ? v : '')
const list = (v: Lua | undefined): Lua[] => (Array.isArray(v) ? v : v && typeof v === 'object' ? Object.values(v) : [])
const rec = (v: Lua | undefined): Record<string, Lua> => (v && typeof v === 'object' && !Array.isArray(v) ? v : {})

export function readAddonFile(src: string): AddonFile {
  const m = /FantasyForceDB\s*=/.exec(src)
  if (!m) throw new Error("This isn't the Fantasy Force addon's file. Look for FantasyForce.lua in WTF\\Account\\<your account>\\SavedVariables.")
  const db = rec(parseLuaTable(src.slice(m.index + m[0].length)))
  const characters = list(db.characters).map((raw) => {
    const c = rec(raw)
    const cls = classId(text(c.class))
    const spec = specFor(cls, text(c.spec))
    const guild = text(c.guild)
    return {
      name: text(c.name),
      level: num(c.level),
      class_id: cls,
      race: c.race ? raceId(text(c.race)) : '',
      spec,
      role: roleFor(cls, spec),
      professions: list(c.professions).map((p) => rec(p)).filter((p) => text(p.name))
        .map((p) => ({ name: text(p.name), skill: num(p.skill) ?? 0, max: num(p.max) ?? 0 })),
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

  return { characters, guild }
}
