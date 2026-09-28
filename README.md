# Completao!!

World of Warcraft addon for the Classic "Forever" beta that shows quests as a
**chain tree**: which quests exist, what each one requires, where it starts, and
which ones you have already done. Pick a dungeon, raid, zone or class on the
left, read the tree on the right, click a quest for the details.

Inspired by BtWQuests.

## What it does

- **Dungeons, Raids, Battlegrounds, Zones, Class Quests, Professions, Races,
  Events and Miscellaneous** sections in a collapsible side panel, each one
  sorted alphabetically (dungeons and raids by level). Each entry lists its
  level range, progress (`done/total`) and a NEW tag for the content Forever
  adds. Everything but dungeons and raids only lists what you can do: entries
  with no quest for your faction and race are hidden. Zone, class, race and
  profession names follow the client's language. Events holds the holiday and
  world events (Lunar Festival, Darkmoon Faire, the Ahn'Qiraj war effort,
  Scourge Invasion...); Miscellaneous the reputation and legendary quests.
- **Only what applies to you**: quests of another class, race or faction are
  hidden, unless you look at that class or race in particular (its own entry in
  the panel). A "Show other faction" checkbox lifts it for the opposite faction.
- **Quest chain tree**: quests laid out left to right by prerequisite, colored
  by state (completed, in progress, available, locked). Long columns are split
  (12 rows at most), so a zone with a hundred loose quests reads as a grid.
  Drag the background to pan and use the wheel to zoom (Shift+wheel scrolls
  sideways, Ctrl+wheel vertically); the zoom is remembered (per character or shared, see Preferences).
- **Search quests...** at the top of the side panel opens a search form in the
  main area, across every section at once, among the quests meant for your
  character: quest title; include low-level, too-high and completed quests
  (off by default); and the reward's item type and subtype as the game names
  them (Weapon > Wands...), or only quests that give an item. Results are a
  table -- title in its state color, level, where it is, money, reward icons
  with their tooltips -- sortable by title, level or money from its header,
  and clicking one opens its tree with the quest selected and centered
  (`Search.lua`). **Quest Log**, right below, shows the quests in your log in
  the same table.
- The window can be made small: filters, the search form and the quest
  panel's buttons wrap onto new rows as it narrows, and the results table
  narrows its columns (`ns.FlowLayout`).
- **Filters** above the tree, remembered like the zoom: a search box by title, and
  three checkboxes -- hide low-level (grey) quests, hide quests that are too
  high (you cannot take them yet, or they are red for your level), hide
  completed quests. "Completed" hides every quest you have done, also the done
  steps of a chain you are still on. By level, chains are shown or hidden
  as a whole, so they are never cut in half: "too high" hides a chain when
  everything it starts with is above your level (if you can start it, all its
  steps stay, even higher ones); "low level" hides a chain only when all its
  quests are grey. A chain you
  have already started, and anything in your quest log, is never hidden by
  level; loose quests are hidden by their own level. What stays visible is
  drawn translucent -- more the quests too high for you, less the low-level
  ones, which stay readable. "Low level" means the title would be grey in your
  quest log, as the game itself decides.
- **Done inside the instance**: quests that take place inside a dungeon or raid
  carry a small doorway icon on the top-left corner of their box (and a line in
  the tooltip and the quest panel), so you can tell them apart from the ones you
  do outside on the way there.
- **Ready to turn in**: a quest in your log with every objective done keeps its
  yellow "in progress" box and gets a green check on the top-right corner.
- **Follow a chain**: click a quest and its whole chain -- everything to do
  before and after it -- lights up in green (thick lines), while every other
  visible quest and connection dims, so a long chain is easy to follow in a
  crowded tree. Close the panel (or click the quest again) to go back.
