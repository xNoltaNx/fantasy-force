// World of Warcraft: Forever (2026): the nine classes of 2004 Azeroth, their three talent trees each, and the races,
// Skyborne included. Forever rebalances the trees; the roles below are each tree's usual job, so a guild can see
// tanks, healers and DPS. Colours are Blizzard's class colours.

export type Role = 'tank' | 'healer' | 'dps'
export type Faction = 'alliance' | 'horde'

export interface WowClass {
  id: string
  name: string
  color: string
  specs: { name: string; role: Role }[]
}

export const CLASSES: WowClass[] = [
  { id: 'druid', name: 'Druid', color: '#FF7C0A', specs: [
    { name: 'Balance', role: 'dps' }, { name: 'Feral (bear)', role: 'tank' }, { name: 'Feral (cat)', role: 'dps' }, { name: 'Restoration', role: 'healer' }] },
  { id: 'hunter', name: 'Hunter', color: '#AAD372', specs: [
    { name: 'Beast Mastery', role: 'dps' }, { name: 'Marksmanship', role: 'dps' }, { name: 'Survival', role: 'dps' }] },
  { id: 'mage', name: 'Mage', color: '#3FC7EB', specs: [
    { name: 'Arcane', role: 'dps' }, { name: 'Fire', role: 'dps' }, { name: 'Frost', role: 'dps' }] },
  { id: 'paladin', name: 'Paladin', color: '#F48CBA', specs: [
    { name: 'Holy', role: 'healer' }, { name: 'Protection', role: 'tank' }, { name: 'Retribution', role: 'dps' }] },
  { id: 'priest', name: 'Priest', color: '#FFFFFF', specs: [
    { name: 'Discipline', role: 'healer' }, { name: 'Holy', role: 'healer' }, { name: 'Shadow', role: 'dps' }] },
  { id: 'rogue', name: 'Rogue', color: '#FFF468', specs: [
    { name: 'Assassination', role: 'dps' }, { name: 'Combat', role: 'dps' }, { name: 'Subtlety', role: 'dps' }] },
  { id: 'shaman', name: 'Shaman', color: '#0070DD', specs: [
    { name: 'Elemental', role: 'dps' }, { name: 'Enhancement', role: 'dps' }, { name: 'Restoration', role: 'healer' }] },
  { id: 'warlock', name: 'Warlock', color: '#8788EE', specs: [
    { name: 'Affliction', role: 'dps' }, { name: 'Demonology', role: 'dps' }, { name: 'Destruction', role: 'dps' }] },
  { id: 'warrior', name: 'Warrior', color: '#C69B6D', specs: [
    { name: 'Arms', role: 'dps' }, { name: 'Fury', role: 'dps' }, { name: 'Protection', role: 'tank' }] },
]

export const RACES: { id: string; name: string; faction: Faction | 'both' }[] = [
  { id: 'human', name: 'Human', faction: 'alliance' },
  { id: 'dwarf', name: 'Dwarf', faction: 'alliance' },
  { id: 'gnome', name: 'Gnome', faction: 'alliance' },
  { id: 'nightelf', name: 'Night Elf', faction: 'alliance' },
  { id: 'orc', name: 'Orc', faction: 'horde' },
  { id: 'undead', name: 'Undead', faction: 'horde' },
  { id: 'tauren', name: 'Tauren', faction: 'horde' },
  { id: 'troll', name: 'Troll', faction: 'horde' },
  { id: 'skyborne', name: 'Skyborne', faction: 'both' },
]

export const PROFESSIONS = [
  'Alchemy', 'Blacksmithing', 'Enchanting', 'Engineering', 'Herbalism', 'Leatherworking', 'Mining', 'Skinning', 'Tailoring',
  'Cooking', 'First Aid', 'Fishing',
]

export const RULESETS =['Normal', 'PvP', 'RP', 'RP-PvP', 'Hardcore']

export const MAX_LEVEL = 60

export const ROLES: { id: Role; name: string; icon: string }[] = [
  { id: 'tank', name: 'Tank', icon: '🛡️' },
  { id: 'healer', name: 'Healer', icon: '✚' },
  { id: 'dps', name: 'DPS', icon: '⚔️' },
]

export function classById(id: string): WowClass | undefined {
  return CLASSES.find((c) => c.id === id)
}

export function raceName(id: string): string {
  return RACES.find((r) => r.id === id)?.name ?? ''
}

export function racesFor(faction: Faction | ''): typeof RACES {
  return RACES.filter((r) => !faction || r.faction === 'both' || r.faction === faction)
}

export function roleFor(classId: string, spec: string): Role {
  return classById(classId)?.specs.find((s) => s.name === spec)?.role ?? 'dps'
}

export function roleName(role: Role): string {
  return ROLES.find((r) => r.id === role)?.name ?? role
}
