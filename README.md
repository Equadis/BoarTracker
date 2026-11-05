# BoarTracker

Standalone boar spawn tracker for **WoW 1.12.1 / OctoWoW**. No pfQuest required.

- Shows individual boar spawn points on **zone maps only** and on the **minimap**.
- Hover a marker for **name, level, NPC ID, respawn time and coordinates**.
- Saves boar kills by name per character and posts a chat message every 50 total kills.
- Includes vanilla and Octo/Turtle boars, including Forest Boars and Elder Forest Boars.
- Estimates boars remaining, XP per hour and time to level from actual XP earned from boar kills (including modified XP rates).

## Preview of v0.3.3

![BoarTracker preview showing the spawn map, levelling tracker and kill counter](docs/BoarTracker-Preview.png)

## Install

Place the repository folder at:

`World of Warcraft\Interface\AddOns\BoarTracker`

## Commands

- `/bt` or `/boartracker` — show status and command help.
- `/bt map` — toggle zone-map pins.
- `/bt mini` or `/bt minimap` — toggle minimap pins.
- `/bt on` / `/bt off` — enable or disable both pin layers (does not toggle the XP tracker).
- `/bt killed` — show kills of your current boar target, or your total kills if you have no target.
- `/bt killed Elder Forest Boar` — show kills of that boar type (case insensitive).
- `/bt xp` — show current XP to next level, recent average XP per XP-awarding boar, and estimated boars remaining.
- `/bt tracker on` / `/bt tracker off` — show or hide the on-screen levelling tracker. Hold **Shift** and drag to reposition it; visibility and position are saved.

The on-screen tracker reports estimated boars remaining, boar XP/hour and estimated time to level. It samples up to 20 recent XP-awarding boars per character. XP/hour uses boar XP after the first qualifying kill of the current session and includes time between subsequent kills; that session rate resets on reload or relog. The average is based on XP **actually earned**, so half-XP and other XP modifiers are accounted for.

Spawn data is derived from pfQuest/pfQuest-turtle database data under its MIT licence; the addon has no runtime dependency on pfQuest.

## Changelog

### v0.3.3
- Added boar XP per hour and estimated time to level to the on-screen tracker.

### v0.3.2
- Added the toggleable, Shift-draggable levelling tracker with saved position and visibility.

### v0.3.1
- Added estimated boars to next level using up to 20 recent XP-awarding boars, saved per character.

### v0.3.0
- Added per-character boar kill counts from the Vanilla combat log, including kills with no XP when credited by the client.
- Cached the minimap zoom probe and skipped pin layout when position and scale are unchanged.

### v0.2.1
- Fixed boar icons appearing on Azeroth/continent maps. Map pins render only on individual zone maps.
