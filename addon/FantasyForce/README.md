# FantasyForce

A small addon for World of Warcraft: Forever that quietly records your characters and your guild roster so the Fantasy Force website can import them, and shows the guild bank and your guildmates' crafting in game, anywhere. No chat spam.

## What it records

Per character on this account: name, level, class, race, faction, spec (the talent tree with the most points) and points per tree, every profession and secondary skill with its skill level, guild and guild rank.

Recipes: the game only lists them while a profession window is open, so open each profession once on each character (and again after learning new ones). Only your own: a linked or guild recipe list is never recorded.

Once a minute at most, when the server sends the guild roster: every member's name, rank, level, class, public note and online status (and days since last online). Officer notes are never read.

Guild bank: when you open it (if this game has one), every tab you can view, with its items (stacks of one item combined per tab) and the gold. Forever may have no guild bank, so use a bank alt instead (below).

Bank alt: after `/ff bankalt` on a character, its bags are recorded on login and when they change (at most every 10 seconds), and its bank each time you open it. Mail it your guild's spare gear and the site shows the bank.

Raids: while you are in a raid group inside a raid instance, one record per raid per day: everyone seen in the raid (checked on entering, on every boss kill and every 10 minutes), each boss kill with who was there, and the loot. Loot is only epic (purple) or better by default; `/ff loot rare` also records rares, `/ff loot epic` goes back. Only the last 60 raids are kept.

## In-game windows

Both open anywhere, move by dragging (they remember where you put them) and close with Escape or by typing the command again.

- `/ff bank`: the guild bank. One row per item with its icon, name, count and the tab it's in; a search box and a button per tab; the gold and when the bank alt last updated it at the bottom. Hover a row for the item's tooltip; shift-click links it in chat. If you're on the bank alt's account it shows your own record, otherwise the newest one shared by the guild. Nothing yet? The bank alt types `/ff bankalt` and logs in with the addon on.
- `/ff crafts`: who in the guild can make what. A button per profession (All, Alchemy, Blacksmithing, ...), a search box over recipe names, and one row per recipe with who can make it, online people first (with the green dot). Someone offline whose alt is online shows as "Name (Alt)", and whispering goes to the alt. Hover a row for the item's tooltip plus every crafter and their skill; click a name to whisper them, click the row to whisper the first one online, shift-click to link the item. Your own characters are in it too.

## Sharing with the guild

The windows show what guildmates' addons share over the guild's hidden addon channel (guild only: never whispers, never other channels, never other guilds). You see someone's crafting only if both of you run the addon.

- Each player's addon shares its own account's characters that are in this guild: their professions with skill, and their recipes (as spell and item ids). A character in another guild is never shared.
- The bank alt's addon shares the bank: tab names, each item and count, the gold, and when it was recorded.
- When: shortly after you log in (a random 5 to 20 seconds, only what changed since it last went out), 10 seconds after something changes (a profession window opened, the bank alt's bags or bank changed), and when someone asks. Opening a window asks the guild for anything newer than what you have, at most once an hour.
- Anyone online can answer for someone who's offline, so you see the bank even when the bank alt isn't on. Only one copy goes out: whoever starts first, the others stay quiet.
- Sending is paced at about one short message a second (the game's own limit), so it never floods or gets you disconnected. A big recipe list is 5 to 8 messages.
- What you've been sent is kept in your saved file, so the windows work right after login before anyone answers. Crafters not heard from in 60 days are dropped.

## Where the data lives

The game writes it when you log out or `/reload`:

```
World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\FantasyForce.lua
```

Drag that file onto the guild website to import. (The beta client used `_classic_beta_` instead of `_forever_`; if neither exists, use Battle.net's gear icon > Show in Explorer and look for `WTF\Account`.)

## Install

Put the `FantasyForce` folder in `World of Warcraft\_forever_\Interface\AddOns\`, or install from CurseForge.

## Commands

- `/ff` prints how many characters, guild members and raids are recorded, how many guildmates' crafters were shared, the last update, and whether this character is a bank alt.
- `/ff bank` opens the guild bank window; `/ff crafts` opens the guild crafting window.
- `/ff bankalt` makes this character the guild's bank alt (or turns it off again).
- `/ff loot rare` records rare (blue) raid loot too; `/ff loot epic` returns to epic only.
- `/ff reset` clears everything recorded, and what guildmates shared.
