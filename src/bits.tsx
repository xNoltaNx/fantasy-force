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

/** Whether something (an event, a kill-on-sight mark) is up in the guild's Discord: the Discord logo, lit or faded, named on hover. */
export function DiscordMark({ posted }: { posted: boolean }) {
  const label = posted ? 'Posted in Discord' : 'Not in Discord yet'
  return (
    <span className={`discord-mark ${posted ? 'on' : ''}`} title={label} role="img" aria-label={label}>
      <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="currentColor">
        <path d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.057 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028 14.09 14.09 0 0 0 1.226-1.994.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.946 2.418-2.157 2.418z" />
      </svg>
    </span>
  )
}
