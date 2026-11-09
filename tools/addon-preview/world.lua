-- The pretend guild the preview plays in: Fantasy Force, a Horde guild on WoW Forever. Names, characters and
-- recipes follow the website's example guild (src/store/seed.ts); items and icons are the real ones.
-- Returns world(now): what the pretend game knows (items, spells, the roster) and what the player's
-- account has recorded, plus the guildmates' accounts their addons share.

local GUILD = "Fantasy Force"

-- [id] = { name, quality, icon }
local ITEMS = {
  [118] = { "Minor Healing Potion", 1, "inv_potion_49" },
  [1251] = { "Linen Bandage", 1, "inv_misc_bandage_15" },
  [2304] = { "Light Armor Kit", 1, "inv_misc_armorkit_17" },
  [2459] = { "Swiftness Potion", 1, "inv_potion_95" },
  [2840] = { "Copper Bar", 1, "inv_ingot_02" },
  [2851] = { "Copper Chain Belt", 1, "inv_belt_02" },
  [2862] = { "Rough Sharpening Stone", 1, "inv_stone_sharpeningstone_01" },
  [2871] = { "Heavy Sharpening Stone", 1, "inv_stone_sharpeningstone_03" },
  [3575] = { "Iron Bar", 1, "inv_ingot_iron" },
  [3825] = { "Elixir of Fortitude", 1, "inv_potion_43" },
  [3860] = { "Mithril Bar", 1, "inv_ingot_06" },
  [4238] = { "Linen Bag", 1, "inv_misc_bag_01" },
  [4358] = { "Rough Dynamite", 1, "inv_misc_bomb_06" },
  [6948] = { "Hearthstone", 1, "inv_misc_rune_01" },
  [7068] = { "Elemental Fire", 1, "spell_fire_fire" },
  [7078] = { "Essence of Fire", 2, "spell_fire_volcano" },
  [7969] = { "Mithril Spurs", 2, "ability_rogue_sprint" },
  [8545] = { "Heavy Mageweave Bandage", 1, "inv_misc_bandage_20" },
  [10562] = { "Hi-Explosive Bomb", 1, "inv_misc_bomb_07" },
  [10646] = { "Goblin Sapper Charge", 1, "spell_fire_selfdestruct" },
  [11604] = { "Dark Iron Plate", 3, "inv_chest_plate08" },
  [12217] = { "Dragonbreath Chili", 1, "inv_drink_17" },
  [12359] = { "Thorium Bar", 1, "inv_ingot_07" },
  [12360] = { "Arcanite Bar", 2, "inv_misc_stonetablet_05" },
  [12404] = { "Dense Sharpening Stone", 1, "inv_stone_sharpeningstone_05" },
  [12640] = { "Lionheart Helm", 4, "inv_helmet_36" },
  [12643] = { "Dense Weightstone", 1, "inv_stone_weightstone_05" },
  [12784] = { "Arcanite Reaper", 3, "inv_axe_09" },
  [12811] = { "Righteous Orb", 2, "inv_misc_gem_pearl_03" },
  [13444] = { "Major Mana Potion", 1, "inv_potion_76" },
  [13446] = { "Major Healing Potion", 1, "inv_potion_54" },
  [13452] = { "Elixir of the Mongoose", 1, "inv_potion_32" },
  [13457] = { "Greater Fire Protection Potion", 1, "inv_potion_24" },
  [13468] = { "Black Lotus", 2, "inv_misc_herb_blacklotus" },
  [13510] = { "Flask of the Titans", 1, "inv_potion_62" },
  [13928] = { "Grilled Squid", 1, "inv_misc_fish_13" },
  [13931] = { "Nightfin Soup", 1, "inv_drink_17" },
  [14046] = { "Runecloth Bag", 1, "inv_misc_bag_19" },
  [14047] = { "Runecloth", 1, "inv_fabric_purplefire_01" },
  [14048] = { "Bolt of Runecloth", 1, "inv_fabric_purplefire_02" },
  [14152] = { "Robe of the Archmage", 4, "inv_chest_cloth_38" },
  [14154] = { "Truefaith Vestments", 4, "inv_chest_cloth_31" },
  [14155] = { "Mooncloth Bag", 2, "inv_misc_bag_14" },
  [14342] = { "Mooncloth", 1, "inv_fabric_moonrag_01" },
  [14344] = { "Large Brilliant Shard", 3, "inv_enchant_shardbrilliantlarge" },
  [14530] = { "Heavy Runecloth Bandage", 1, "inv_misc_bandage_12" },
  [15062] = { "Devilsaur Leggings", 3, "inv_pants_wolf" },
  [15063] = { "Devilsaur Gauntlets", 3, "inv_gauntlets_26" },
  [15417] = { "Devilsaur Leather", 1, "inv_misc_pelt_03" },
  [15564] = { "Rugged Armor Kit", 1, "inv_misc_armorkit_09" },
  [15993] = { "Thorium Grenade", 1, "inv_misc_bomb_08" },
  [16022] = { "Arcanite Dragonling", 3, "inv_misc_head_dragon_01" },
  [17010] = { "Fiery Core", 3, "spell_fire_flamebolt" },
  [17011] = { "Lava Core", 3, "spell_nature_earthquake" },
  [18251] = { "Core Armor Kit", 3, "inv_misc_armorkit_05" },
  [20452] = { "Smoked Desert Dumplings", 1, "inv_misc_food_64" },
  -- reagents
  [2589] = { "Linen Cloth", 1, "inv_fabric_linen_01" },
  [2770] = { "Copper Ore", 1, "inv_ore_copper_01" },
  [2772] = { "Iron Ore", 1, "inv_ore_iron_01" },
  [3858] = { "Mithril Ore", 1, "inv_ore_mithril_02" },
  [10620] = { "Thorium Ore", 1, "inv_ore_thorium_02" },
  [4338] = { "Mageweave Cloth", 1, "inv_fabric_mageweave_01" },
  [4357] = { "Rough Blasting Powder", 1, "inv_misc_dust_01" },
  [10560] = { "Unstable Trigger", 1, "inv_battery_01" },
  [10561] = { "Mithril Casing", 1, "inv_gizmo_mithrilcasing_01" },
  [15992] = { "Dense Blasting Powder", 1, "inv_misc_ammo_gunpowder_01" },
  [15994] = { "Thorium Widget", 1, "inv_gizmo_04" },
}

