# Changelog

## Unreleased

- New: French (`frFR`), German (`deDE`), Italian (`itIT`) and Brazilian
  Portuguese (`ptBR`) interface. The addon description is translated too.
- New: the names of dungeons and raids follow the client's language (the game's own
  names; a few that the game names differently are translated by the addon).

## 0.5.0-beta

- New: with Autofocus on, a quest you just accepted that is a direct turn-in
  (ready the moment you take it) takes the focus from a quest still in
  progress when its turn-in is nearer than what that quest needs next.
- Fix: the Preferences texts wrap inside the window instead of running out of it.
- New: a right click on the focus window (or on one of its objectives) moves
  the focus to the nearest other tracked quest, by what each needs next, with
  the waypoint. Autofocus leaves a quest chosen that way alone.
- New: **Hide empty or completed categories** (Preferences,
  off by default): the side panel leaves out the zones, dungeons and other
  entries where everything is done or nothing is available to you now (not
  done, your level, requirements met), and the categories left with none. The
  counts next to each category follow. The entry you are looking at stays
  until you leave it. What doesn't count as something to do:
  - holiday quests outside the events section: the ones also listed there (the
    Lunar Festival elders, level 60 but open from level 1, filed under their
    dungeons) and other event ones (Darkmoon Faire, the Gurubashi arena, the
    Ahn'Qiraj war effort, Commendation Signets, some of Forever's new seasonal
    quests);
  - the quests of a dungeon, raid or battleground when you are more than 10
    levels under its minimum (e.g. Alterac Valley's "Launch the Attack!");
  - a profession's quests (Fishing, Alchemy...) without that profession; the
    crafting writs need any crafting one;
  - the class and race entries that aren't yours (the panel lists them all to
    look at, but only your class and race have anything to do; with "Show
    other faction", the other faction's races too).

## 0.4.0-beta

- New: **focus window** -- right-click a quest in Tracked Quests (or press
  **Focus** in its details) to get a small floating window with its status
  icon, title and objectives with live progress ("Boars 0/5"); done objectives
  go grey and struck through, and once all are done they are replaced by
  "Turn in <quest> (<npc>)". The waypoint goes on the nearest objective left
  and follows you through the quest; when the quest is turned in or abandoned
  the window stays, saying no quest is focused and to click to choose
  another (its X closes it). It has a "Focused Quest" title bar, can be moved
  (the place is saved; reset with the other window positions) unless locked
  with the padlock at its top left, and clicking an objective sets the
  waypoint on it, while a click on the rest of it opens the main window on
  Tracked Quests. In combat it lets every click through.
- Fix: with a quest's details open under Search, Quest Log or Tracked Quests,
  the quest tree no longer shows through the table.
- New: **Autofocus tracked quests** (Preferences, off by default): the focus
  window picks its quest by itself, by how near each tracked quest's next step
  is (its nearest objective left, or its turn-in once ready):
  - with nothing focused (at login, after a turn-in or an abandon, or when a
    quest is accepted), the quest with the nearest objective; if no quest has an
    objective to do, the nearest turn-in;
  - with the focused quest ready to turn in, the tracked quest with the
    nearest objective or turn-in (its own included);
  - a quest still in progress keeps the focus, whatever you accept or however
    near the others are; one you focused by hand while already ready stays too.
  Quests whose distance can't be told (no known spot) are left out, and if none
  is left the window says "No quest focused" for you to click and choose.
  Closing the window or unfocusing by hand pauses it until you focus a quest.
- Fix: "hide too high" only hides quests you can't take yet (their minimum
  level is above yours). Quests with a high level but a low minimum, like a
  level 60 one you can pick up at level 10, are no longer hidden, nor drawn
  translucent in the tree.
