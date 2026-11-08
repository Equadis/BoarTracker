# BoarTracker

Standalone boar spawn tracker for **WoW 1.12.1 / OctoWoW**. No pfQuest required.

- Shows individual boar spawn points on **zone maps only** and on the **minimap**, using compact circular portraits keyed by NPC ID. Goldbristle Boars use their own golden unit-frame portrait; unconfigured NPCs currently fall back to the existing Stonehide portrait.
- Hover a marker for **name, level, NPC ID, respawn time and coordinates**.
- Boar names in tooltips are colour-coded by difficulty relative to your level (grey, green, yellow, orange, red and dark red/skull); ranged mobs use their upper level for a safer indicator.
- Saves boar kills by name per character and posts a chat message every 50 total kills.
- Includes vanilla and Octo/Turtle boars, including Forest Boars and Elder Forest Boars.
- Estimates boars remaining, XP per hour and time to level from actual XP earned from boar kills (including modified XP rates).

## Preview of v0.3.3

![BoarTracker preview showing the spawn map, levelling tracker and kill counter](docs/BoarTracker-Preview.png)

## Portrait mapping and candidate renderer

All 48 boar NPC IDs are mapped to 23 creature display IDs in `BoarPortraitDisplays.lua`, with provenance in `tools/boar-display-ids.json`. Both maps select by display ID; the 389 (Stonehide/Rockhide/Forest) and 20504 (Goldbristle/Thalassian/Hightusk) portraits use actual captured game unit frames. The existing brown Stonehide portrait remains the fallback for all other displays until reviewed.

To generate **candidate** textures for the other 21 display models:

```sh
python -m pip install Pillow requests
python tools/build_boar_portraits.py
```

This fetches full-body model thumbnails using the same sources as the Tortoise DB Viewer, crops head-biased candidates as power-of-two TGA textures and outputs `tools/portrait-candidates/ContactSheet.png` for review. It does **not** produce guaranteed pixel-perfect unit-frame framing: true head portraits require rendering with the 1.12 client camera, or capturing the game's own target portraits. Review each result first, then copy selected `Portrait_ID.tga` into `Textures` and add the display ID to `BoarTrackerPortraitTextures`. New candidate textures are deliberately not auto-enabled.

Two less-accessible NPC pages (708 and 1984) are marked as secondary-source IDs in the manifest and should be checked in the live client.

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

The on-screen tracker reports estimated boars remaining, boar XP/hour and estimated time to level. It samples up to 20 recent XP-awarding boars per character. XP/hour uses boar XP after the first qualifying kill of the current session and includes time between subsequent kills; that session rate resets on reload, relog, or after five minutes out of combat. After an idle reset, the next XP-awarding boar starts a fresh measurement. Shorter breaks still count; kill totals and recent XP-per-boar samples are preserved. The average is based on XP **actually earned**, so half-XP and other XP modifiers are accounted for.

Spawn data is derived from pfQuest/pfQuest-turtle database data under its MIT licence; the addon has no runtime dependency on pfQuest.

## Changelog

### v0.3.11
- Add NPC-to-CreatureDisplayID mapping for 48 boars (23 unique display models), with source links in `tools/boar-display-ids.json`.
- Share the existing genuine game-unit portraits across every NPC using display 389 (grey/brown) or 20504 (golden), including all Goldbristle variants.
- Include a candidate portrait exporter (`tools/build_boar_portraits.py`) that uses Tortoise DB Viewer model thumbnails, Wowhead Classic and OctoWoW model images, plus a contact sheet for visual review.
- Do not automatically ship full-body thumbnail crops as authentic unit-frame head portraits. Other display variants retain the existing fallback until individually approved.

### v0.3.10
- Add the authentic golden Goldbristle Boar unit-frame portrait for NPC 62121, cropped from an in-game screenshot (16×16 TGA).
- Select a portrait per NPC ID on both maps, correctly refreshing pooled pins when the NPC type changes.
- Keep the existing Stonehide portrait as a fallback for types without individual assets; no changes to spawn coordinates, marker sizes, or draw order.

### v0.3.9
- Place world-map boar spawn markers below the player arrow, matching the minimap.
- Restore the 1.12 world-map player arrow's top drawing priority by adjusting its actual 3D model, not the WorldMapPlayer mouseover frame.
- Keep all nearby boar markers visible and unchanged in position.

### v0.3.8
- Remove the proximity exclusion that hid boar spawn pins within 18 pixels of the player.
- Lower minimap boar pin frame levels to the bottom child level, below the higher-priority player marker, without changing their positions or visibility.
- Keep the new boar portrait textures and tooltip difficulty colours.

### v0.3.7
- Replace every world-map and minimap spawn icon with a small, circular Stonehide Boar portrait, cropped from an in-game portrait image.
- Bundle the portrait as a 16×16, 32-bit TGA texture compatible with WoW 1.12.1; existing marker positions and sizes are unchanged.

### v0.3.6
- Colour world-map and minimap tooltip names using classic mob difficulty thresholds relative to your character level, including dark red for skull-level mobs.
- For level ranges, use the highest listed mob level to show the toughest possible difficulty.

### v0.3.5
- Earlier workaround for the minimap player arrow (nearby pins were hidden). Reverted in v0.3.8.

### v0.3.4
- Reset XP/hour and time-to-level after five minutes out of combat, including when the tracker is hidden.
- Start a fresh measurement on the next XP-awarding boar while preserving kill totals and XP-per-boar samples.

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
<!-- EqUpdater update icon test -->
