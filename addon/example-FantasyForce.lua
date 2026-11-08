
-- An example of the addon's saved file, for trying the site's import without the game.
-- The real one is World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\FantasyForce.lua
FantasyForceDB = {
	["version"] = 1,
	["characters"] = {
		["Kettle Brewgut"] = {
			["name"] = "Kettle Brewgut",
			["level"] = 60,
			["class"] = "HUNTER",
			["race"] = "Orc",
			["raceName"] = "Orc",
			["faction"] = "Horde",
			["spec"] = "Beast Mastery",
			["talents"] = { 31, 20, 0, },
			["professions"] = {
				{ ["name"] = "Engineering", ["skill"] = 300, ["max"] = 300, }, -- [1]
				{ ["name"] = "Mining", ["skill"] = 300, ["max"] = 300, }, -- [2]
				{ ["name"] = "Fishing", ["skill"] = 150, ["max"] = 225, }, -- [3]
			},
			["recipes"] = {
				["Engineering"] = {
					{ ["id"] = 3919, ["name"] = "Rough Dynamite", }, -- [1]
					{ ["id"] = 12619, ["name"] = "Hi-Explosive Bomb", }, -- [2]
					{ ["id"] = 19790, ["name"] = "Thorium Grenade", }, -- [3]
					{ ["id"] = 12760, ["name"] = "Goblin Sapper Charge", }, -- [4]
				},
			},
			["guild"] = "Fantasy Force",
			["rank"] = "Raider",
			["updated"] = 1762632000,
		},
		["Kettle Emberbrew"] = {
			["name"] = "Kettle Emberbrew",
			["level"] = 36,
			["class"] = "SHAMAN",
			["race"] = "Troll",
			["raceName"] = "Troll",
			["faction"] = "Horde",
			["spec"] = "Restoration",
			["professions"] = {
				{ ["name"] = "Herbalism", ["skill"] = 190, ["max"] = 225, }, -- [1]
				{ ["name"] = "Alchemy", ["skill"] = 175, ["max"] = 225, }, -- [2]
			},
			["guild"] = "Fantasy Force",
			["rank"] = "Alt",
			["updated"] = 1762632000,
		},
		["Kettle Bankalt"] = {
			["name"] = "Kettle Bankalt",
			["level"] = 1,
			["class"] = "WARRIOR",
			["race"] = "Undead",
			["raceName"] = "Undead",
			["faction"] = "Horde",
			["spec"] = "",
			["professions"] = {},
			["guild"] = "",
			["rank"] = "",
			["updated"] = 1762632000,
		},
	},
	["bankAlts"] = { ["Kettle Bankalt"] = true, },
	["bank"] = {
		["source"] = "alt",
		["updated"] = 1762632000,
		["by"] = "Kettle Bankalt",
		["money"] = 1234567,
		["tabs"] = {
			{ ["name"] = "Bags", ["items"] = {
				{ ["id"] = 13446, ["name"] = "Major Healing Potion", ["count"] = 40, ["quality"] = 1, },
				{ ["id"] = 13459, ["name"] = "Greater Shadow Protection Potion", ["count"] = 12, ["quality"] = 1, },
				{ ["id"] = 12404, ["name"] = "Dense Sharpening Stone", ["count"] = 60, ["quality"] = 1, },
				{ ["id"] = 7076, ["name"] = "Essence of Earth", ["count"] = 18, ["quality"] = 1, },
				{ ["id"] = 12359, ["name"] = "Thorium Bar", ["count"] = 75, ["quality"] = 1, },
			}, },
			{ ["name"] = "Bank", ["items"] = {
				{ ["id"] = 13444, ["name"] = "Major Mana Potion", ["count"] = 35, ["quality"] = 1, },
				{ ["id"] = 12753, ["name"] = "Skin of Shadow", ["count"] = 5, ["quality"] = 1, },
				{ ["id"] = 7078, ["name"] = "Essence of Fire", ["count"] = 22, ["quality"] = 1, },
				{ ["id"] = 15410, ["name"] = "Scale of Onyxia", ["count"] = 9, ["quality"] = 3, },
				{ ["id"] = 11382, ["name"] = "Blood of the Mountain", ["count"] = 14, ["quality"] = 1, },
				{ ["id"] = 17010, ["name"] = "Fiery Core", ["count"] = 6, ["quality"] = 2, },
			}, },
		},
	},
	["raids"] = {
		{
			["key"] = "Molten Core 2026-11-07",
			["zone"] = "Molten Core",
			["started"] = 1762540800,
			["ended"] = 1762551600,
			["by"] = "Kettle Brewgut",
			["attendees"] = { "Kettle Brewgut", "Zug Bramblehoof", "Thalia", "Grimjaw", "Sylvara", "Mokk", "Pyrewind", "Dunmar", },
			["bosses"] = {
				{ ["name"] = "Lucifron", ["killed"] = 1762542000, ["attendees"] = { "Kettle Brewgut", "Zug Bramblehoof", "Thalia", "Grimjaw", "Sylvara", "Mokk", "Pyrewind", }, },
				{ ["name"] = "Magmadar", ["killed"] = 1762544000, ["attendees"] = { "Kettle Brewgut", "Zug Bramblehoof", "Thalia", "Grimjaw", "Sylvara", "Mokk", "Pyrewind", "Dunmar", }, },
				{ ["name"] = "Gehennas", ["killed"] = 1762546000, ["attendees"] = { "Kettle Brewgut", "Zug Bramblehoof", "Thalia", "Grimjaw", "Sylvara", "Pyrewind", "Dunmar", }, },
			},
			["loot"] = {
				{ ["id"] = 16800, ["name"] = "Arcanist Boots", ["quality"] = 4, ["to"] = "Sylvara", ["at"] = 1762542100, ["boss"] = "Lucifron", },
				{ ["id"] = 16796, ["name"] = "Arcanist Leggings", ["quality"] = 4, ["to"] = "Pyrewind", ["at"] = 1762544100, ["boss"] = "Magmadar", },
				{ ["id"] = 16862, ["name"] = "Sabatons of Might", ["quality"] = 4, ["to"] = "Grimjaw", ["at"] = 1762546100, ["boss"] = "Gehennas", },
			},
		},
	},
	["guild"] = {
		["name"] = "Fantasy Force",
		["updated"] = 1762632000,
		["by"] = "Kettle Brewgut",
		["members"] = {
			{ ["name"] = "Kettle Brewgut", ["rank"] = "Raider", ["rankIndex"] = 2, ["level"] = 60, ["class"] = "HUNTER", ["note"] = "", ["online"] = true, ["lastOnline"] = 0, }, -- [1]
			{ ["name"] = "Zug Bramblehoof", ["rank"] = "Member", ["rankIndex"] = 3, ["level"] = 60, ["class"] = "SHAMAN", ["note"] = "returning player", ["online"] = false, ["lastOnline"] = 1, }, -- [2]
		},
	},
}