- Fix: scroll bars (side panel, tree, tables, quest details, what's new) are
  hidden when there is nothing to scroll, instead of sitting there greyed out.
  When the side panel's list fits (for instance collapsed to its icons), the
  room its bar used goes to the main area, so the views sit closer to the
  buttons.
- Fix: on a flight path the main window no longer turns translucent or
  click-through "while moving": it stays as it is, to read on the trip.
- Change: with TomTom, a new waypoint replaces the one the addon set before
  instead of piling up.

## 0.3.0-beta

- New: **Tracked Quests** view under Quest Log, with the quests in your
  objective tracker; under each one its objectives with live progress (done
  ones checked, the next one in gold, only the turn-in once it is ready).
  Click an objective to set the waypoint on it -- the one in use is marked
  until the waypoint changes.
- New: clicking a quest in Search, Quest Log or Tracked Quests opens its
  details below the table, with a **View chain** button (for quests that are
  part of a chain) that takes you to its tree.
- New: a **Distance** column with the live distance to each quest's next
  step (meters, or yards in US/UK English clients); sort by it and the table
  re-sorts as you move.
- New: quest titles carry a `[level]` prefix, with `D` for dungeon quests and
  `+` for elite ones, and a status icon (ready / in progress) in the quest log
  and tracked views.
- New: **Sync with Blizzard Quest Log** -- besides opening and closing with
  the log, selecting a quest in it opens that quest (and its chain).
- New: click-through in combat and/or while moving (separate settings), and a
  separate window opacity in combat.
- New: the table's sort order is remembered, and going to Search, Quest Log
  or Tracked Quests collapses the sections.
- Fix: the game's quest log selection no longer loops back into the window.

## 0.2.0-beta

- New: **Battlegrounds**, **Events** and **Miscellaneous** sections, and quests
  for the raids; the generator moved to Forever's own quest database, so many
  quests that were missing before (or filed under the wrong dungeon) are now in.
- New: **Zones**, **Class Quests**, **Professions** and **Races** sections, so
  every quest that isn't tied to a dungeon or raid has a home too.
- New: quest steps -- each objective gets its own waypoint, with a dropdown to
  pick which one, and live progress next to it; **Show on map** and the
  waypoint buttons follow whichever step is selected.
- New: a check mark on quests that are ready to turn in, both in the tree and
  the quest log table.
- New: a dungeon-door badge on quests done inside an instance, and a dragon
  head badge on elite quests (recommended with a group), on the tree and in
  the quest panel and tooltip.
- New: the quest panel shows the recommended level next to the required one,
  and both are colored the way the game colors that level for your character.
- New: quest rewards (items, money, reputation) in the quest panel, and a long
  description at the end, read live from the quest log.
- New: global quest search and a Quest Log view, as a sortable table (name,
  level, zone, money) with a money column and an items-only filter; the whole
  window layout is responsive to its size.
- New: tree filters -- title search, and hiding low level, too high or
  completed chains; the chain of the selected quest is highlighted, the rest
  dimmed.
- New: a Preferences window: per-character or shared settings, opening the
  window together with the quest log, always opening on the quest log (or
  remembering where you left it), and key bindings.
- New: the window and its trees redraw as you level up, accept, abandon or
  turn in a quest, so they never go stale.
- Fix: quests only ever done inside a dungeon aren't marked as such if the
  particular quest never sends you in; "too high" also catches quests the
  game itself would show in red; several map coordinates fixed, including a
  wrong pond for "Altered Beings".

## 0.1.0-beta

First version.

- New: the window uses the same portrait frame as Embolsao, with the addon's
  icon, and its title shows the version.

- New: a window (`/completao`, `/cpl` or the minimap button) with a
  collapsible **Dungeons** and **Raids** side panel. Every entry shows its level
  range, how many of its quests you have done, and a NEW tag for what Forever
  adds.
- New: each dungeon or raid draws its quests as a chain tree, left to right by
  prerequisite. Colors show completed, in progress, available and locked
  quests, and only your faction's quests appear. Drag the background to pan.
- New: click a quest for its panel: requirements (met in green, missing in red),
  objective, description, and who starts and ends it with zone and coordinates.
  The panel can be maximized over the whole tree.
- New: **Waypoint: start / turn-in** buttons set a TomTom waypoint (or the game's
  own waypoint without TomTom).
- New: **Show on map** opens the world map on the quest giver and marks the spot
  with a bouncing gold "!". If nobody is known to hand the quest out -- it
  starts inside the instance -- it becomes **Show entrance** and points at the
  door of the dungeon.
- New: **Open quest** opens the quest log on a quest you have accepted.
- New: the window can be moved and resized; its position, size, open section
  and selected dungeon are remembered per character.
- New: minimap button (click to open, drag to move; `/completao minimap` hides
  it) and an icon in the AddOns list.
- New: English and Spanish (`esES`/`esMX`) interface.
- Data: every Classic dungeon has its quests, generated from Questie's
  database; of Forever's new instances The Hall of Thanes and Ruins of
  Lordaeron have theirs, from public quest databases. The other new dungeons and
  the new raids are empty until their quests are published.
