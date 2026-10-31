# Completao!! — agent guide

World of Warcraft Classic addon: quest chain trees per dungeon, raid, zone, class... in the spirit of BtWQuests. The data is
per game client (`Data/<Flavor>/`, one `Load_Data_<Flavor>.xml` each): today only Forever (interface 16001; its beta has ended),
with Classic Era, TBC Anniversary and Retail planned. Public repo `LechuckThePirate/Completao` (branch `master`), GPLv3, CurseForge project id 1716061.
Sibling addons with the same conventions: `Embolsao` and `Aggreao` (both under `D:\Source\WowAddons\`).

## How to work with the maintainer

- **Chat in Spanish from Spain** ("tú", never Argentine voseo: not "tenés", "contame", "dale"). **Everything committed is in English**:
  code comments, test names, tool output, workflow comments, docs, commit messages. Only the translation tables in
  `Localization/<locale>.lua` hold other languages.
- Windows machine. Prefer the PowerShell tool over Bash. Multi-line commit messages: write a file and use `git commit -F <file>`.
- Work happens in git worktrees (`.claude/worktrees/<name>`, branch `claude/<name>`). **After every change (tests green) commit and
  push** (`git push origin HEAD`). **Merging to `master` and cutting a release only happen when the maintainer asks.**
- Keep the maintainer informed in one or two short lines during long tasks.
- Never mention the source of the Forever quest data in anything tracked (README, CHANGELOG, CurseForge text, comments, commit
  messages). The public wording is "public quest databases". The generators that talk to it stay in git-ignored `tools/local/`.
- Do not store quest descriptions in saved variables (the maintainer refused: too much data).

## Layout

Addon files live at the repo root and are packaged as the folder `Completao` (`.pkgmeta`), like Questie:

- `Completao.toc` (the Forever client's; it lists three load files, `Load_Core.xml` -> `Load_Data_<Flavor>.xml` -> `Load_Modules.xml`, which hold the
  load order), `Completao.lua` (entry), `Bindings.xml`. The other clients get their own `Completao_<Suffix>.toc` with their own data file
- `Modules/Core/Flavor.lua` -- `ns.flavor` (`forever`, `vanilla`, `tbc`, `mainline`) from the interface number
- `Localization/` — `Locale.lua` (English text is the key; `ns.AddLocale`) + `esES, deDE, frFR, itIT, ptBR`
- `Modules/API/API.lua` -- the public global `CompletaoAPI` for other addons (Fabrikao reads it: keep it stable, bump `version` on a breaking change)
- `Modules/{Database,Quest,Settings,Graph,Map,UI}/` — every `X.lua` has `X.test.lua` next to it
- `Data/<Flavor>/` — one folder per client (today only `Forever/`): `Dungeons.lua`, `Raids.lua`, `Battlegrounds.lua` (hand-registered),
  `Overrides.lua` (manual fixes), `Generated/` (**never hand-edit; regenerate**)
- `tools/` — `questie_forever.mjs` + `questie_db.mjs` generate `Data/Forever/Generated` from Questie's Forever database;
  `tools/local/` is git-ignored (deploy script, web-sourced data helpers, caches)
- `test/` (WoW API mock + local runner), `setupTests.lua`, `images/screencaps/` (CurseForge description images)

## Commands (PowerShell, repo root)

```powershell
lua test/busted.lua                                  # all tests, no busted install needed (Lua 5.1+)
lua test/busted.lua (git ls-files '*.test.lua')      # same, but ignores tests inside nested .claude\worktrees (use on master)
luacheck Completao.lua Localization Modules Data/Forever/Dungeons.lua Data/Forever/Raids.lua Data/Forever/Overrides.lua test setupTests.lua   # if installed
node tools/questie_forever.mjs                       # regenerate Data/Forever/Generated from Questie's Forever data
pwsh tools\local\deploy.ps1                          # copy the addon into D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\Completao, then /reload
```

`tools/local/deploy.ps1` is git-ignored, so a fresh worktree does not have it: run it from the main checkout
(`D:\Source\WowAddons\Completao`) or copy it; it derives the source folder from its own location.

## Code conventions

- Lua 5.1 (the game's version). Shared namespace: `local _, ns = ...` in every file; no new globals (see `.luacheckrc`).
- English text is the localization key: `ns.L["Some text"]`; add translations to the per-locale files, never block on them.
- Comments explain *why*, are short, and match the surrounding density. Match surrounding naming and idiom.
- Every module gets a `*.test.lua` next to it, starting with `dofile("setupTests.lua")`; tests set globals through `_G.X`.
  New behavior ships with tests. CI runs busted on Lua 5.1 and luacheck (`.github/workflows/ci.yml`).
- Quest data in `Data/Forever/` is already in Forever map coordinates (the generators convert whatever they read); manual fixes go
  in `Data/Forever/Overrides.lua`, never in `Data/Forever/Generated/`.
- User-visible changes go in `CHANGELOG.md` under `## Unreleased` (style: `New:` / `Fixed:` bullets, plain sentences).

## Infra and release

- **CI:** `.github/workflows/ci.yml` (luacheck + busted on every push).
- **Daily data refresh** (two jobs, both end as a pull request that the maintainer merges, never automatically):
  `.github/workflows/update-quests.yml` (cron) regenerates `Data/Forever/Generated` from the latest QuestieDB Forever release and opens
  `auto/quest-data`; the rewards and new quests (`Rewards.lua`, `ForeverNew.lua`) are generated by a cron job on the
  maintainer's server that publishes both files at the media host, and `update-web-data.yml` fetches them and opens
  `auto/web-data`. The server holds no credentials for this repo. Both workflows need the repo setting "Allow GitHub Actions to
  create and approve pull requests".
- **Repo hardening:** actions are pinned by commit SHA (Dependabot updates them weekly; the repo requires SHA pinning), a ruleset
  makes `master` PR-only (the owner can bypass), and `CF_API_KEY` belongs to the `release` environment, which only `master` and
  `v*` tags can use. Repository deploy keys count as admins for ruleset bypass, so never add a write deploy key.
- **Release** (only when asked; beta or stable, see below): on `master`, one commit `chore: release X.Y.Z` (`X.Y.Z-beta` for a beta) that bumps
  `## Version` in `Completao.toc`, renames `## Unreleased` to the version in `CHANGELOG.md`, and updates
  `LATEST_CHANGELOG_TEXT` in `Modules/UI/Welcome.lua` (keep the words "Turn in" out of it: a Search test looks for that text on
  screen). Then `git tag vX.Y.Z` (`vX.Y.Z-beta` for a beta), push `master` and the tag, and run
  `gh workflow run release.yml --repo LechuckThePirate/Completao --ref vX.Y.Z` (workflow_dispatch; BigWigsMods/packager
  uploads to CurseForge with repo secret `CF_API_KEY` and creates the GitHub release). Watch with `gh run watch`.
- **Beta vs stable:** the same commit, tag and workflow; only the tag name differs. The packager reads the channel from it: a tag
  containing `alpha`/`beta` (`v1.2.0-beta`) goes out as a GitHub pre-release and a CurseForge Beta file, any other (`v1.2.1`) as the
  GitHub "Latest" release and a CurseForge Release file. `## Version` in the `.toc` never carries the suffix. Betas have been the
  norm; a stable one is cut when the maintainer asks, and it gets a version number of its own rather than reusing the last beta's
  (`1.2.0-beta` -> stable `1.2.1`), so no two packages share one `.toc` version. Its CHANGELOG section lists only what is new since
  the last beta (the beta sections stay as they are), but `LATEST_CHANGELOG_TEXT` summarizes everything since the last stable
  release, since that is what players on the stable channel have not seen yet.
  Check with `gh release list` that the new one is marked "Latest" and not "Pre-release".
- **Screenshots:** `images/screencaps/*.png` are optimized and rsynced by `.github/workflows/sync-media.yml` (push to master touching
  that path, or `gh workflow run sync-media.yml`) to `https://media.joanvilarino.online/completao/images/screencaps/`, which
  `CURSEFORGE_DESCRIPTION.md` references. Secret `COMPLETAO_MEDIA_SSH_KEY` (restricted rsync-only user on the maintainer's VPS).
- The `.pkgmeta` ignore list keeps tests, tools and images out of the CurseForge package.

## Gotchas

- Renaming the addon folder resets saved variables (new SV file name); don't rename casually.
- Run PowerShell renames from a folder that is not the addon folder (it gets locked otherwise).
- The web sources throttle (403 beyond ~1 request / 3 s) and, since mid-October 2026, refuse scripted requests to the Forever
  pages altogether: local fetch tools stay slow and never try to get around a refusal. The server job probes once, and while
  it is refused it writes the rewards from the cached listings plus open data (`tools/local/open_rows.mjs`) and publishes
  `source.txt` (`open since <date>`); when the sources answer again the next run goes back to them by itself.
- Forever moved the map coordinates of 4 zones (Mulgore, Eastern Plaguelands, Redridge, Stormwind) relative to Classic Era:
  anything sourced from Era coordinates needs converting (the git-ignored `tools/local/era_to_forever.mjs` does it).
- Questie's data lives in a separate `QuestieDB` addon (baked CBOR in `QuestieDB_Forever.toc`). CBOR gotchas: half-float
  coordinates, and Lua maps keyed 1,2,3... come out as arrays (`keyed()` in `tools/questie_db.mjs`).