-- Item classes, as GetItemInfoInstant gives them (0 consumable, 1 bag, 2 weapon, 4 armour, 7 trade goods,
-- 15 miscellaneous): [id] = { classID, subtype }; anything not listed is trade goods.
local CLASSES = {
  [118] = { 0 }, [1251] = { 0 }, [2304] = { 0 }, [2459] = { 0 }, [2862] = { 0 }, [2871] = { 0 }, [3825] = { 0 },
  [8545] = { 0 }, [12217] = { 0 }, [12404] = { 0 }, [12643] = { 0 }, [13444] = { 0 }, [13446] = { 0 }, [13452] = { 0 },
  [13457] = { 0 }, [13510] = { 0 }, [13928] = { 0 }, [13931] = { 0 }, [14530] = { 0 }, [15564] = { 0 }, [18251] = { 0 },
  [20452] = { 0 },
  [4238] = { 1, "Bag" }, [14046] = { 1, "Bag" }, [14155] = { 1, "Bag" },
  [12784] = { 2, "Two-Handed Axes" },
  [2851] = { 4, "Mail" }, [11604] = { 4, "Plate" }, [12640] = { 4, "Plate" }, [14152] = { 4, "Cloth" }, [14154] = { 4, "Cloth" },
  [15062] = { 4, "Leather" }, [15063] = { 4, "Leather" }, [16022] = { 4, "Miscellaneous" },
  [6948] = { 15, "Junk" },
}

