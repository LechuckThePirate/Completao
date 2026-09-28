# Completao!!

World of Warcraft addon for the Classic "Forever" beta that shows quests as a
**chain tree**: which quests exist, what each one requires, where it starts, and
which ones you have already done. Pick a dungeon, raid, zone or class on the
left, read the tree on the right, click a quest for the details.

Inspired by BtWQuests.

## What it does

- **Dungeons, Raids, Zones, Class Quests and Races** sections in a collapsible
  side panel, each one sorted alphabetically. Each entry lists its level range,
  progress (`done/total`) and a NEW tag for the content Forever adds. Zones and
  classes only list what you can do: entries with no quest for your faction and
  race are hidden. Zone, class and race names follow the client's language.
- **Only what applies to you**: quests of another class, race or faction are
  hidden, unless you look at that class or race in particular (its own entry in
  the panel). A "Show other faction" checkbox lifts it for the opposite faction.
- **Quest chain tree**: quests laid out left to right by prerequisite, colored
  by state (completed, in progress, available, locked). Long columns are split
  (12 rows at most), so a zone with a hundred loose quests reads as a grid.
  Drag the background to pan and use the wheel to zoom (Shift+wheel scrolls
  sideways, Ctrl+wheel vertically); the zoom is remembered (per character or shared, see Preferences).
- **Filters** above the tree, remembered like the zoom: a search box by title, and
  three checkboxes -- hide low-level (grey) quests, hide quests that require a
  higher level than yours, hide completed chains. Chains are shown or hidden
  as a whole, so they are never cut in half: "too high" hides a chain when
  everything it starts with is above your level (if you can start it, all its
  steps stay, even higher ones); "low level" hides a chain only when all its
  quests are grey; "completed" hides chains with every quest done. A chain you
  have already started, and anything in your quest log, is never hidden by
  level; loose quests are hidden by their own level. What stays visible is
  drawn translucent -- more the quests too high for you, less the low-level
  ones, which stay readable. "Low level" means the title would be grey in your
  quest log, as the game itself decides.
- **Done inside the instance**: quests that take place inside a dungeon or raid
  carry a small doorway icon on the top-left corner of their box (and a line in
  the tooltip and the quest panel), so you can tell them apart from the ones you
  do outside on the way there.
- **Follow a chain**: click a quest and its whole chain -- everything to do
  before and after it -- lights up in green (thick lines), while every other
  visible quest and connection dims, so a long chain is easy to follow in a
  crowded tree. Close the panel (or click the quest again) to go back.
- **Quest panel** (click a quest): requirements (met ones in green, missing in
  red), objective, who starts / ends it with zone and coordinates, and the long
  description at the end. It can be maximized over the whole tree with
  Blizzard's maximize/restore button.
  - The client only gives a quest's text for quests in your log, never by id:
    for those the description is read live, in your client's language; for
    the rest it comes from the addon's data, when it has it. Nothing is saved.
  - **Waypoint: start / turn-in** -- sets a [TomTom](https://www.curseforge.com/wow/addons/tomtom)
    waypoint, or the game's own user waypoint if TomTom is not installed.
  - **Show on map** -- opens the world map on the quest giver and drops a
    bouncing gold "!" marker on the exact spot. When the quest has no known
    starting point (it starts inside the instance) the button becomes **Show
    entrance** and points at the instance's door.
  - **Open quest** -- for quests in your log, opens the quest log on that quest.
- Resizable, movable window; its position, size, open section and selected
  dungeon are saved (the position and size per character or shared, see
  Preferences; the open section and dungeon always per character).
- Minimap button (click to open, drag to move) and an icon in the AddOns list.
- **Fades while you move**, like the world map: the window drops to 50 %
  opacity while the character is walking or running, so it never hides what is
  ahead, and comes back when you stop or while the cursor is over it.
  `/completao fade <10-100>` sets the opacity (100 = no fade), saved per
  character.
- **Preferences**: a gear next to the window's close button (or `/completao
  prefs`) opens a small window, as in Embolsao, with the basics: opacity while
  moving, show the minimap button, show the chat messages at startup, open
  with the quest log (the window opens when you open the quest log -- `L` or
  its micro button -- and closes with it if it was opened that way), and
  buttons to reset the window position, the zoom and the filters. More will be
  added. A **Character specific preferences** checkbox, as in Embolsao, decides
  where these settings -- and the filters, zoom and window position and size --
  are kept: for this character only (the default) or shared by all your
  characters (`CompletaoDB.shared`). Switching to per character starts from a
  copy of the shared ones; switching back leaves the character's copy saved,
  unused. The selected entry and open section always stay per character.
- Dungeons and raids are sorted by level, the other sections alphabetically.
- Two chat lines, like Embolsao: `Completao!! vX -- initializing...` when the
  addon loads and `... initialization complete (N quests)` once you are in the
  world with everything indexed.
- English and Spanish UI (`esES`/`esMX` clients get Spanish).

Commands: `/completao` (or `/cpl`) toggles the window, `/completao minimap`
shows or hides the minimap button, `/completao dump` lists the quest ids in
your log.

## Repo layout

The addon files live at the repo root (`Completao.toc`, `Core.lua`, `UI.lua`,
`Data/`, `Icons/`, `.pkgmeta`) -- this is what release tooling and CurseForge
expect to package directly as `Completao/`.

- `tools/` -- the data generators (see below). `tools/local/` is git-ignored.
- `images/` -- source icon artwork (unprocessed) and the screenshots of the
  CurseForge page (`images/screencaps/`). The addon icon is cut from it into
  `Icons/Completao.png`.
- `.github/workflows/release.yml` -- manual (`workflow_dispatch` only) release
  pipeline via [BigWigsMods/packager](https://github.com/BigWigsMods/packager),
  packaging the repo root and uploading to CurseForge.
  `.github/workflows/sync-media.yml` -- hosts the page screenshots.

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
- `lua tools/questie_classic.lua zones` -- writes `Data/Generated/Zones.lua`,
  `Classes.lua` and `Races.lua`: one entry per zone with a map (Classic zones and
  cities; starting subzones such as Northshire fold into their zone), one per
  class and one per race. Class quests (by Questie's class category or class
  mask) go into their class, the rest into their zone; quests restricted to a
  few races also appear under each of those races. Quests that belong to a
  dungeon also show up under its zone when Questie files them there.
- The generators apply Questie's own corrections (`Database/Corrections`,
  executed outside the game) on top of its base database, so levels,
  prerequisites, races and classes match what Questie shows. A quest inherits
  the class or race restriction of the prerequisites it requires (`tools/questie_fixes.lua`).
- Chain steps that share a name are numbered ("Unending Torment (2/5)").
- Fix anything wrong in `Data/Overrides.lua`, never in `Data/Generated/`.

## Installing (development)

Copy or symlink this repo's root as `Completao` into the client's AddOns folder
(the `tools/`, `images/` and `.github/` folders are not needed there):

```
World of Warcraft/_classic_beta_/Interface/AddOns/Completao/
```

## Status

Early (`0.1.0-beta`); see `CHANGELOG.md`.

- Every Classic zone and class has generated quests too (Forever's own zones
  and class quests are not covered yet). Every Classic dungeon has generated
  quests. Of Forever's new instances only
  The Hall of Thanes and Ruins of Lordaeron have quests so far; the rest are
  listed (level range, zone of the door) but empty until their quests are
  published.
- Quest text shipped with the addon is English only, and only Forever's quests
  have a long description in it; titles are read from the client, so they
  follow its language, and so does the description of the quests in your log.
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
