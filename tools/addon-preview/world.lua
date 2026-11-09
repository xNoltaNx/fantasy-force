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
  end
  return out
end

-- Guildmates' accounts (the first character is the main). Online characters marked with true.
-- { name, class, race, level, { { profession, skill } }, online }
local ACCOUNTS = {
  { { "Grukka Stonefist", "WARRIOR", "Orc", 60, { { "Blacksmithing", 300 }, { "Mining", 300 } }, true },
    { "Ashka Stonefist", "PRIEST", "Troll", 34, { { "Tailoring", 165 }, { "First Aid", 225 } } },
    { "Fantasy Bankalt", "WARRIOR", "Undead", 5, {} } },
  { { "Morwen Hollowmere", "PRIEST", "Undead", 60, { { "Alchemy", 300 }, { "Herbalism", 300 } }, true },
    { "Silt Hollowmere", "ROGUE", "Undead", 47, { { "Skinning", 220 }, { "Leatherworking", 210 } } },
    { "Ember Hollowmere", "MAGE", "Undead", 19, { { "Enchanting", 90 } } } },
  { { "Brakka Ironhide", "DRUID", "Tauren", 60, { { "Leatherworking", 300 }, { "Skinning", 300 } } },
    { "Brakka Longsight", "HUNTER", "Orc", 52, { { "Engineering", 240 }, { "Mining", 245 } }, true } },
  { { "Sunniva Windcaller", "SHAMAN", "Skyborne", 60, { { "Herbalism", 300 }, { "Alchemy", 295 }, { "Cooking", 300 } } },
    { "Sunclaw Windcaller", "DRUID", "Tauren", 41, { { "Fishing", 180 } } } },
  { { "Vashir Nightshade", "ROGUE", "Troll", 60, { { "Alchemy", 260 }, { "Herbalism", 270 } } },
    { "Vashir Dreadmoor", "WARLOCK", "Undead", 38, { { "Tailoring", 180 } }, true },
    { "Vashtusk Grimhorn", "WARRIOR", "Tauren", 26, { { "Mining", 110 } } } },
  { { "Orla Tidesong", "SHAMAN", "Troll", 60, { { "Herbalism", 300 }, { "First Aid", 300 } }, true },
    { "Orla Stormcrest", "SHAMAN", "Skyborne", 44, { { "Enchanting", 200 }, { "Tailoring", 210 } } } },
  { { "Pip Ashwhistle", "MAGE", "Undead", 60, { { "Tailoring", 300 }, { "Enchanting", 290 } }, true } },
  { { "Dunmore Blackthorn", "WARLOCK", "Undead", 60, { { "Tailoring", 285 }, { "Enchanting", 300 } } },
    { "Dunmore Ruttusk", "WARRIOR", "Orc", 30, { { "Blacksmithing", 140 }, { "Mining", 150 } } } },
  { { "Yseth Moonhoof", "DRUID", "Tauren", 60, { { "Herbalism", 300 }, { "Alchemy", 300 } } } },
  { { "Grell Bonechewer", "HUNTER", "Troll", 58, { { "Skinning", 280 }, { "Leatherworking", 270 } } },
    { "Grell Hexmoor", "PRIEST", "Troll", 27, {} } },
  { { "Marrow Gravelkin", "WARRIOR", "Undead", 60, { { "Mining", 300 }, { "Blacksmithing", 290 }, { "Fishing", 300 } } } },
  { { "Tamsin Duskhorn", "DRUID", "Tauren", 56, { { "Cooking", 260 }, { "Fishing", 240 } } },
    { "Tamsin Wraithe", "PRIEST", "Undead", 33, { { "Tailoring", 160 } } } },
}

-- In the guild, without the addon (the guild list only).
local ROSTER_ONLY = {
  { "Hobb Quickfingers", "ROGUE", 49 }, { "Liora Skywhisper", "SHAMAN", 42 }, { "Quill Redmane", "WARRIOR", 37 },
  { "Zug Bramblehoof", "SHAMAN", 60 }, { "Krenn Saltfang", "MAGE", 45, true }, { "Nyx Thistlewhip", "WARLOCK", 33 },
}

-- The player's own account: the main the preview logs in as, and two alts (one with recipes not recorded yet).
local OWN = {
  { "Kettle Brewgut", "HUNTER", "Orc", 60, { { "Engineering", 300 }, { "Mining", 280 } }, true },
  { "Kettle Emberbrew", "SHAMAN", "Troll", 36, { { "Herbalism", 190 }, { "Alchemy", 175 } }, false, noRecipes = true },
  { "Kettle Duskhoof", "DRUID", "Tauren", 24, { { "Skinning", 110 }, { "Leatherworking", 105 } } },
}

local function record(c, now, ago)
  local rec = { name = c[1], class = c[2], race = c[3], raceName = c[3], level = c[4], faction = "Horde",
    guild = GUILD, rank = "Raider", updated = now - ago, professions = {}, recipes = {} }
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
  for id, it in pairs(ITEMS) do W.items[id] = { name = it[1], quality = it[2], icon = "Interface\\Icons\\" .. it[3] } end
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
    W.roster[#W.roster + 1] = { name = m[1], class = m[2], level = m[3], online = m[4] and true or false, rank = "Member", rankIndex = 3 }
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

  local here = { "Kettle Brewgut", "Grukka Stonefist", "Morwen Hollowmere", "Brakka Ironhide", "Sunniva Windcaller",
    "Vashir Nightshade", "Orla Tidesong", "Pip Ashwhistle", "Dunmore Blackthorn", "Yseth Moonhoof", "Marrow Gravelkin" }
  W.raids = {
    raid(now, 12, 6, { { 16800, "Arcanist Boots", 0 }, { 16862, "Sabatons of Might", 2 } }, here),
    raid(now, 9, 8, { { 16796, "Arcanist Leggings", 1 }, { 16849, "Giantstalker's Boots", 2 }, { 16837, "Earthfury Boots", 4 } }, here),
    raid(now, 5, 10, { { 16805, "Felheart Gloves", 0 }, { 16829, "Cenarion Boots", 2 }, { 19147, "Ring of Spell Power", 8 } }, here),
  }

  -- a few lines already in guild chat when the preview starts (alts get their main in front)
  W.guildChat = {
    { "Grukka Stonefist", "Raid invites at 7:15, bring fire resist." },
    { "Brakka Longsight", "Anyone need Thorium Grenades? I can make a stack." },
    { "Vashir Dreadmoor", "Logged my alt for a sec, back on Vashir soon." },
  }
  return W
end