-- Required level and item level, as GetItemInfo gives them: [id] = { required, item level }; the rest 0, 0.
local LEVELS = {
  [118] = { 1, 5 }, [2459] = { 0, 10 }, [3825] = { 0, 20 }, [13457] = { 48, 58 }, [13452] = { 46, 56 }, [13446] = { 45, 55 },
  [13444] = { 49, 59 }, [13510] = { 50, 60 }, [12360] = { 0, 55 }, [2862] = { 0, 5 }, [2851] = { 2, 7 }, [2871] = { 0, 25 },
  [7969] = { 0, 40 }, [12643] = { 0, 55 }, [11604] = { 58, 63 }, [12640] = { 56, 61 }, [12784] = { 58, 63 }, [4238] = { 0, 10 },
  [14048] = { 0, 55 }, [14046] = { 0, 55 }, [14155] = { 0, 60 }, [14154] = { 57, 62 }, [14152] = { 57, 62 }, [2304] = { 1, 5 },
  [15564] = { 50, 60 }, [15063] = { 53, 58 }, [15062] = { 55, 60 }, [18251] = { 60, 65 }, [4358] = { 0, 10 }, [10562] = { 0, 47 },
  [15993] = { 0, 47 }, [10646] = { 0, 50 }, [16022] = { 0, 60 }, [13928] = { 40, 50 }, [13931] = { 45, 55 }, [20452] = { 45, 55 },
  [12217] = { 35, 45 }, [1251] = { 0, 5 }, [8545] = { 0, 40 }, [14530] = { 0, 58 }, [2840] = { 0, 10 }, [3575] = { 0, 20 },
  [3860] = { 0, 30 }, [12359] = { 0, 50 },
}

-- [id] = { name, icon }
local SPELLS = {
  [2657] = { "Smelt Copper", "inv_ingot_02" },
  [3307] = { "Smelt Iron", "inv_ingot_iron" },
  [10097] = { "Smelt Mithril", "inv_ingot_06" },
  [16153] = { "Smelt Thorium", "inv_ingot_07" },
  [13890] = { "Enchant Boots - Minor Speed", "spell_holy_greaterheal" },
  [20011] = { "Enchant Bracer - Superior Stamina", "spell_holy_greaterheal" },
  [20012] = { "Enchant Gloves - Greater Agility", "spell_holy_greaterheal" },
  [20026] = { "Enchant Chest - Major Health", "spell_holy_greaterheal" },
  [20034] = { "Enchant Weapon - Crusader", "spell_holy_greaterheal" },
  -- the professions themselves
  [2259] = { "Alchemy", "trade_alchemy" }, [2018] = { "Blacksmithing", "trade_blacksmithing" },
  [7411] = { "Enchanting", "trade_engraving" }, [4036] = { "Engineering", "trade_engineering" },
  [2108] = { "Leatherworking", "inv_misc_armorkit_17" }, [3908] = { "Tailoring", "trade_tailoring" },
  [2550] = { "Cooking", "inv_misc_food_15" }, [3273] = { "First Aid", "spell_holy_sealofsacrifice" },
  [2575] = { "Mining", "trade_mining" }, [2366] = { "Herb Gathering", "spell_nature_naturetouchgrow" },
  [8613] = { "Skinning", "inv_misc_pelt_wolf_01" }, [7620] = { "Fishing", "trade_fishing" },
}

-- What some recipes take, recorded with the player's own recipes: [made item] = { { item, count } }.
local REAGENTS = {
  [2840] = { { 2770, 1 } }, [3575] = { { 2772, 1 } }, [3860] = { { 3858, 1 } }, [12359] = { { 10620, 1 } },
  [4358] = { { 4357, 2 }, { 2589, 1 } },
  [10562] = { { 10561, 1 }, { 15992, 2 }, { 3860, 1 } },
  [15993] = { { 15994, 1 }, { 12359, 3 }, { 15992, 3 }, { 14047, 3 } },
  [10646] = { { 4338, 1 }, { 15992, 3 }, { 10560, 1 } },
  [16022] = { { 15994, 4 }, { 12360, 10 }, { 17010, 4 }, { 14047, 6 } },
}

