# Boaring Adventure

A lightweight WoW 1.12.1 / OctoWoW addon that shows **enemy boar spawn points only** on the world map and minimap using pfQuest data.

Hovering a pin uses pfQuest's normal NPC tooltip information. `pfQuest-turtle` is supported for custom Octo/Turtle boars.

## Requirements

- `pfQuest`
- `pfQuest-turtle` optional, recommended for OctoWoW

## Install

Place the repository folder at:

`World of Warcraft\Interface\AddOns\BoarTracker`

The folder must be named `BoarTracker` so WoW can load `BoarTracker.toc`.

After logging in, `/boar status` should confirm that the addon loaded and indexed boars.

## Commands

- `/boar all` — show all boar spawns
- `/boar <name>` — show matching boars
- `/boar info <name or id>` — show level, NPC ID, zones and spawn count
- `/boar list [text]` — list indexed boars
- `/boar clean` — clear pins
- `/boar filter on|off` — toggle strict boar-only pfQuest map filtering
- `/boar status` — show addon/database status
