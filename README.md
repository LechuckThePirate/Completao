# Completao!!

World of Warcraft addon for the Classic "Forever" beta that shows the quests
of every dungeon and raid as a **chain tree**: which quests exist, what each
one requires, where it starts, and which ones you have already done. Pick a
dungeon or raid on the left, read the tree on the right, click a quest for the
details.

Inspired by BtWQuests.

## What it does

- **Dungeons and Raids** sections in a collapsible side panel (more sections --
  zones, class quests -- slot in later). Each entry lists its level range,
  progress (`done/total`) and a NEW tag for the content Forever adds.
- **Quest chain tree**: quests laid out left to right by prerequisite, colored
  by state (completed, in progress, available, locked). Only your faction's
  quests are shown. Drag the background to pan, wheel to scroll (Shift+wheel
  sideways).
- **Quest panel** (click a quest): requirements (met ones in green, missing in
  red), objective, description, and who starts / ends it with zone and
  coordinates. It can be maximized over the whole tree with Blizzard's
  maximize/restore button.
  - **Waypoint: start / turn-in** -- sets a [TomTom](https://www.curseforge.com/wow/addons/tomtom)
    waypoint, or the game's own user waypoint if TomTom is not installed.
  - **Show on map** -- opens the world map on the quest giver and drops a
    bouncing gold "!" marker on the exact spot. When the quest has no known
    starting point (it starts inside the instance) the button becomes **Show
    entrance** and points at the instance's door.
  - **Open quest** -- for quests in your log, opens the quest log on that quest.
- Resizable, movable window; its position, size, open section and selected
  dungeon are saved per character.
- Minimap button (click to open, drag to move) and an icon in the AddOns list.
- English and Spanish UI (`esES`/`esMX` clients get Spanish).

Commands: `/completao` (or `/cpl`) toggles the window, `/completao minimap`
shows or hides the minimap button, `/completao dump` lists the quest ids in
your log.

## Repo layout

- `Completao!!/` -- the addon itself. The folder is named exactly like the
  addon (`Completao!!`), so it can be copied as is into `AddOns`.
- `tools/` -- the data generators (see below). `tools/cache/` holds downloaded
  pages and is git-ignored.
- `images/` -- source icon artwork (unprocessed). The addon icon is cut from it
  into `Completao!!/Icons/Completao.png`.

## How it works

- `Locale.lua` -- `ns.L`, keyed by the English string; `esES`/`esMX` replace
  the keys they translate, everything else falls back to English.
- `Core.lua` -- entries (a dungeon or raid), categories, quest status
  (`done` / `active` / `available` / `locked` with the reasons), slash
  commands and per-character saved variables (`CompletaoCharDB`).
- `Data/Dungeons.lua`, `Data/Raids.lua` -- the list of instances and where their
  doors are. `Data/Generated/` -- quests and entrances written by the tools.
  `Data/Overrides.lua` -- hand corrections (`ns.PatchQuest`) that no generator
  overwrites.
- `Graph.lua` -- lays a quest list out in columns by prerequisite depth.
- `Waypoints.lua` -- converts an area id to the client's map by zone name,
  sets waypoints, opens the world map and draws the map marker.
- `Detail.lua` -- the quest panel; `UI.lua` -- the window, list and tree;
  `Minimap.lua` -- the minimap button.

A quest is `{ id, name, level, minLevel, requires = {ids}, requiresAny = {ids},
faction, giver, start = {npc, area, x, y}, finish = {...}, objective, desc }`.
Completion is always read live from the client (`C_QuestLog`), never stored.

## Data pipeline

Quest data is generated offline, not written by hand. The Forever-only content
is fetched with a local helper that is not part of this repository
(`tools/local/`, git-ignored):

- `lua tools/questie_classic.lua [entry ids]` -- reads the Classic database that
  ships with [Questie](https://github.com/Questie/Questie) (Lua 5.4; point
  `QUESTIE_DIR` at the Questie folder if it is not in the default path) and
  writes `Data/Generated/Classic.lua` and `Entrances.lua`. A quest belongs to an
  instance when its zone is the instance, or when an NPC that only ever spawns
  inside it gives, receives or is the target of the quest; its prerequisite
  chain (up to 12 steps back) and continuations (3 steps forward) come along.
- Chain steps that share a name are numbered ("Unending Torment (2/5)").
- Fix anything wrong in `Data/Overrides.lua`, never in `Data/Generated/`.

## Installing (development)

Copy `Completao!!` into the client's AddOns folder:

```
World of Warcraft/_classic_beta_/Interface/AddOns/Completao!!/
```

## Status

Early (`0.1.0-beta`); see `CHANGELOG.md`.

- Every Classic dungeon has generated quests. Of Forever's new instances only
  The Hall of Thanes and Ruins of Lordaeron have quests so far; the rest are
  listed (level range, zone of the door) but empty until their quests are
  published.
- Quest text is English only; titles are read from the client, so they follow
  its language.
- Several integration points could not be checked against the client's own UI
  source and fall back gracefully when missing: Blizzard's maximize/restore
  widget, opening the quest log on a quest, and the map marker.

## License

Copyright (C) 2026 LechuckThePirate.

Completao!! is free software: you can redistribute it and/or modify it under the
terms of the [GNU General Public License v3.0](LICENSE) as published by the Free
Software Foundation. It is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.

### Credits and what the GPL does not cover

- **Questie.** The generated Classic data (`Data/Generated/Classic.lua` and
  `Entrances.lua`) derives from the database that ships with
  [Questie](https://github.com/Questie/Questie). Questie declares GPLv3 on its
  CurseForge page (its GitHub repository carries no license file); thanks to
  the Questie team and its contributors.
- **Public quest databases.** The names, text and locations of the quests
  Forever adds are compiled from public quest databases and are not covered by
  this license.
- **Blizzard Entertainment.** The quests, their names and text, and every game
  asset are Blizzard's. At runtime the addon uses textures and widgets the game
  client already ships (quest icon, frame and button templates, maximize/restore
  widget); none are included in this repository.
- **Artwork.** The addon icon (`Icons/Completao.png`) is cut from AI-generated
  artwork (`images/`); the map glow (`Icons/Glow.png`) was generated for this
  addon.
- **TomTom** is an optional, separate addon that Completao!! only talks to.

World of Warcraft is a trademark of Blizzard Entertainment, Inc. Completao!! is
not affiliated with or endorsed by Blizzard Entertainment, Questie or TomTom.
