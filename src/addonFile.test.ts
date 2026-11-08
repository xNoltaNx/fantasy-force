import { describe, expect, it } from 'vitest'
import { parseLuaTable, readAddonFile } from './addonFile'

const SAMPLE = `
FantasyForceDB = {
	["version"] = 1,
	["characters"] = {
		["Grukka Stonefist"] = {
			["name"] = "Grukka Stonefist",
			["level"] = 60,
			["class"] = "WARRIOR",
			["race"] = "Orc",
			["raceName"] = "Orc",
			["faction"] = "Horde",
			["spec"] = "Protection",
			["talents"] = { 5, 11, 35, },
			["professions"] = {
				{ ["name"] = "Blacksmithing", ["skill"] = 300, ["max"] = 300, }, -- [1]
				{ ["name"] = "Mining", ["skill"] = 285, ["max"] = 300, }, -- [2]
			},
			["guild"] = "Fantasy Force",
			["rank"] = "Officer",
			["updated"] = 1731100000,
		},
		["Mossy Underbridge"] = {
			["name"] = "Mossy Underbridge",
			["level"] = 23,
			["class"] = "DRUID",
			["race"] = "Tauren",
			["spec"] = "Feral Combat",
			["professions"] = {},
			["guild"] = "",
		},
	},
	["guild"] = {
		["name"] = "Fantasy Force",
		["updated"] = 1731100000,
		["by"] = "Grukka Stonefist",
		["members"] = {
			{ ["name"] = "Grukka Stonefist", ["rank"] = "Officer", ["rankIndex"] = 1, ["level"] = 60, ["class"] = "WARRIOR", ["note"] = "tank \\"main\\"", ["online"] = true, ["lastOnline"] = 0, },
			{ ["name"] = "Vel'ari Dusk", ["rank"] = "Raider", ["rankIndex"] = 2, ["level"] = 58, ["class"] = "PRIEST", ["note"] = "", ["online"] = false, },
		},
	},
}
`

describe('parseLuaTable', () => {
  it('reads nested tables, arrays, strings, numbers, booleans and comments', () => {
    const v = parseLuaTable('{ ["a"] = 1, b = -2.5, "x", true, nil, { 3 }, ["s"] = "q\\"\\n" } -- end') as Record<string, unknown>
    expect(v).toEqual({ a: 1, b: -2.5, 1: 'x', 2: true, 3: null, 4: [3], s: 'q"\n' })
  })

  it('turns a table with only sequential keys into an array', () => {
    expect(parseLuaTable('{ 1, 2, 3, }')).toEqual([1, 2, 3])
    expect(parseLuaTable('{}')).toEqual([])
  })

  it('refuses code, not just data', () => {
    expect(() => parseLuaTable('{ a = os.exit() }')).toThrow()
  })
})

describe('readAddonFile', () => {
  it('reads characters with their class, race, spec, role and professions', () => {
    const f = readAddonFile(SAMPLE)
    expect(f.characters).toHaveLength(2)
    const g = f.characters.find((c) => c.name === 'Grukka Stonefist')!
    expect(g).toMatchObject({ class_id: 'warrior', race: 'orc', level: 60, spec: 'Protection', role: 'tank', inGuild: true })
    expect(g.professions).toEqual([{ name: 'Blacksmithing', skill: 300, max: 300 }, { name: 'Mining', skill: 285, max: 300 }])
    const m = f.characters.find((c) => c.name === 'Mossy Underbridge')!
    expect(m).toMatchObject({ class_id: 'druid', race: 'tauren', spec: 'Feral (cat)', role: 'dps', inGuild: false })
  })

  it('reads the guild roster the addon saw', () => {
    const f = readAddonFile(SAMPLE)
    expect(f.guild?.name).toBe('Fantasy Force')
    expect(f.guild?.members).toEqual([
      { name: 'Grukka Stonefist', rank: 'Officer', rank_index: 1, level: 60, class_id: 'warrior', note: 'tank "main"', online: true, last_online_days: 0 },
      { name: "Vel'ari Dusk", rank: 'Raider', rank_index: 2, level: 58, class_id: 'priest', note: '', online: false, last_online_days: null },
    ])
  })

  it('says plainly when the file is not the addon file', () => {
    expect(() => readAddonFile('SomethingElseDB = {}')).toThrow(/FantasyForce\.lua/)
  })
})
