# FantasyForce

A small addon for World of Warcraft: Forever that quietly records your characters and your guild roster so the Fantasy Force website can import them. In game it shows the guild bank and your guildmates' crafting anywhere, puts a guildmate's main in front of what they say on an alt, and can make you talk in your race's accent. No chat spam.

## What it records

Per character on this account: name, level, class, race, faction, spec (the talent tree with the most points) and points per tree, every profession and secondary skill with its skill level, guild and guild rank.

Recipes: the game only lists them while a profession window is open, so open each profession once on each character (and again after learning new ones). Only your own: a linked or guild recipe list is never recorded.

Once a minute at most, when the server sends the guild roster: every member's name, rank, level, class, public note and online status (and days since last online). Officer notes are never read.

Guild bank: when you open it (if this game has one), every tab you can view, with its items (stacks of one item combined per tab) and the gold. Forever may have no guild bank, so use a bank alt instead (below).

Bank alt: after `/ff bankalt` on a character, its bags are recorded on login and when they change (at most every 10 seconds), and its bank each time you open it. Mail it your guild's spare gear and the site shows the bank.

Raids: while you are in a raid group inside a raid instance, one record per raid per day: everyone seen in the raid (checked on entering, on every boss kill and every 10 minutes), each boss kill with who was there, and the loot. Loot is only epic (purple) or better by default; `/ff loot rare` also records rares, `/ff loot epic` goes back. Only the last 60 raids are kept.

## The window

`/ff` (or the round guild icon on the minimap) opens one window, anywhere. Drag it to move it (it remembers where), Escape or `/ff` closes it. The guild's icon sits on its corner; the header has your character's name (a star on your main) and two small icons: the speech bubble turns your accent on or off (the same as `/accent`), the "i" shows every command. Tabs along the bottom:

- **Bank** (`/ff bank`): the guild bank. One row per item with its icon, name, count and tab; a search box and a button per tab; the gold and when the bank alt last updated it. Hover for the item's tooltip; shift-click links it. On the bank alt's account it shows your own record, otherwise the newest one shared by the guild.
- **Crafting** (`/ff crafts`): who in the guild can make what. A button per profession, a search box, and one row per recipe with who can make it, online people first. Someone offline whose alt is online shows as "Name (Alt)", and whispering goes to the alt. Hover for the item and every crafter's skill; click a name to whisper, click the row to whisper the first one online, shift-click to link.
- **Guild** (`/ff guild`): everyone running the addon, each main with its alts under it, online players first. Hover for level and professions; click to whisper.
- **Website** (`/ff site`): three steps to put your characters on the site: 1 Save (reloads, so the game writes the file), 2 the file's path to copy, 3 drop it on My characters at the site's address (to copy). Under them, this account's characters: a star on the main, a warning when a profession's recipes aren't recorded yet (hover: "Open Tailoring once"). Officers also see what else their file carries (guild list, bank, raids).
- **Options** (`/ff options`): Character (Set main, Bank alt, Minimap button; More: raid loot), Chat (Mains in chat), Accent (the accent, Light or Thick, a one-line preview; More: which chats). Each control does what its command does, and the window follows the commands too.

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
- Each account shares its characters in this guild (name, class, level, professions with skill) and which is the main.
- When: shortly after you log in (a random 5 to 20 seconds, only what changed since it last went out), 10 seconds after something changes (a profession window opened, the bank alt's bags or bank changed), and when someone asks. About a minute after you log in, and when you open a window, the addon asks the guild for anything newer than what you have, at most once an hour.
- Anyone online can answer for someone who's offline, so you see the bank even when the bank alt isn't on. Only one copy goes out: whoever starts first, the others stay quiet.
- Sending is paced at about one short message a second (the game's own limit), so it never floods or gets you disconnected. A big recipe list is 5 to 8 messages.
- What you've been sent is kept in your saved file, so the windows work right after login before anyone answers. Crafters not heard from in 60 days are dropped.

## Accents

Talk like your race, for fun. Off until you pick one; it's saved per character. Pick it on the Options tab, or:

- `/accent` turns it on or off, remembering which accent and strength you had (the very first time: your race's). The speech bubble in the window does the same. `/accent status` says what's on and whether this game lets it change chat.
- `/accent troll` (or `orc`, `tauren`, `undead`, `skyborne`), `/accent auto` (your character's race: Troll, Orc, Tauren, Forsaken, Skyborne; Alliance races stay plain), `/accent off`.
- `/accent light` swaps a few words; `/accent thick` swaps more and now and then adds a closing line ("Ya mon!", "Lok'tar!", "Walk with the Earth Mother.").
- It converts what you type in say, yell, guild, officer, party, raid and whispers. `/accent chat <type> on|off` changes the list (e.g. `/accent chat whisper off`). Never channels like Trade.
- `/troll` turns troll on and off; `/troll <message>` sends that one message in troll to the chat you're typing in, whatever your accent is.
- Mail: the send mail window has an Accent button in the corner of the letter. It rewrites the letter (and its subject, lightly) in your accent (or your race's, if you haven't picked one). Press it again within 10 seconds to undo.
- Never changed: item, spell and quest links, coloured text, player names in links, `/commands`, raid icons like `{skull}`, `[anything in brackets]`, `@names`, web addresses and numbers (300g, 3:30, 10x). A message that would go past chat's 255 letters drops its closing line, then goes light, then goes as typed.
- The word lists are tables at the top of `Accent.lua`, easy to edit. Skyborne is new in Forever, so its accent (sky, wind and wings) is a placeholder until the race has a voice of its own.
- If this game version won't let addons change what you type, one line says so; `/troll <message>` and the mail button still work.

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
