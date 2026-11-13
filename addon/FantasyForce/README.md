# FantasyForce

A small addon for World of Warcraft: Forever that quietly records your characters and your guild roster so the Fantasy Force website can import them. In game it shows the guild bank and your guildmates' crafting anywhere, puts a guildmate's main in front of what they say on an alt, and can make you talk in your race's accent. No chat spam.

## What it records

Per character on this account: name, level, class, race, faction, spec (the talent tree with the most points) and points per tree, every profession and secondary skill with its skill level, guild and guild rank.

Recipes: the game only lists them while a profession window is open, so open each profession once on each character (and again after learning new ones), with what each takes (its reagents and counts) where the game says. Only your own: a linked or guild recipe list is never recorded.

Roles: each character's Tank, Healer and Damage, set on the Options tab or by right-clicking your own character on the Guild tab. Until you pick, they follow the spec (the website's rule: Protection warriors and paladins and bear druids tank; Holy paladins and priests, Discipline priests, Restoration shamans and druids heal; any other spec is damage; no spec known, no roles).

Once a minute at most, when the server sends the guild roster: every member's name, rank, level, class, public note and online status (and days since last online). Zones and officer notes (the latter only if your rank may view them) are kept in memory for the Guild tab's tooltips and never saved.

Your own bags and banks: every character on this account, its bags on login and when they change (at most every 10 seconds) and its bank (and reagent bank, on clients that have one) when you open it and while it's open, for the Bank tab's Mine. Private: never sent to anyone unless that character is the bank alt, and kept in `FantasyForceDB.personal`, which the site ignores.

Item facts: the required level, item level and quality of items the windows sort, as the game answers (`FantasyForceDB.itemFacts[id] = { q, r, i }`), so sorting works after login before the game has them again.

Guild bank: when you open it (if this game has one), every tab you can view, with its items (stacks of one item combined per tab) and the gold. Forever may have no guild bank, so use a bank alt instead (below).

Bank alt: after `/ff bankalt` on a character, its bags are recorded on login and when they change (at most every 10 seconds), and its bank each time you open it. Mail it your guild's spare gear and the site shows the bank.

Raids: while you are in a raid group inside a raid instance, one record per raid per day: everyone seen in the raid (checked on entering, on every boss kill and every 10 minutes), each boss kill with who was there, and the loot. Loot is only epic (purple) or better by default; `/ff loot rare` also records rares, `/ff loot epic` goes back. Only the last 60 raids are kept.

## The window

`/ff` (or the round guild icon on the minimap) opens one window, anywhere. Drag it to move it (it remembers where), Escape or `/ff` closes it. It's the game's own portrait window (gold trim, the guild's icon in the round portrait; on a game without that template, a plain window with the icon as a badge in a thin gold ring); the pages start below the portrait; the header has your character's name (a star on your main) and two small icons: the speech bubble turns your accent on or off (the same as `/accent`), the "i" shows every command. Tabs along the bottom:

Bank and Crafting share one shape, like the game's profession window: a list on the left, the items in the middle under foldable categories (from the item's class: Consumables, Trade goods, Armor by type, Weapons, Bags, Recipes, Quest; else from words in the name; Other last), and the picked one on the right. Both remember what was picked.

Both sort the same way: headers over the middle list, Name, Rarity, Level (required level, else item level; anything not an item last) and Crafters on Crafting or Count on Bank. Click one to sort, again to reverse; each tab remembers its own. Groups (on by default) keeps the categories; off makes one flat list. Sorting by Level shows each level small and grey at the row's right. Items the game hasn't loaded yet are asked for and the list re-sorts when they arrive, keeping the picked row in view. (No Skill sort: the game doesn't say a recipe's skill level.)