-- Recipes by profession, low skill to high: a character knows the share their skill reaches.
-- { item } for crafts, { spell = id } for enchants and smelting.
local RECIPES = {
  Blacksmithing = { 2862, 2851, 2871, 7969, 12643, 11604, 12640, 12784 },
  Alchemy = { 118, 2459, 3825, 13457, 13452, 13446, 13444, 12360, 13510 },
  Enchanting = { { spell = 13890 }, { spell = 20011 }, { spell = 20012 }, { spell = 20026 }, { spell = 20034 } },
  Tailoring = { 4238, 14048, 14046, 14155, 14154, 14152 },
  Leatherworking = { 2304, 15564, 15063, 15062, 18251 },
  Engineering = { 4358, 10562, 15993, 10646, 16022 },
  Cooking = { 13928, 13931, 20452, 12217 },
  ["First Aid"] = { 1251, 8545, 14530 },
  Mining = { { spell = 2657, item = 2840 }, { spell = 3307, item = 3575 }, { spell = 10097, item = 3860 }, { spell = 16153, item = 12359 } },
}
local GATHERING = { Herbalism = true, Skinning = true, Fishing = true }

local function recipesAt(prof, skill)
  local all = RECIPES[prof]
  if not all then return nil end
  local n = math.max(1, math.floor(skill / 300 * #all + 0.5))
  local out = {}
  for i = 1, math.min(n, #all) do
    local r = all[i]
    if type(r) == "number" then
      out[#out + 1] = { item = r, name = ITEMS[r][1] }
    else
      out[#out + 1] = { id = r.spell, item = r.item, name = SPELLS[r.spell][1] }
    end
    local made = out[#out].item
    if REAGENTS[made] then
      out[#out].reagents = {}
      for _, g in ipairs(REAGENTS[made]) do table.insert(out[#out].reagents, { item = g[1], count = g[2] }) end
    end
  end
  return out
end

-- Guildmates' accounts (the first character is the main). Online characters marked with true.
-- { name, class, race, level, { { profession, skill } }, online, spec = talent tree, roles = their own pick }
-- Roles follow the spec (the website's rule) unless the player picked them.
local ACCOUNTS = {
  { { "Grukka Stonefist", "WARRIOR", "Orc", 60, { { "Blacksmithing", 300 }, { "Mining", 300 } }, true, spec = "Protection" },
    { "Ashka Stonefist", "PRIEST", "Troll", 34, { { "Tailoring", 165 }, { "First Aid", 225 } }, spec = "Shadow" },
    { "Fantasy Bankalt", "WARRIOR", "Undead", 5, {} } },
  { { "Morwen Hollowmere", "PRIEST", "Undead", 60, { { "Alchemy", 300 }, { "Herbalism", 300 } }, true, spec = "Holy" },
    { "Silt Hollowmere", "ROGUE", "Undead", 47, { { "Skinning", 220 }, { "Leatherworking", 210 } }, spec = "Combat" },
    { "Ember Hollowmere", "MAGE", "Undead", 19, { { "Enchanting", 90 } }, spec = "Frost" } },
  { { "Brakka Ironhide", "DRUID", "Tauren", 60, { { "Leatherworking", 300 }, { "Skinning", 300 } }, spec = "Feral (bear)", roles = { "tank", "dps" } },
    { "Brakka Longsight", "HUNTER", "Orc", 52, { { "Engineering", 240 }, { "Mining", 245 } }, true, spec = "Marksmanship" } },
  { { "Sunniva Windcaller", "SHAMAN", "Skyborne", 60, { { "Herbalism", 300 }, { "Alchemy", 295 }, { "Cooking", 300 } }, spec = "Restoration" },
    { "Sunclaw Windcaller", "DRUID", "Tauren", 41, { { "Fishing", 180 } }, spec = "Balance" } },
  { { "Vashir Nightshade", "ROGUE", "Troll", 60, { { "Alchemy", 260 }, { "Herbalism", 270 } }, spec = "Combat" },
    { "Vashir Dreadmoor", "WARLOCK", "Undead", 38, { { "Tailoring", 180 } }, true, spec = "Affliction" },
    { "Vashtusk Grimhorn", "WARRIOR", "Tauren", 26, { { "Mining", 110 } }, spec = "Protection" } },
  { { "Orla Tidesong", "SHAMAN", "Troll", 60, { { "Herbalism", 300 }, { "First Aid", 300 } }, true, spec = "Restoration" },
    { "Orla Stormcrest", "SHAMAN", "Skyborne", 44, { { "Enchanting", 200 }, { "Tailoring", 210 } }, spec = "Elemental" } },
  { { "Pip Ashwhistle", "MAGE", "Undead", 60, { { "Tailoring", 300 }, { "Enchanting", 290 } }, true, spec = "Frost" } },
  { { "Dunmore Blackthorn", "WARLOCK", "Undead", 60, { { "Tailoring", 285 }, { "Enchanting", 300 } }, spec = "Destruction" },
    { "Dunmore Ruttusk", "WARRIOR", "Orc", 30, { { "Blacksmithing", 140 }, { "Mining", 150 } }, spec = "Arms" } },
  { { "Yseth Moonhoof", "DRUID", "Tauren", 60, { { "Herbalism", 300 }, { "Alchemy", 300 } }, spec = "Restoration", roles = { "healer", "dps" } } },
  { { "Grell Bonechewer", "HUNTER", "Troll", 58, { { "Skinning", 280 }, { "Leatherworking", 270 } }, spec = "Beast Mastery" },
    { "Grell Hexmoor", "PRIEST", "Troll", 27, {}, spec = "Discipline" } },
  { { "Marrow Gravelkin", "WARRIOR", "Undead", 60, { { "Mining", 300 }, { "Blacksmithing", 290 }, { "Fishing", 300 } }, spec = "Arms", roles = { "tank", "dps" } } },
  { { "Tamsin Duskhorn", "DRUID", "Tauren", 56, { { "Cooking", 260 }, { "Fishing", 240 } }, spec = "Balance" },
    { "Tamsin Wraithe", "PRIEST", "Undead", 33, { { "Tailoring", 160 } }, spec = "Holy" } },
}

-- In the guild, without the addon (the guild list only): { name, class, level, online, note, days offline,
-- officer note, zone }. Some notes say whose alt it is ("alt of X", "X's alt", "main: X"), which the Guild tab guesses from.
local ROSTER_ONLY = {
  { "Hobb Quickfingers", "ROGUE", 49, false, "PvP mostly", 2 },
  { "Liora Skywhisper", "SHAMAN", 42, false, "Zug's alt", 1 },
  { "Quill Redmane", "WARRIOR", 37, false, "main: Zug", 4, "Asked about tanking" },
  { "Zug Bramblehoof", "SHAMAN", 60, true, "Resto, MC Thursdays", 0, "Trial ends 20 Nov", "Molten Core" },
  { "Krenn Saltfang", "MAGE", 45, true, "", 0, nil, "Tanaris" },
  { "Nyx Thistlewhip", "WARLOCK", 33, false, "alt of Hobb", 6 },
  { "Rurik Ashenmaul", "WARRIOR", 60, false, "back after the holidays", 143, "Kept on the list, ask before removing" },
  { "Tova Brightwool", "PRIEST", 18, false, "Pip alt", 3 },
}

-- The player's own account: the main the preview logs in as, and two alts (one with recipes not recorded yet).
local OWN = {
  { "Kettle Brewgut", "HUNTER", "Orc", 60, { { "Engineering", 300 }, { "Mining", 280 } }, true, spec = "Marksmanship" },
  { "Kettle Emberbrew", "SHAMAN", "Troll", 36, { { "Herbalism", 190 }, { "Alchemy", 175 } }, false, noRecipes = true, spec = "Restoration" },
  { "Kettle Duskhoof", "DRUID", "Tauren", 24, { { "Skinning", 110 }, { "Leatherworking", 105 } }, spec = "Feral (bear)" },
}

local function record(c, now, ago)
  local rec = { name = c[1], class = c[2], race = c[3], raceName = c[3], level = c[4], faction = "Horde",
    guild = GUILD, rank = "Raider", updated = now - ago, professions = {}, recipes = {}, spec = c.spec }
  if c.roles then rec.roles, rec.rolesSet = c.roles, true end
  for _, p in ipairs(c[5]) do
    rec.professions[#rec.professions + 1] = { name = p[1], skill = p[2], max = 300 }
    if not GATHERING[p[1]] and not c.noRecipes then rec.recipes[p[1]] = recipesAt(p[1], p[2]) end
  end
  return rec
end

local function raid(now, daysAgo, kills, loot, attendees)
  local start = now - daysAgo * 86400
  local bosses = { "Lucifron", "Magmadar", "Gehennas", "Garr", "Baron Geddon", "Shazzrah", "Sulfuron Harbinger",
    "Golemagg the Incinerator", "Majordomo Executus", "Ragnaros" }
  local r = { key = "Molten Core " .. os.date("!%Y-%m-%d", start), zone = "Molten Core", started = start,
    ended = start + (20 + kills * 17) * 60, by = "Kettle Brewgut", attendees = attendees, bosses = {}, loot = {} }
  for i = 1, kills do r.bosses[i] = { name = bosses[i], killed = start + (20 + i * 17) * 60, attendees = attendees } end
  for i, l in ipairs(loot) do
    r.loot[i] = { id = l[1], name = l[2], quality = 4, to = attendees[(i * 3) % #attendees + 1], at = start + (22 + l[3] * 17) * 60, boss = bosses[l[3] + 1] }
  end
  return r
end

return function(now)
  local W = { guild = GUILD, items = {}, spells = {}, accounts = {}, own = {}, roster = {} }
  for id, it in pairs(ITEMS) do
    local class = CLASSES[id] or { 7, "Trade Goods" }
    local lv = LEVELS[id] or { 0, 0 }
    W.items[id] = { name = it[1], quality = it[2], icon = "Interface\\Icons\\" .. it[3], classID = class[1], sub = class[2],
      level = lv[1], ilvl = lv[2] }
  end
  for id, s in pairs(SPELLS) do W.spells[id] = { name = s[1], icon = "Interface\\Icons\\" .. s[2] } end

  for i, list in ipairs(ACCOUNTS) do
    local a = { id = "acct" .. i .. "x7q", main = list[1][1], records = {}, online = {}, updated = now - i * 2700 }
    for j, c in ipairs(list) do
      a.records[c[1]] = record(c, now, i * 3600 + j * 600)
      if c[6] then a.online[#a.online + 1] = c[1] end
      W.roster[#W.roster + 1] = { name = c[1], class = c[2], level = c[4], online = c[6] and true or false,
        rank = j == 1 and (i == 1 and "Guild Master" or i <= 3 and "Officer" or "Raider") or "Alt",
        rankIndex = j == 1 and (i == 1 and 0 or i <= 3 and 1 or 2) or 4, note = j == 1 and "" or ("alt of " .. list[1][1]:match("^%S+")) }
    end
    W.accounts[i] = a
  end
  for _, m in ipairs(ROSTER_ONLY) do
    W.roster[#W.roster + 1] = { name = m[1], class = m[2], level = m[3], online = m[4] and true or false, rank = "Member", rankIndex = 3,
      note = m[5], lastOnline = m[6], officerNote = m[7], zone = m[8] }
  end
  for i, c in ipairs(OWN) do
    W.own[c[1]] = record(c, now, i == 1 and 0 or i * 86400)
    W.roster[#W.roster + 1] = { name = c[1], class = c[2], level = c[4], online = i == 1, rank = i == 1 and "Raider" or "Alt", rankIndex = i == 1 and 2 or 4 }
  end
  W.player = { name = OWN[1][1], class = OWN[1][2], race = OWN[1][3], level = OWN[1][4], profs = W.own[OWN[1][1]].professions }

  -- the guild bank alt's bags and bank, shared by Grukka's account
  local function it(id, count) return { id = id, count = count, name = ITEMS[id][1], quality = ITEMS[id][2] } end
  W.bank = { source = "alt", by = "Fantasy Bankalt", updated = now - 26 * 3600, money = 4821537, sender = "Grukka Stonefist",
    tabs = {
      { name = "Bags", items = { it(13446, 60), it(13444, 45), it(13457, 38), it(13452, 12), it(13510, 3), it(12404, 80), it(6948, 1) } },
      { name = "Bank", items = { it(12359, 140), it(12360, 6), it(14047, 420), it(14342, 9), it(7078, 24), it(7068, 51),
        it(17010, 7), it(17011, 11), it(13468, 4), it(14344, 15), it(15417, 8), it(12811, 3), it(12784, 1), it(12640, 1) } },
    } }
  -- the scan before it, three days earlier: fewer potions and Runecloth, more Thorium, no Lionheart Helm yet
  W.bankBefore = { source = "alt", by = "Fantasy Bankalt", updated = now - 74 * 3600, money = 3950210, sender = "Grukka Stonefist",
    tabs = {
      { name = "Bags", items = { it(13446, 40), it(13444, 45), it(13457, 20), it(13452, 12), it(13510, 2), it(12404, 80), it(6948, 1) } },
      { name = "Bank", items = { it(12359, 160), it(12360, 6), it(14047, 400), it(14342, 9), it(7078, 24), it(7068, 51),
        it(17010, 5), it(17011, 11), it(13468, 4), it(14344, 15), it(15417, 8), it(12811, 3), it(12784, 1) } },
    } }

  local here = { "Kettle Brewgut", "Grukka Stonefist", "Morwen Hollowmere", "Brakka Ironhide", "Sunniva Windcaller",
    "Vashir Nightshade", "Orla Tidesong", "Pip Ashwhistle", "Dunmore Blackthorn", "Yseth Moonhoof", "Marrow Gravelkin" }
  W.raids = {
    raid(now, 12, 6, { { 16800, "Arcanist Boots", 0 }, { 16862, "Sabatons of Might", 2 } }, here),
    raid(now, 9, 8, { { 16796, "Arcanist Leggings", 1 }, { 16849, "Giantstalker's Boots", 2 }, { 16837, "Earthfury Boots", 4 } }, here),
    raid(now, 5, 10, { { 16805, "Felheart Gloves", 0 }, { 16829, "Cenarion Boots", 2 }, { 19147, "Ring of Spell Power", 8 } }, here),
  }

  -- the player's own characters' bags and banks (Bank tab, Mine): private to this account. Kettle Duskhoof
  -- has never opened a bank.
  W.personal = {
    ["Kettle Brewgut"] = { class = "HUNTER", bagsAt = now - 60, bankAt = now - 2 * 86400,
      bags = { it(15993, 4), it(10562, 12), it(12359, 20), it(13446, 5), it(6948, 1) },
      bank = { it(15993, 10), it(12359, 60), it(14047, 40), it(7078, 3), it(13444, 8) } },
    ["Kettle Emberbrew"] = { class = "SHAMAN", bagsAt = now - 3 * 86400, bankAt = now - 3 * 86400,
      bags = { it(15993, 2), it(13446, 3), it(13457, 6) },
      bank = { it(13444, 2), it(12359, 15), it(13468, 1), it(14344, 2) } },
    ["Kettle Duskhoof"] = { class = "DRUID", bagsAt = now - 5 * 86400,
      bags = { it(12359, 4), it(14047, 12), it(6948, 1) } },
  }

  -- craft requests: two Kettle can make (Engineering), and one Kettle asked for that Pip has taken
  W.requests = {
    { asker = "Orla Tidesong", class = "SHAMAN", prof = "Engineering", key = "Engineering#i15993", item = 15993, qty = 10, mats = true,
      note = "For Ragnaros. I have the Thorium!", state = "open", created = now - 2 * 3600, sender = "Orla Tidesong" },
    { asker = "Pip Ashwhistle", class = "MAGE", prof = "Engineering", key = "Engineering#i10562", item = 10562, qty = 5, mats = false,
      note = "", state = "open", created = now - 25 * 60, sender = "Pip Ashwhistle" },
    { asker = "Kettle Brewgut", class = "HUNTER", prof = "Tailoring", key = "Tailoring#i14152", item = 14152, qty = 1, mats = true,
      note = "Mooncloth's in the bank", state = "claimed", claimer = "Pip Ashwhistle", created = now - 26 * 3600, sender = "Pip Ashwhistle" },
  }

  -- a few lines already in guild chat when the preview starts (alts get their main in front)
  W.guildChat = {
    { "Grukka Stonefist", "Raid invites at 7:15, bring fire resist." },
    { "Brakka Longsight", "Anyone need Thorium Grenades? I can make a stack." },
    { "Vashir Dreadmoor", "Logged my alt for a sec, back on Vashir soon." },
  }
  return W
end
