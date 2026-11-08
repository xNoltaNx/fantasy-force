// World of Warcraft classes, specs and roles (Midnight, 12.x). Colours are Blizzard's class colours.

export type Role = 'tank' | 'healer' | 'dps'

export interface WowClass {
  id: string
  name: string
  color: string
  specs: { name: string; role: Role }[]
}

export const CLASSES: WowClass[] = [
  { id: 'deathknight', name: 'Death Knight', color: '#C41E3A', specs: [
    { name: 'Blood', role: 'tank' }, { name: 'Frost', role: 'dps' }, { name: 'Unholy', role: 'dps' }] },
  { id: 'demonhunter', name: 'Demon Hunter', color: '#A330C9', specs: [
    { name: 'Havoc', role: 'dps' }, { name: 'Vengeance', role: 'tank' }, { name: 'Devourer', role: 'dps' }] },
  { id: 'druid', name: 'Druid', color: '#FF7C0A', specs: [
    { name: 'Balance', role: 'dps' }, { name: 'Feral', role: 'dps' }, { name: 'Guardian', role: 'tank' }, { name: 'Restoration', role: 'healer' }] },
  { id: 'evoker', name: 'Evoker', color: '#33937F', specs: [
    { name: 'Devastation', role: 'dps' }, { name: 'Preservation', role: 'healer' }, { name: 'Augmentation', role: 'dps' }] },
  { id: 'hunter', name: 'Hunter', color: '#AAD372', specs: [
    { name: 'Beast Mastery', role: 'dps' }, { name: 'Marksmanship', role: 'dps' }, { name: 'Survival', role: 'dps' }] },
  { id: 'mage', name: 'Mage', color: '#3FC7EB', specs: [
    { name: 'Arcane', role: 'dps' }, { name: 'Fire', role: 'dps' }, { name: 'Frost', role: 'dps' }] },
  { id: 'monk', name: 'Monk', color: '#00FF98', specs: [
    { name: 'Brewmaster', role: 'tank' }, { name: 'Mistweaver', role: 'healer' }, { name: 'Windwalker', role: 'dps' }] },
  { id: 'paladin', name: 'Paladin', color: '#F48CBA', specs: [
    { name: 'Holy', role: 'healer' }, { name: 'Protection', role: 'tank' }, { name: 'Retribution', role: 'dps' }] },
  { id: 'priest', name: 'Priest', color: '#FFFFFF', specs: [
    { name: 'Discipline', role: 'healer' }, { name: 'Holy', role: 'healer' }, { name: 'Shadow', role: 'dps' }] },
  { id: 'rogue', name: 'Rogue', color: '#FFF468', specs: [
    { name: 'Assassination', role: 'dps' }, { name: 'Outlaw', role: 'dps' }, { name: 'Subtlety', role: 'dps' }] },
  { id: 'shaman', name: 'Shaman', color: '#0070DD', specs: [
    { name: 'Elemental', role: 'dps' }, { name: 'Enhancement', role: 'dps' }, { name: 'Restoration', role: 'healer' }] },
  { id: 'warlock', name: 'Warlock', color: '#8788EE', specs: [
    { name: 'Affliction', role: 'dps' }, { name: 'Demonology', role: 'dps' }, { name: 'Destruction', role: 'dps' }] },
  { id: 'warrior', name: 'Warrior', color: '#C69B6D', specs: [
    { name: 'Arms', role: 'dps' }, { name: 'Fury', role: 'dps' }, { name: 'Protection', role: 'tank' }] },
]

export const ROLES: { id: Role; name: string; icon: string }[] = [
  { id: 'tank', name: 'Tank', icon: '🛡️' },
  { id: 'healer', name: 'Healer', icon: '✚' },
  { id: 'dps', name: 'DPS', icon: '⚔️' },
]

export function classById(id: string): WowClass | undefined {
  return CLASSES.find((c) => c.id === id)
}

export function roleFor(classId: string, spec: string): Role {
  return classById(classId)?.specs.find((s) => s.name === spec)?.role ?? 'dps'
}

export function roleName(role: Role): string {
  return ROLES.find((r) => r.id === role)?.name ?? role
}

/** The realm as Blizzard's URLs write it: lower case, spaces to dashes, apostrophes dropped. */
export function realmSlug(realm: string): string {
  return realm.trim().toLowerCase().replace(/['’]/g, '').replace(/\s+/g, '-')
}

export function armoryUrl(region: string, realm: string, name: string): string {
  return `https://worldofwarcraft.blizzard.com/en-us/character/${region}/${realmSlug(realm)}/${encodeURIComponent(name.toLowerCase())}`
}

export function raiderIoUrl(region: string, realm: string, name: string): string {
  return `https://raider.io/characters/${region}/${realmSlug(realm)}/${encodeURIComponent(name)}`
}
