# Completao!!

**Every quest, in order.** Completao!! lays out the quests of WoW Forever as
chain trees: what each quest needs before you can take it, where it starts, what
it asks of you, and which ones you have already done. Pick a section on the
left, read the tree on the right, click a quest for everything about it -- and
let the addon walk you to the person who hands it out.

Dungeons and raids are in from day one, with more sections on the way (class
quests, zones and beyond). Currently in **beta**.

![Main window](https://media.joanvilarino.online/completao/images/screencaps/main_window.png)

---

## Features

### Quest chain trees
Each entry -- a dungeon, a raid -- draws its quests left to right, by
prerequisite, so a long chain reads like a story instead of a list. Quests are
colored by state: **completed**, **in progress**, **available** and **locked**,
and the lines between them turn green as you move down a chain. Only the quests
of your own faction are shown. Drag the background to pan the tree, scroll the
wheel to move (Shift + wheel to go sideways).

### A side panel that grows with the addon
Sections are collapsible: open **Dungeons** or **Raids** and pick an entry.
Each one lists its level range, your progress (`done/total`), and a **NEW** tag
on what Forever adds on top of Classic. More sections -- class quests, zones and
others -- slot into the same panel as they are added.

### Everything about a quest, one click away
Click any quest in the tree to open its panel:

- **Requirements** -- prerequisite quests and level, in green when you meet
  them and red when you don't.
- **Objective and description** -- what to do and the story behind it.
- **Who starts it and who ends it**, with the zone and coordinates.
- A **maximize / restore** button (Blizzard's own) to read the text over the
  whole tree.

![The quest panel, with a locked quest's tooltip](https://media.joanvilarino.online/completao/images/screencaps/quest_info_pane.png)

![The quest panel maximized, with the requirement still missing](https://media.joanvilarino.online/completao/images/screencaps/maximize_pane_unavailable_quest.png)

### Find it, go there
- **Waypoint: start / turn-in** sets a [TomTom](https://www.curseforge.com/wow/addons/tomtom)
  waypoint to the quest giver or the turn-in, or the game's own waypoint if you
  don't use TomTom.
- **Show on map** opens the world map on the quest giver and drops a bouncing
  gold **!** marker on the exact spot, easy to see even on a busy map.
- Quest starts inside the instance? **Show entrance** takes you to the door of
  the dungeon instead.
- Already have the quest? **Open quest** opens your quest log right on it.

![The gold marker on the world map](https://media.joanvilarino.online/completao/images/screencaps/map_marker.png)

![A TomTom waypoint to the quest giver](https://media.joanvilarino.online/completao/images/screencaps/tomtom_integration.png)

### Made to stay out of your way
- Move and resize the window; its position, size, open section and selected
  dungeon are remembered **per character**.
- A minimap button opens it (drag it wherever you like), and the addon has its
  own icon in the AddOns list and on the window's portrait, next to its version.
- Completion is always read live from the game, so it is never out of date.

![The minimap button](https://media.joanvilarino.online/completao/images/screencaps/minimap_button.png)

Commands: `/completao` (or `/cpl`) opens the window, `/completao minimap` shows
or hides the minimap button.

---

## Where the data comes from

Quest data is generated, not typed in by hand: the Classic quests come from
Questie's database and the ones Forever adds are compiled from public quest
databases. That has a consequence you should know about:

- Every Classic dungeon has its quests.
- Of Forever's new content, **The Hall of Thanes** and **Ruins of Lordaeron**
  have theirs so far; the other new dungeons and the new raids appear as their
  quests are published, and coverage grows with each update.
- Quest text is English only; quest titles follow your client's language.
- Some quests start inside an instance and have no known starting point yet --
  for those the addon shows the entrance instead.

This is a beta: expect gaps, and please report them.

---

## Supported game versions

- Classic "Forever" (beta)

## License and credits

Completao!! is free software under the **GNU General Public License v3**.
Copyright (C) 2026 LechuckThePirate.

- The Classic quest data derives from [Questie](https://www.curseforge.com/wow/addons/questie)'s
  database -- thanks to its team and contributors.
- The names, text and locations of the quests Forever adds are compiled from
  public quest databases.
- The quests and every game asset belong to Blizzard Entertainment. World of
  Warcraft is a trademark of Blizzard Entertainment, Inc.; Completao!! is not
  affiliated with or endorsed by Blizzard, Questie or TomTom.

## Localization

English and Spanish interface (`esES` / `esMX` clients get Spanish). Missing a
translation for your locale? Open an issue or a PR on GitHub.

## Feedback & Issues

Found a bug, a wrong chain, a missing quest, or have an idea?
[Open an issue on GitHub](https://github.com/LechuckThePirate/Completao/issues).
