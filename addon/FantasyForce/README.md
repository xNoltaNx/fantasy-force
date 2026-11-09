# FantasyForce

A small addon for World of Warcraft: Forever that quietly records your characters and your guild roster so the Fantasy Force website can import them. In game it shows the guild bank and your guildmates' crafting anywhere, puts a guildmate's main in front of what they say on an alt, and can make you talk in your race's accent. No chat spam.

## What it records

Per character on this account: name, level, class, race, faction, spec (the talent tree with the most points) and points per tree, every profession and secondary skill with its skill level, guild and guild rank.

Recipes: the game only lists them while a profession window is open, so open each profession once on each character (and again after learning new ones), with what each takes (its reagents and counts) where the game says. Only your own: a linked or guild recipe list is never recorded.

Roles: each character's Tank, Healer and Damage, set on the Options tab or by right-clicking your own character on the Guild tab. Until you pick, they follow the spec (the website's rule: Protection warriors and paladins and bear druids tank; Holy paladins and priests, Discipline priests, Restoration shamans and druids heal; any other spec is damage; no spec known, no roles).

Once a minute at most, when the server sends the guild roster: every member's name, rank, level, class, public note and online status (and days since last online). Officer notes are never read.

Guild bank: when you open it (if this game has one), every tab you can view, with its items (stacks of one item combined per tab) and the gold. Forever may have no guild bank, so use a bank alt instead (below).

Bank alt: after `/ff bankalt` on a character, its bags are recorded on login and when they change (at most every 10 seconds), and its bank each time you open it. Mail it your guild's spare gear and the site shows the bank.

Raids: while you are in a raid group inside a raid instance, one record per raid per day: everyone seen in the raid (checked on entering, on every boss kill and every 10 minutes), each boss kill with who was there, and the loot. Loot is only epic (purple) or better by default; `/ff loot rare` also records rares, `/ff loot epic` goes back. Only the last 60 raids are kept.

## The window

`/ff` (or the round guild icon on the minimap) opens one window, anywhere. Drag it to move it (it remembers where), Escape or `/ff` closes it. The guild's icon sits on its corner; the header has your character's name (a star on your main) and two small icons: the speech bubble turns your accent on or off (the same as `/accent`), the "i" shows every command. Tabs along the bottom:

Bank and Crafting share one shape, like the game's profession window: a list on the left, the items in the middle under foldable categories (from the item's class: Consumables, Trade goods, Armor by type, Weapons, Bags, Recipes, Quest; else from words in the name; Other last), and the picked one on the right. Both remember what was picked.