- **Bank** (`/ff bank`): the guild bank. Left: All, then each tab (Bags and Bank for a bank alt) with its item count, and the gold. Middle: each item once with its icon, name in its quality colour and count; Grid shows them as bag slots instead. Right: the item, how many and where (Bags 12, Bank 38), when it was recorded and by whom, what changed since the scan before ("+20 since 2 days ago"), a real guild bank's last deposits and withdrawals, and Ask, which starts a whisper to the bank alt (for a guild bank, the guild master) asking for one, with the item's link. Hover for the item's tooltip; shift-click links it. On the bank alt's account it shows your own record, otherwise the newest one shared by the guild. The left list has two groups. Guild is the guild bank ("No bank alt yet" until someone sets one). Mine is your own account: All mine (every character's things added up), then each character in its class colour with its item count; hover one for when its bank was last seen, or "Open your bank once". An item's detail there says who has it where ("Kettle: Bags 4, Bank 10; Ember: Bags 2"), and search covers Mine too. At the bottom of the left list, Set bank alt makes this character the bank alt (Bank alt and a tick when it is; press again to stop), the same as `/ff bankalt` and the Options tick.
- **Crafting** (`/ff crafts`): who in the guild can make what. Left: All, then each profession with its icon and recipe count. Middle: the recipes with how many can make them (a green dot when one is online); search finds recipes and crafters, Online keeps what someone online can make. Right: the recipe, what it takes, and everyone who can make it, online first, with level, skill and a Whisper button. Someone offline whose alt is online is whispered on the alt. Shift-click links.
- **Craft requests** (on Crafting): New request, at the top of the Requests list, walks you through asking the guild in three steps, on a small panel over the right-hand side (the lists stay usable): 1 Recipe (everything someone else in the guild can make, with a search box and a row of professions; online crafters first, each with how many can make it and a green dot when one is online), 2 Crafter ("Anyone who can make it", or one of them: name in class colour, online dot, level and skill, when they were last seen; "Nobody online now: they'll see it when they log in" when nobody is), 3 Details (how many with - and +, 1 to 200; "I have mats"; a short note; a summary line such as "Thorium Grenade x10, mats ready, to Pip"). Back keeps every choice; Send asks. Request, on a recipe's Crafters heading, opens it on step 2 with that recipe picked. One request per recipe per character at a time: asking again for one you've asked for says Update request and changes it (the recipe says Requested, with Cancel). A request to one crafter alerts only them and shows under their For you; others who can make it see it greyed under For others (they can still offer); the asker can change it to everyone with Ask anyone. Requests sits at the top of Crafting's left list: under For you what your characters can make, under For others what was asked of someone else, under Being made what someone has taken, under Yours your own (waiting, to whom, or who's making it). Pick one for I'll make it (everyone sees who took it), Whisper, and for the asker Cancel and Done; whoever took it can press Made it. Done or cancelled ones go from every list. The minimap button and the Crafting tab show how many open requests you can make.
- **Request alerts:** when a request comes in that one of your characters can make, one chat line ("Craft request: [Thorium Grenade] x10 from Grukka, /ff crafts") and a small notice at the top of the screen, below the zone text: the recipe's icon, "Craft request", "Thorium Grenade x10 from Grukka" (a tick when they have the mats). It fades after 8 seconds (not while the mouse is on it); click it to open Crafting > Requests on that request, right-click to dismiss. Up to three show at once, the rest as "+2 more requests" (and in chat, three lines then "+2 more craft requests"). The asker gets the same when someone takes theirs ("Pip will make your Robe of the Archmage") and when they've made it ("Pip made your Robe of the Archmage"). In the first minutes after login, new requests make one line instead ("2 craft requests: /ff crafts"). Never in combat: the notices and their sound wait for the fight to end. Each request alerts once. Options > Chat: Request alerts (the notices; the chat line always comes) and Alert sound (a soft sound with them), both on. A request goes to whoever is online and is passed on to crafters who log in later, like the rest; it's dropped after 7 days.
- **Guild** (`/ff guild`): the whole guild, like the game's roster, with what guildmates' addons add: Name, Role, Class, Level and Rank columns (click to sort, again to reverse; remembered; Rank sorts in the guild's rank order), each main with its alts under it. Members without the addon have a grey "no addon" mark (hover: "No addon: game info only"); their main and alts are guessed only from a plain public note ("alt of Zug", "Zug alt", "Zug's alt", "main: Zug", naming someone in the guild), and the tooltip says it's from their note. Filters in one row: Online, the nine classes, the three roles (none picked means all), and Alts (off lists mains only); More folds out a filter by rank. The footer counts everyone: "34 players, 9 online" (with filters, "5 of 34"). Hover for level, rank, roles and professions, the zone (online) or when they were last seen, the public note, and the officer note if your rank may see it; click to whisper; right-click your own character to set its roles. The roster is kept between sessions, so the list is there at login; while it's more than 5 minutes old the footer says "Updated 2 hours ago".
- **KOS** (`/ff kos` with no target): the guild's kill-on-sight list. Under Attacked you, the enemy players who attacked you since you logged in and aren't marked yet (killed you or attacked you, how long ago); click one to mark them. Under Kill on sight, everyone marked, newest first: name in class colour, their guild, the reason, who marked them and when. Search finds names, guilds, reasons and markers. Mark target (top right) marks your target; shift-right-click a mark to clear it.
- **Website** (`/ff site`): three steps to put your characters on the site: 1 Save (reloads, so the game writes the file), 2 the file's path to copy, 3 drop it on My characters at the site's address (to copy). Under them, this account's characters: a star on the main, a warning when a profession's recipes aren't recorded yet (hover: "Open Tailoring once"). Officers also see what else their file carries (guild list, bank, raids).
- **Options** (`/ff options`): Character ("Main: Kettle" with Set main, and under it "Your other characters are its alts."; Roles, Bank alt, Minimap button; More: raid loot), Chat (Mains in chat, Request alerts, Alert sound), Accent (the accent, Light or Thick, Shift+Enter, a one-line preview; More: which chats). Each control does what its command does, and the window follows the commands too.

## Kill on sight

Guildmates mark enemy players to be killed on sight, and everyone in the guild with the addon sees the mark.

- **Marking:** target them and type `/ff kos` (or press Mark target on the KOS tab, the "Mark target kill on sight" key in Key Bindings > Fantasy Force, or Mark kill on sight in the target's right-click menu, on game versions that let addons add to it). Add a reason after a dash: `/ff kos - ganks lowbies at the Crossroads`. Someone not in sight: `/ff kos Itz Shifty - ganker` (any case). Marking someone already marked with a reason changes the reason. You can't mark yourself or anyone in your guild.
- **Attacked:** when an enemy player hurts you (or misses, or puts something on you), a notice drops in at the top of the screen, "Attacked by Itz Shifty" with what's known of them (level, race, class, guild) and a **Mark KOS** button that works mid-fight. If they kill you it says "Killed by". One chat line says the same, and `/ff kos last` marks the last one. Each attacker is offered once a minute; already marked ones get the kill-on-sight warning instead. Not in battlegrounds or arenas. Duels don't count (from a challenge until the duel ends, at most 3 minutes, since the game doesn't always say when a challenge is declined).
- **Seeing them:** a marked player wears the skull (a skull on a red crosshair, `Media/Kos.tga`) with a pulsing red glow on the target and focus frames' portrait and above their nameplate, and their tooltip says "Kill on sight", who marked them, when and why. The first time you see one in 5 minutes (target, focus, mouseover or nameplate), chat says "Kill on sight: Itz Shifty (32 Night Elf Druid, <DYNASTY>) is here: ganker" with the raid warning sound; `/ff kos alerts off` stops those lines (the skulls stay).
- **Clearing:** `/ff kos clear Itz Shifty` (or `/ff kos clear` with them targeted, or shift-right-click on the KOS tab). Anyone in the guild may mark or clear; the mark says who did.
- **Names:** WoW Forever's names are "First Last". A mark typed by name matches the player when the game gives their full name, or their first name alone when only one mark starts with it (and the class agrees once known). The first time someone with the addon sees a typed mark's player, the mark learns their class, race, level, guild and character id, and passes them on.
- When a guildmate marks someone, a chat line says so (marks passed on at login, older than 10 minutes, don't).

## Mains and alts

Each player's addon tells the guild which of their characters belong together and which one is the main.

- Your main is the character you typed `/ff main` on (per guild). Until you do, it's your highest-level character in the guild (on a tie, the one you played last).
- Guild and officer chat: when someone speaks on an alt you see their main in front, `(Morwen) anyone up for Strat?`. Nothing changes when they're on their main. Only your own chat window changes: the message others see is exactly what was typed. `/ff tags off` turns this off, `/ff tags on` back on.
- Hovering a guildmate (their character in the world, or their portrait) adds "Alt of Morwen" on an alt, or "Alts: Bob (60), Jim (42)" on a main, and their professions with skill.
- Like crafting, you only see this for guildmates who run the addon too, and offline members' links are passed on by whoever is online.

## Sharing with the guild

The windows show what guildmates' addons share over the guild's hidden addon channel (guild only: never whispers, never other channels, never other guilds). You see someone's crafting only if both of you run the addon.

- Each player's addon shares its own account's characters that are in this guild: their professions with skill, and their recipes (as spell and item ids). A character in another guild is never shared.
- The bank alt's addon shares the bank: tab names, each item and count, the gold, and when it was recorded.
- Each account shares its characters in this guild (name, class, level, professions with skill, roles) and which is the main. Roles go last as letters (`=TD`); an addon from before roles shows them as an odd extra profession until it's updated.
- Craft requests: each one is a single short message (the note is cut to fit; the crafter asked, if any, goes after it, which an addon from before ignores), sent when it's asked, changed, taken, done or cancelled, and passed on like the rest. An addon from before requests ignores them.
- Kill-on-sight marks: one short message each (the reason is cut to fit), sent when someone marks, changes or clears one, and passed on like the rest; a clear is kept 30 days so a late copy of the mark can't bring it back. An addon from before KOS ignores them.
- When: shortly after you log in (a random 5 to 20 seconds, only what changed since it last went out), 10 seconds after something changes (a profession window opened, the bank alt's bags or bank changed), and when someone asks. About a minute after you log in, and when you open a window, the addon asks the guild for anything newer than what you have, at most once an hour.
- Anyone online can answer for someone who's offline, so you see the bank even when the bank alt isn't on. Only one copy goes out: whoever starts first, the others stay quiet.
- Sending is paced at about one short message a second (the game's own limit), so it never floods or gets you disconnected. A big recipe list is 5 to 8 messages.
- What you've been sent is kept in your saved file, so the windows work right after login before anyone answers. Crafters not heard from in 60 days are dropped.

## Accents

Talk like your race, for fun. Off until you pick one; it's saved per character. Pick it on the Options tab, or:

- `/accent` turns it on or off, remembering which accent and strength you had (the very first time: your race's). The speech bubble in the window does the same. `/accent status` says what's on and whether this game lets it change chat.
- `/accent troll` (or `orc`, `tauren`, `undead`, `skyborne`), `/accent auto` (your character's race: Troll, Orc, Tauren, Forsaken, Skyborne; Alliance races stay plain), `/accent off`.
- `/accent light` swaps a few words; `/accent thick` swaps more and now and then adds a closing line ("Ya mon!", "Lok'tar!", "Walk with the Earth Mother.").
- Where you talk in it: the accent's own chat line. Press Shift+Enter, click the speech bubble by your chat tab (shown while an accent is on), or set a key in Key Bindings > Fantasy Force. It opens where the chat box sits, on the chat the game's box is on (`/s`, `/g`, `/w Name` at its start switch it, as in the game's box; `/w Azujin` whispers Azujin Rimetusk when the guild has only one Azujin), and Enter (or Shift+Enter) sends it in your accent. The addon's Whisper and Ask buttons open it too, and shift-clicked links go into it.
- Shift+Enter: while an accent is on, Shift+Enter opens the accent line; Enter, `/` and Reply stay the game's chat box. If you've bound Shift+Enter to something yourself in Key Bindings, it stays yours (the accent line's own key binding still works). Turn it off with the Options tick "Shift+Enter". In combat the key only changes once combat ends. A `/command` typed in the accent line isn't sent; it says "Commands: press / to type them in the game's chat box."
- The game's own chat box is never touched, so what you type there goes out as typed. On newer game versions an addon that hooks or writes to the chat box gets the game's own chat and slash commands blocked ("FantasyForce has been blocked from an action only available to the Blizzard UI"), so this addon doesn't.
- It converts say, yell, guild, officer, party, raid and whispers. `/accent chat <type> on|off` changes the list (e.g. `/accent chat whisper off`). Never channels like Trade.
- `/accent debug` says what's in (the line, the bubble, no chat box hooks), what Shift+Enter does ("Shift+Enter: opens the line" or "the game's"), and the last few actions the game blocked for any addon, as "Blocked: <addon>: <function>" (or "Blocked: nothing"), then how the next line you send went.
- `/troll` turns troll on and off; `/troll <message>` sends that one message in troll to the chat you're typing in, whatever your accent is.
- Mail: the send mail window has an Accent button in the corner of the letter. It rewrites the letter (and its subject, lightly) in your accent (or your race's, if you haven't picked one). Press it again within 10 seconds to undo.
- Never changed: item, spell and quest links, coloured text, player names in links, `/commands`, raid icons like `{skull}`, `[anything in brackets]`, `@names`, web addresses and numbers (300g, 3:30, 10x). A message that would go past chat's 255 letters drops its closing line, then goes light, then goes as typed.
- The word lists are tables at the top of `Accent.lua`, easy to edit. Skyborne is new in Forever, so its accent (sky, wind and wings) is a placeholder until the race has a voice of its own.
- If the game ever blocks the addon, one line says what it blocked and the accent line sends as typed; `/troll <message>` and the mail button still work.

## Names

On WoW Forever characters have a first and a last name, and the guild roster, chat and whispers use both ("Azujin Rimetusk"). Everything the addon records and shares uses the full name: the saved file's characters, mains, roles, requests and banks, and what goes over the guild channel. The game's own name functions may give the first name alone, so the addon takes the full name from the first one that gives it, else from the guild roster (the online member with your first name, class and level), and remembers it per character; until it's known, nothing is shared. Records an older version kept under a first name alone move to the full name at login (yours) or when the roster comes (a guildmate's, when only one member has that first name). The site's import matches names case-insensitively, as full names.

## Where the data lives

The game writes it when you log out or `/reload`:

```
World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\FantasyForce.lua
```

Drag that file onto the guild website to import. (The beta client used `_classic_beta_` instead of `_forever_`; if neither exists, use Battle.net's gear icon > Show in Explorer and look for `WTF\Account`.)

Mains and alts in the saved file, for the site:

```lua
FantasyForceDB.mains = { ["Fantasy Force"] = "Morwen" }       -- this account's /ff main, per guild (absent: highest level)
FantasyForceDB.mainOf = { Morwen = "Morwen", Bob = "Morwen", Kettle = "Kettle" }  -- every character known (yours and guildmates') to its main
FantasyForceDB.shared.accounts = {                            -- what guildmates' addons shared, one entry per account
  ["tni7nu7mo5sq"] = { main = "Morwen", updated = 1793000500, from = "Bob", heard = 1793000510,
    chars = { { name = "Morwen", class = "PRIEST", level = 60, profs = { { name = "Tailoring", skill = 300 } } },
              { name = "Bob", class = "ROGUE", level = 42, profs = {} } } },
}
```

Roles, for the site, on each of this account's characters (always the roles in effect: the player's pick, else the spec's):

```lua
FantasyForceDB.characters["Morwen"].roles = { "healer", "dps" }  -- any of "tank", "healer", "dps", in that order
FantasyForceDB.characters["Morwen"].rolesSet = true             -- picked by the player (absent: from the spec)
```

Guildmates' roles are in `shared.accounts` too, as `roles` on each of their `chars`.

Kill-on-sight marks, everyone's this account has heard, by lower-case name (marks never expire; cleared ones go 30 days after they were cleared):

```lua
FantasyForceDB.kos["itz shifty"] = {
  name = "Itz Shifty", state = "kos",       -- "kos" or "cleared"
  by = "Azujin Rimetusk", added = 1793000000, -- who marked them (on a cleared mark: who cleared it) and when
  class = "DRUID", race = "Night Elf", level = 32, guild = "DYNASTY", guid = "Player-...", -- what the game showed
  reason = "ganks lowbies at the Crossroads",
  updated = 1793000400, from = "Grukka Bonesaw", heard = 1793000401,
}
FantasyForceDB.kosAlerts = false            -- /ff kos alerts off (absent: on)
```

Craft requests, everyone's in the guild that this account has heard (open, claimed, and done or cancelled ones until they're 7 days old), by id (`asker@recipeKey`; the key is the profession, `#`, then `s` and the spell id, `i` and the item id, or `n` and the name):

```lua
FantasyForceDB.requests["Mira@Engineering#s19790"] = {
  asker = "Mira", class = "PRIEST", prof = "Engineering", key = "Engineering#s19790",
  spell = 19790, item = 15993,             -- the recipe (name = "..." only when it has neither id)
  qty = 5, mats = true, note = "for Molten Core, thanks!",
  to = "Brakka",                           -- the crafter asked (absent: anyone who can make it)
  state = "claimed", claimer = "Brakka",   -- "open", "claimed", "done" or "cancelled"; claimer only once claimed
  created = 1793000000, updated = 1793000400, from = "Brakka", heard = 1793000401,
}
```

`mainOf` is the simple one to read: this account's characters in the current guild plus every guildmate who runs the addon, rebuilt whenever something changes. `shared.accounts` has the details (`from` is who passed it on, `heard` when; account ids are random and only group characters together). If two accounts list the same character (it moved), the newer `updated` wins.

Your own characters' bags and banks (the Bank tab's Mine) are under a key of their own that the site ignores; they never leave this account unless the character is the bank alt:

```lua
FantasyForceDB.personal["Kettle"] = { class = "HUNTER",
  bags = { { id = 15993, name = "Thorium Grenade", count = 4, quality = 1 } }, bagsAt = 1793000000,
  bank = { { id = 12359, name = "Thorium Bar", count = 60, quality = 1 } }, bankAt = 1792800000 }  -- no bank: never opened
```

The Guild tab reads the same guild roster record the site imports (`FantasyForceDB.guild.members`; zones and officer notes are never in it). `FantasyForceDB.itemFacts` holds item facts for sorting; the site doesn't need it.

Accent settings are in a second, per-character file, `WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\FantasyForce.lua` (`FantasyForceCharDB`); the site doesn't need it.

## Install

Put the `FantasyForce` folder in `World of Warcraft\_forever_\Interface\AddOns\`, or install from CurseForge.

To try the window without the game, `npm run addon-preview` (in the repo) builds `tools/addon-preview/dist/index.html`: these Lua files running in a browser against a pretend game and guild.

## Commands

`/ff help` prints this list in game; the window's "i" icon shows the same list.

- `/ff` opens or closes the window; `/ff bank`, `/ff crafts`, `/ff guild`, `/ff site`, `/ff options` open it on that tab.
- `/ff status` prints how many characters, guild members and raids are recorded, how many guildmates' crafters were shared, the last update, and whether this character is a bank alt.
- `/ff main` makes this character your main in this guild; `/ff tags off|on` hides or shows mains in front of alts in guild chat.
- `/ff kos` marks your target kill on sight (no target: opens the KOS tab); `/ff kos - <reason>` with a reason; `/ff kos <name> [- <reason>]` by name; `/ff kos last [- <reason>]` the last enemy player who attacked you; `/ff kos clear [<name>]` clears one; `/ff kos list` lists them in chat; `/ff kos alerts off|on`.
- `/ff bankalt` makes this character the guild's bank alt (or turns it off again).
- `/ff loot rare` records rare (blue) raid loot too; `/ff loot epic` returns to epic only.
- `/ff minimap off|on` hides or shows the minimap button.
- `/ff reset` clears everything recorded, and what guildmates shared.
- `/accent` turns your accent on or off; `/accent status`, `/accent help`, `/accent <name>`, `/accent light|thick`, `/accent chat <type> on|off`, and `/troll ...`: see Accents above.
