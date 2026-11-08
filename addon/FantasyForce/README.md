# FantasyForce

A tiny addon for World of Warcraft: Forever that quietly records your characters and your guild roster so the Fantasy Force website can import them. No UI, no network, no chat spam.

## What it records

Per character on this account: name, level, class, race, faction, spec (the talent tree with the most points) and points per tree, every profession and secondary skill with its skill level, guild and guild rank.

Once a minute at most, when the server sends the guild roster: every member's name, rank, level, class, public note and online status (and days since last online). Officer notes are never read.

## Where the data lives

The game writes it when you log out or `/reload`:

```
World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\FantasyForce.lua
```

Drag that file onto the guild website to import. (The beta client used `_classic_beta_` instead of `_forever_`; if neither exists, use Battle.net's gear icon > Show in Explorer and look for `WTF\Account`.)

## Install

Put the `FantasyForce` folder in `World of Warcraft\_forever_\Interface\AddOns\`, or install from CurseForge.

## Commands

- `/ff` prints how many characters and guild members are recorded and the last update.
- `/ff reset` clears everything recorded.