- **Bank** (`/ff bank`): the guild bank. Left: All, then each tab (Bags and Bank for a bank alt) with its item count, and the gold. Middle: each item once with its icon, name in its quality colour and count; Grid shows them as bag slots instead. Right: the item, how many and where (Bags 12, Bank 38), when it was recorded and by whom, what changed since the scan before ("+20 since 2 days ago"), a real guild bank's last deposits and withdrawals, and Ask, which starts a whisper to the bank alt (for a guild bank, the guild master) asking for one, with the item's link. Hover for the item's tooltip; shift-click links it. On the bank alt's account it shows your own record, otherwise the newest one shared by the guild.
- **Crafting** (`/ff crafts`): who in the guild can make what. Left: All, then each profession with its icon and recipe count. Middle: the recipes with how many can make them (a green dot when one is online); search finds recipes and crafters, Online keeps what someone online can make. Right: the recipe, what it takes, and everyone who can make it, online first, with level, skill and a Whisper button. Someone offline whose alt is online is whispered on the alt. Shift-click links.
- **Guild** (`/ff guild`): everyone running the addon, like the game's roster: Name, Role, Class and Level columns (click to sort, again to reverse; remembered), each main with its alts under it. Filters in one row: Online, the nine classes, the three roles (none picked means all), and Alts (off lists mains only); the footer then says "5 of 13". Hover for level, roles and professions; click to whisper; right-click your own character to set its roles.
- **Website** (`/ff site`): three steps to put your characters on the site: 1 Save (reloads, so the game writes the file), 2 the file's path to copy, 3 drop it on My characters at the site's address (to copy). Under them, this account's characters: a star on the main, a warning when a profession's recipes aren't recorded yet (hover: "Open Tailoring once"). Officers also see what else their file carries (guild list, bank, raids).
- **Options** (`/ff options`): Character (Set main, Roles, Bank alt, Minimap button; More: raid loot), Chat (Mains in chat), Accent (the accent, Light or Thick, a one-line preview; More: which chats). Each control does what its command does, and the window follows the commands too.

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
- When: shortly after you log in (a random 5 to 20 seconds, only what changed since it last went out), 10 seconds after something changes (a profession window opened, the bank alt's bags or bank changed), and when someone asks. About a minute after you log in, and when you open a window, the addon asks the guild for anything newer than what you have, at most once an hour.
- Anyone online can answer for someone who's offline, so you see the bank even when the bank alt isn't on. Only one copy goes out: whoever starts first, the others stay quiet.
- Sending is paced at about one short message a second (the game's own limit), so it never floods or gets you disconnected. A big recipe list is 5 to 8 messages.
- What you've been sent is kept in your saved file, so the windows work right after login before anyone answers. Crafters not heard from in 60 days are dropped.

## Accents

Talk like your race, for fun. Off until you pick one; it's saved per character. Pick it on the Options tab, or:

- `/accent` turns it on or off, remembering which accent and strength you had (the very first time: your race's). The speech bubble in the window does the same. `/accent status` says what's on and whether this game lets it change chat.
- `/accent troll` (or `orc`, `tauren`, `undead`, `skyborne`), `/accent auto` (your character's race: Troll, Orc, Tauren, Forsaken, Skyborne; Alliance races stay plain), `/accent off`.
- `/accent light` swaps a few words; `/accent thick` swaps more and now and then adds a closing line ("Ya mon!", "Lok'tar!", "Walk with the Earth Mother.").
- Where you talk in it: the accent's own chat line. Click the speech bubble by your chat tab (shown while an accent is on), or set a key in Key Bindings > Fantasy Force. It opens where the chat box sits, on the chat the game's box is on (`/s`, `/g`, `/w Name` at its start switch it, as in the game's box), and Enter sends it in your accent. The addon's Whisper and Ask buttons open it too, and shift-clicked links go into it.
- The game's own chat box is never touched, so what you type there goes out as typed. On newer game versions an addon that hooks or writes to the chat box gets the game's own chat and slash commands blocked ("FantasyForce has been blocked from an action only available to the Blizzard UI"), so this addon doesn't.
- It converts say, yell, guild, officer, party, raid and whispers. `/accent chat <type> on|off` changes the list (e.g. `/accent chat whisper off`). Never channels like Trade.
- `/accent debug` says what's in (the line, the bubble, no chat box hooks) and anything the game blocked, then how the next line you send went.
- `/troll` turns troll on and off; `/troll <message>` sends that one message in troll to the chat you're typing in, whatever your accent is.
- Mail: the send mail window has an Accent button in the corner of the letter. It rewrites the letter (and its subject, lightly) in your accent (or your race's, if you haven't picked one). Press it again within 10 seconds to undo.
- Never changed: item, spell and quest links, coloured text, player names in links, `/commands`, raid icons like `{skull}`, `[anything in brackets]`, `@names`, web addresses and numbers (300g, 3:30, 10x). A message that would go past chat's 255 letters drops its closing line, then goes light, then goes as typed.
- The word lists are tables at the top of `Accent.lua`, easy to edit. Skyborne is new in Forever, so its accent (sky, wind and wings) is a placeholder until the race has a voice of its own.
- If the game ever blocks the addon, one line says what it blocked and the accent line sends as typed; `/troll <message>` and the mail button still work.

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

`mainOf` is the simple one to read: this account's characters in the current guild plus every guildmate who runs the addon, rebuilt whenever something changes. `shared.accounts` has the details (`from` is who passed it on, `heard` when; account ids are random and only group characters together). If two accounts list the same character (it moved), the newer `updated` wins.

Accent settings are in a second, per-character file, `WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\FantasyForce.lua` (`FantasyForceCharDB`); the site doesn't need it.

## Install

Put the `FantasyForce` folder in `World of Warcraft\_forever_\Interface\AddOns\`, or install from CurseForge.

To try the window without the game, `npm run addon-preview` (in the repo) builds `tools/addon-preview/dist/index.html`: these Lua files running in a browser against a pretend game and guild.

## Commands

`/ff help` prints this list in game; the window's "i" icon shows the same list.

- `/ff` opens or closes the window; `/ff bank`, `/ff crafts`, `/ff guild`, `/ff site`, `/ff options` open it on that tab.
- `/ff status` prints how many characters, guild members and raids are recorded, how many guildmates' crafters were shared, the last update, and whether this character is a bank alt.
- `/ff main` makes this character your main in this guild; `/ff tags off|on` hides or shows mains in front of alts in guild chat.
- `/ff bankalt` makes this character the guild's bank alt (or turns it off again).
- `/ff loot rare` records rare (blue) raid loot too; `/ff loot epic` returns to epic only.
- `/ff minimap off|on` hides or shows the minimap button.
- `/ff reset` clears everything recorded, and what guildmates shared.
- `/accent` turns your accent on or off; `/accent status`, `/accent help`, `/accent <name>`, `/accent light|thick`, `/accent chat <type> on|off`, and `/troll ...`: see Accents above.