- **Quest panel** (click a quest): requirements (met ones in green, missing in
  red), objective, who starts / ends it with zone and coordinates, the long
  description, and the **rewards** at the end: items to choose from and items
  you always get (icon, count, name in its quality color, the game's own item
  tooltip on hover, Shift-click to link it), money, experience and reputation. It can be maximized over the whole tree with
  Blizzard's maximize/restore button.
  - The client only gives a quest's text for quests in your log, never by id:
    for those the description is read live, in your client's language; for
    the rest it comes from the addon's data, when it has it. Nothing is saved.
  - **Steps**, right after the objective: the missing requirement (if any),
    the start, one step per objective with the zone where it is done, and
    the turn-in. With the quest in your log each objective shows its live
    progress (`3/8`); done steps are ticked and the next one is highlighted.
    Objective places come from the data (`steps`): for each objective, the
    zone where its targets (or whatever drops the item) are most common and
    the densest spot in it.
  - **Waypoint: <step>** -- a split button: the main part sets a
    [TomTom](https://www.curseforge.com/wow/addons/tomtom) waypoint (or the
    game's own user waypoint) to the step that comes next -- the requirement
    or the start if you haven't taken the quest, the first unfinished
    objective while you are on it, the turn-in once it is complete -- and the
    arrow lists every step to pick another one.
  - **Show on map** -- opens the world map on the chosen step and drops a
    bouncing gold "!" marker on the exact spot. For a step inside an instance
    the button becomes **Show entrance** and points at the instance's door.
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
  its micro button -- and closes with it if it was opened that way), always
  open on the Quest Log (otherwise the window comes back to where you left it:
  the log, the search or an entry's tree), and buttons to reset the window
  position, the zoom and the filters. More will be
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
your log. Key bindings for opening the window and the preferences are under
Options -> Keybindings, in their own Completao!! section (`Bindings.xml`).

## Repo layout

The addon lives at the repo root -- this is what release tooling and CurseForge
expect to package directly as `Completao/` -- organized in folders like
[Questie](https://github.com/Questie/Questie), with a `*.test.lua` next to
every module:

```
Completao.toc  Completao.lua  Bindings.xml     entry point: events, chat, /completao, key bindings
Localization/Locale.lua                         ns.L
Modules/Database/Entries.lua                    sections, entries and their quests, hand fixes
Modules/Quest/QuestState.lua                    status, low/too high, who sees it, titles, description
Modules/Quest/QuestSteps.lua                    steps of a quest and the one that comes next
Modules/Settings/Settings.lua                   per character or shared settings
Modules/Graph/Graph.lua                         tree layout
Modules/Map/Waypoints.lua                       zone -> map, waypoints, map marker
Modules/UI/  Layout Menu MainWindow QuestPanel Search Preferences MinimapButton
Data/          Dungeons.lua  Raids.lua  Battlegrounds.lua  Overrides.lua  Generated/ (tools output)
Icons/
test/          WowApiMock.lua (the game's API, simulated)  Addon.lua (loader)  busted.lua (local runner)
setupTests.lua
tools/         data generators (tools/local/ is git-ignored)
```

- `images/` -- source icon artwork (unprocessed) and the screenshots of the
  CurseForge page (`images/screencaps/`). The addon icon is cut from it into
  `Icons/Completao.png`.
- `.github/workflows/ci.yml` -- tests and luacheck on every push.
  `release.yml` -- manual (`workflow_dispatch` only) release pipeline via
  [BigWigsMods/packager](https://github.com/BigWigsMods/packager), packaging
  the repo root (without the tests) and uploading to CurseForge.
  `sync-media.yml` -- hosts the page screenshots.

## How it works

- Every file gets the addon's namespace (`local ADDON, ns = ...`) and adds its
  functions to it; the TOC loads them in order: localization, the logic
  modules, the data (which registers entries through `Modules/Database`), the
  UI and last `Completao.lua`, which starts everything on `ADDON_LOADED`.
- `Localization/Locale.lua` -- `ns.L`, keyed by the English string;
  `esES`/`esMX` replace the keys they translate, everything else falls back to
  English.
- `Data/Dungeons.lua`, `Data/Raids.lua` -- the list of instances and where their
  doors are. `Data/Generated/` -- quests, entrances and rewards written by the
  tools. `Data/Overrides.lua` -- hand corrections (`ns.PatchQuest`) that no
  generator overwrites.

## Tests

Unit tests use [busted](https://lunarmodules.github.io/busted/), as Questie
does: a `*.test.lua` next to each module, run from the repo root. They load the
addon's own files against a simulated game API (`test/WowApiMock.lua`: frames,
`C_QuestLog`, `C_Map`...), so the UI can be exercised too: open the window, tick
a filter, click a search result.

```
busted -p ".test.lua" .        # CI (Lua 5.1, like the game)
lua test/busted.lua            # locally, without installing busted
lua test/busted.lua Modules/UI/Search.test.lua
```

`test/busted.lua` is a small runner that understands the part of busted the
tests use, for machines where busted can't be installed (on Windows it needs
a C compiler). The CI also runs `luacheck` (`.luacheckrc`).

A quest is `{ id, name, level, minLevel, requires = {ids}, requiresAny = {ids},
faction, giver, start = {npc, area, x, y}, finish = {...}, objective, desc }`.
Completion is always read live from the client (`C_QuestLog`), never stored.

## Data pipeline

Quest data is generated offline, not written by hand. The Forever-only content
is fetched with local helpers that are not part of this repository
(`tools/local/`, git-ignored):

- `node tools/questie_forever.mjs` -- reads the Forever database that ships with
  [Questie](https://github.com/Questie/Questie) (`AddOns/QuestieDB/QuestieDB_Forever.toc`,
  base64 CBOR read by `tools/questie_db.mjs`; set `QUESTIEDB_TOC` if it is not
  in the default path) and writes everything under `Data/Generated/` except the
  rewards and Forever-only quests:
  - `Classic.lua` and `Entrances.lua`: dungeons, raids and battlegrounds. A
    quest belongs to an instance when its zone is the instance, or when an NPC
    that only ever spawns inside it gives, receives or is the target of the
    quest; its prerequisite chain (up to 12 steps back) and continuations
    (3 steps forward) come along.
  - `Zones.lua`, `Classes.lua`, `Professions.lua` and `Races.lua`: one entry per
    zone with a map (starting subzones such as Northshire fold into their
    zone), class, profession (by Questie's category or the skill the quest
    requires) and race. Class quests go into their class, the rest into their
    zone; quests restricted to a few races also appear under each of those
    races. Quests that belong to an instance also show up under its zone.
  - `Extra.lua`: the events and miscellaneous entries, from Questie's other
    quest categories.
- Questie's Forever database already has Questie's own corrections and its map
  points in Forever coordinates, so levels, prerequisites, races, classes and
  positions match what Questie shows; a quest inherits the class or race
  restriction of the prerequisites it requires. Chain steps that share a name
  are numbered ("Unending Torment (2/5)"). Each quest also gets one **step**
  per objective (kill, world object, item from its droppers), with the zone
  where it is most common and the densest spot in it.
- `Data/Generated/Rewards.lua` (`ns.REWARDS`) -- the rewards of every quest in
  the other generated files, written by a local helper from public quest
  databases. Only item ids and counts, money, experience and reputation are
  stored: names, icons and tooltips come from the client.
- **Coordinates.** Everything in `Data/Generated/` is in Forever's map
  coordinates. Forever redrew the maps of Mulgore, Eastern Plaguelands,
  Redridge Mountains and Stormwind City (same world positions, new map
  bounds); Questie's data has them converted, and the local helpers that read
  web pages (which show the old coordinates) apply Questie's per-zone
  transform (`tools/local/era_to_forever.mjs`).
- Fix anything wrong in `Data/Overrides.lua`, never in `Data/Generated/`.

## Installing (development)

Copy or symlink this repo's root as `Completao` into the client's AddOns folder
(the `tools/`, `images/` and `.github/` folders are not needed there):

```
World of Warcraft/_classic_beta_/Interface/AddOns/Completao/
```

## Status

Early (`0.1.0-beta`); see `CHANGELOG.md`.

- Every Classic dungeon, zone, class and profession has generated quests.
  Forever's new quests are in too (`Data/Generated/ForeverNew.lua`, ~700): in
  their Classic zones and classes, and in the new entries Zephras Isle,
  Camping and Crafting. Of Forever's new instances only The Hall of Thanes and
  Ruins of Lordaeron have quests so far; the rest are listed (level range,
  zone of the door) but empty until their quests are published.
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

- **Questie.** The generated quest data (`Classic.lua`, `Zones.lua`,
  `Classes.lua`, `Professions.lua`, `Races.lua`, `Extra.lua` and `Entrances.lua`
  in `Data/Generated/`) derives from the Forever database that ships with
  [Questie](https://github.com/Questie/Questie). Questie declares GPLv3 on its
  CurseForge page (its GitHub repository carries no license file); thanks to
  the Questie team and its contributors.
- **Public quest databases.** The names, text and locations of the quests
  Forever adds, and the rewards of every quest, are compiled from public quest
  databases and are not covered by this license.
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
