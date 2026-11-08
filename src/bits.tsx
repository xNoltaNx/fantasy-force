import type { Character, GuildData, Member } from './types'
import { armoryUrl, classById, raiderIoUrl, ROLES, type Role } from './wow'

export function RoleIcon({ role }: { role: Role }) {
  const r = ROLES.find((x) => x.id === role)!
  return <span className={`role role-${role}`} title={r.name} aria-label={r.name}>{r.icon}</span>
}

export function ClassName({ c, children }: { c: Pick<Character, 'class_id'>; children: React.ReactNode }) {
  return <span style={{ color: classById(c.class_id)?.color }}>{children}</span>
}

export function CharLine({ c, region, links = true }: { c: Character; region: string; links?: boolean }) {
  const cls = classById(c.class_id)
  return (
    <span className="charline">
      <RoleIcon role={c.role} />
      <ClassName c={c}><b>{c.name}</b></ClassName>
      <span className="muted"> {c.spec} {cls?.name}</span>
      {c.item_level ? <span className="ilvl" title="Item level">{c.item_level}</span> : null}
      {links && (
        <span className="links">
          <a href={armoryUrl(region, c.realm, c.name)} target="_blank" rel="noreferrer" title="Armory">Armory</a>
          <a href={raiderIoUrl(region, c.realm, c.name)} target="_blank" rel="noreferrer" title="Raider.IO">R.IO</a>
        </span>
      )}
    </span>
  )
}

export function Avatar({ m, size = 32 }: { m: Member; size?: number }) {
  if (m.avatar_url) return <img className="avatar" src={m.avatar_url} width={size} height={size} alt="" />
  return <span className="avatar avatar-letter" style={{ width: size, height: size }}>{m.display_name.slice(0, 1).toUpperCase()}</span>
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
