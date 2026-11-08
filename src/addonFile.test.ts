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
			["recipes"] = {
				["Blacksmithing"] = {
					{ ["id"] = 16988, ["item"] = 12784, ["name"] = "Arcanite Reaper", }, -- [1]
					{ ["name"] = "Lionheart Helm", }, -- [2]
				},
				["Cooking"] = {
					{ ["name"] = "Grilled Squid", }, -- [1]
				},
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

const BANK_AND_RAIDS = `FantasyForceDB = {
  bank = { source = "guild", updated = 1731100000, by = "Grukka Stonefist", money = 1234567,
    tabs = {
      { name = "Consumables", items = { { id = 13446, name = "Major Healing Potion", count = 40, quality = 1 }, { id = 12360, name = "Arcanite Bar", count = 3, quality = 2 } } },
      { name = "Mats", items = {} },
    },
  },
  raids = {
    { key = "Molten Core 2026-11-10", zone = "Molten Core", started = 1731100000, ended = 1731110000, by = "Grukka Stonefist",
      attendees = { "Grukka Stonefist", "Pip Ashwhistle" },
      bosses = { { name = "Lucifron", killed = 1731101000, attendees = { "Grukka Stonefist", "Pip Ashwhistle" } } },
      loot = { { id = 16800, name = "Arcanist Boots", quality = 4, to = "Pip Ashwhistle", at = 1731101200, boss = "Lucifron" } },
    },
  },
}`

describe('readAddonFile: bank and raids', () => {
  it('reads the guild bank by tab, with gold', () => {
    const f = readAddonFile(BANK_AND_RAIDS)
    expect(f.bank).toEqual({
      source: 'guild', updated_at: new Date(1731100000 * 1000).toISOString(), recorded_by: 'Grukka Stonefist', money: 1234567,
      tabs: [
        { name: 'Consumables', items: [{ id: 13446, name: 'Major Healing Potion', count: 40, quality: 1 }, { id: 12360, name: 'Arcanite Bar', count: 3, quality: 2 }] },
        { name: 'Mats', items: [] },
      ],
    })
  })

  it('reads raids with bosses, attendance and loot', () => {
    const [r] = readAddonFile(BANK_AND_RAIDS).raids
    expect(r).toEqual({
      key: 'Molten Core 2026-11-10', zone: 'Molten Core', recorded_by: 'Grukka Stonefist',
      started_at: new Date(1731100000 * 1000).toISOString(), ended_at: new Date(1731110000 * 1000).toISOString(),
      attendees: ['Grukka Stonefist', 'Pip Ashwhistle'],
      bosses: [{ name: 'Lucifron', killed_at: new Date(1731101000 * 1000).toISOString(), attendees: ['Grukka Stonefist', 'Pip Ashwhistle'] }],
      loot: [{ item_id: 16800, name: 'Arcanist Boots', quality: 4, to: 'Pip Ashwhistle', at: new Date(1731101200 * 1000).toISOString(), boss: 'Lucifron' }],
    })
  })
})

describe('readAddonFile', () => {
  it('reads characters with their class, race, spec, role and professions', () => {
    const f = readAddonFile(SAMPLE)
    expect(f.characters).toHaveLength(2)
    const g = f.characters.find((c) => c.name === 'Grukka Stonefist')!
    expect(g).toMatchObject({ class_id: 'warrior', race: 'orc', level: 60, spec: 'Protection', role: 'tank', inGuild: true })
    expect(g.professions).toEqual([
      { name: 'Blacksmithing', skill: 300, max: 300, recipes: [{ name: 'Arcanite Reaper', spell: 16988, item: 12784 }, { name: 'Lionheart Helm' }] },
      { name: 'Mining', skill: 285, max: 300 },
      { name: 'Cooking', skill: 0, max: 0, recipes: [{ name: 'Grilled Squid' }] }, // recipes for a skill the list didn't name still arrive
    ])
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

  it('marks the main chosen in game with /ff main, for its guild only', () => {
    const withMain = SAMPLE.replace(/\}\s*$/, '\t["mains"] = { ["Fantasy Force"] = "grukka stonefist", ["Other Guild"] = "Mossy Underbridge", },\n}\n')
    const f = readAddonFile(withMain)
    expect(f.characters.find((c) => c.name === 'Grukka Stonefist')!.main).toBe(true)
    expect(f.characters.find((c) => c.name === 'Mossy Underbridge')!.main).toBe(false)
    expect(readAddonFile(SAMPLE).characters.every((c) => !c.main)).toBe(true)
  })

  it('says plainly when the file is not the addon file', () => {
    expect(() => readAddonFile('SomethingElseDB = {}')).toThrow(/FantasyForce\.lua/)
  })
})
