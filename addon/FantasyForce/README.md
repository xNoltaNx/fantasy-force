# FantasyForce

A tiny addon for World of Warcraft: Forever that quietly records your characters and your guild roster so the Fantasy Force website can import them. No UI, no network, no chat spam.

## What it records

Per character on this account: name, level, class, race, faction, spec (the talent tree with the most points) and points per tree, every profession and secondary skill with its skill level, guild and guild rank.

Recipes: the game only lists them while a profession window is open, so open each profession once on each character (and again after learning new ones). Only your own: a linked or guild recipe list is never recorded.

Once a minute at most, when the server sends the guild roster: every member's name, rank, level, class, public note and online status (and days since last online). Officer notes are never read.

Guild bank: when you open it (if this game has one), every tab you can view, with its items (stacks of one item combined per tab) and the gold. Forever may have no guild bank, so use a bank alt instead (below).

Bank alt: after `/ff bankalt` on a character, its bags are recorded on login and when they change (at most every 10 seconds), and its bank each time you open it. Mail it your guild's spare gear and the site shows the bank.

Raids: while you are in a raid group inside a raid instance, one record per raid per day: everyone seen in the raid (checked on entering, on every boss kill and every 10 minutes), each boss kill with who was there, and the loot. Loot is only epic (purple) or better by default; `/ff loot rare` also records rares, `/ff loot epic` goes back. Only the last 60 raids are kept.

## Where the data lives

The game writes it when you log out or `/reload`:

```
World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\FantasyForce.lua
```

Drag that file onto the guild website to import. (The beta client used `_classic_beta_` instead of `_forever_`; if neither exists, use Battle.net's gear icon > Show in Explorer and look for `WTF\Account`.)

## Install

Put the `FantasyForce` folder in `World of Warcraft\_forever_\Interface\AddOns\`, or install from CurseForge.

## Commands

- `/ff` prints how many characters, guild members and raids are recorded, the last update, and whether this character is a bank alt.
- `/ff bankalt` makes this character the guild's bank alt (or turns it off again).
- `/ff loot rare` records rare (blue) raid loot too; `/ff loot epic` returns to epic only.
- `/ff reset` clears everything recorded.
