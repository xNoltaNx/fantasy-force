import type { Character, GuildData, Member, Profession } from './types'
import { classById, MAX_LEVEL, raceName, ROLES, type Role } from './wow'

export function RoleIcon({ role }: { role: Role }) {
  const r = ROLES.find((x) => x.id === role)!
  return <span className={`role role-${role}`} title={r.name} aria-label={r.name}>{r.icon}</span>
}

export function ClassName({ c, children }: { c: Pick<Character, 'class_id'>; children: React.ReactNode }) {
  return <span className="cls-name" style={{ '--cls': classById(c.class_id)?.color } as React.CSSProperties}>{children}</span>
}

export function CharLine({ c, race = false }: { c: Character; race?: boolean }) {
  const cls = classById(c.class_id)
  return (
    <span className="charline">
      <RoleIcon role={c.role} />
      <ClassName c={c}><b>{c.name}</b></ClassName>
      <span className="muted"> {c.spec} {race && c.race ? `${raceName(c.race)} ` : ''}{cls?.name}</span>
      {c.level ? <span className={`ilvl ${c.level >= MAX_LEVEL ? 'max' : ''}`} title={c.level >= MAX_LEVEL ? 'Max level' : 'Level'}>Level {c.level}</span> : null}
    </span>
  )
}

export function Avatar({ m, size = 32 }: { m: Member; size?: number }) {
  if (m.avatar_url) return <img className="avatar" src={m.avatar_url} width={size} height={size} alt="" />
  return <span className="avatar avatar-letter" style={{ width: size, height: size }}>{m.display_name.slice(0, 1).toUpperCase()}</span>
}

/** What hovering a character shows: who plays it, level, race, spec and class, and its professions (one in focus first). */
export function charSummary(data: GuildData, c: Character, focus?: Profession): string {
  const cls = classById(c.class_id)?.name ?? ''
  const profs = [...(focus ? [focus] : []), ...c.professions.filter((p) => p.name !== focus?.name)]
    .map((p) => `${p.name} ${p.skill}${p.recipes?.length ? ` (${p.recipes.length} recipes)` : ''}`)
  return [
    `${c.name}, played by ${memberName(data, c.member_id)}`,
    [c.level ? `Level ${c.level}` : '', raceName(c.race), c.spec, cls].filter(Boolean).join(' '),
    ...profs,
  ].join('\n')
}

export function charsOf(data: GuildData, memberId: string): Character[] {
  return data.characters
    .filter((c) => c.member_id === memberId)
    .sort((a, b) => Number(b.is_main) - Number(a.is_main) || a.name.localeCompare(b.name))
}

export function rankName(data: GuildData, rankId: number | null): string {
  return data.ranks.find((r) => r.id === rankId)?.name ?? 'Waiting for approval'
}

export function memberName(data: GuildData, id: string): string {
  return data.members.find((m) => m.id === id)?.display_name ?? 'Someone'
}
