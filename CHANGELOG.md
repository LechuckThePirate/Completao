# Changelog

## 0.1.0

First version.

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
  Lordaeron have theirs, from Wowhead. The other new dungeons and the new raids
  are empty until their quests are published.
