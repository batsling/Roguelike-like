# Roguelike-like (Godot 4)

A roguelike **played on a graph of real video games**. Every node on the map is an
actual game connected to others it influenced; each run is a journey from a
randomly chosen **Start** game to a hidden **Amulet** game, and the "combat" is
you going off and actually playing each game to clear its goal — reported back on
the honour system, with defeated goal-enemies dropping relics.

This repository's **main project is the Godot 4.6 game at the repository root**.
The original browser/JavaScript version has been retired to
[`legacy-web/`](#legacy-web--the-old-html-version) and is kept only for
reference.

> **New here?** Open the folder in Godot 4.6+ and press play. The main scene is
> `res://scenes/menu/MainMenu.tscn`.

---

## Repository layout

The repository root **is** the Godot project (`project.godot` lives here), so
Godot resource paths map directly onto folders: `res://scripts/…` is
`scripts/…`, `res://images/…` is `images/…`, and so on.

```
.
├── project.godot          # Godot project definition (autoloads, display, one key binding)
├── icon.svg               # Application icon
├── .gutconfig.json        # GUT (test framework) configuration → runs res://test/
│
├── scenes/                # .tscn scenes — two of them; the UI is built in code
│   ├── menu/              #   MainMenu.tscn (the boot scene)
│   └── redesign2/        #   Overworld2.tscn (the game) + PlaySession2.tscn (its
│                          #   text-only precursor, kept as a harness)
│
├── scripts/               # All GDScript, mirroring the scenes + shared systems
│   ├── autoload/         #   global singletons (see "Autoload singletons" below)
│   ├── resources/        #   Resource schemas (ItemData, GoalEnemyData, GameData, …)
│   ├── data/             #   generated catalogs (e.g. ReferenceCatalog.gd)
│   ├── redesign2/        #   the games-first screens:
│   │                      #     Overworld2      — run flow: offering, report, pack
│   │                      #     BattlefieldView — the grid the enemies close in on
│   │                      #     EnemyInfoCard   — click-to-inspect enemy card
│   │                      #     RunMapModal / ScrollReadModal
│   ├── events/           #   the D20 event system (EventModal, D20DieView)
│   ├── menu/             #   the main menu
│   ├── runtime/          #   RunGraph — the real-games influence graph
│   └── ui/               #   shared UI (UITheme, RewardScreen, Collection, AtlasView, toasts)
│
├── data/                  # Game content as Godot Resources (.tres) — the source
│   │                      # of truth the game loads at startup (see Data.gd)
│   ├── games/            #   GameData — the ~750 real games that form the map
│   ├── atlas_layout*.tres#   BAKED star positions for the Atlas, one sky per game
│   │                      #   filter: all / _owned / _downloaded (tools/bake_atlas.py)
│   ├── items2.0/         #   ItemData — the relics that drop from a defeated enemy
│   ├── enemies2.0/       #   GoalEnemyData — goal-enemies, one per game beaten
│   ├── bosses2.0/        #   GoalEnemyData — the difficulty-gate bosses
│   ├── characters2.0/    #   CharacterData — the playable roster
│   ├── scrolls2.0/       #   ScrollData — identify-by-reading scrolls
│   ├── items/            #   ItemData (pre-2.0 set, still loaded)
│   ├── characters/       #   CharacterData (pre-2.0)
│   ├── events/           #   EventData — the D20 events
│   ├── encounters/       #   EncounterData — shops / deals / teleporters
│   ├── curses/           #   CurseData (shelved, kept — §5)
│   └── stats/            #   StatDefinition (the stat dispatcher's vocabulary)
│
├── images2.0/             # ★ Games-first art — covers, items, enemies, bosses, characters, scrolls
├── images/                #   Surviving pre-2.0 art (legacy items / events / encounters)
├── addons/gut/            # GUT — the GDScript unit-test framework
├── test/                  # GUT test suites (test_*.gd)
├── docs/                  # Design docs. `games-first-redesign.md` is the canonical
│                          # spec for the current build; the combat-era docs
│                          # (card authoring, action attacks, …) are kept for
│                          # reference only.
│
├── tools/                 # Shared Python tooling + design source of truth
│   ├── Roguelikes.xlsx    #   spreadsheet that drives the importers/generators
│   ├── Roguelikes.drawio6.svg
│   ├── generate_game_tres.py       #   data/games from the games sheet
│   ├── generate_item2_tres.py      #   data/items2.0
│   ├── generate_goal_enemy_tres.py #   data/enemies2.0
│   ├── generate_boss_tres.py       #   data/bosses2.0
│   ├── generate_character2_tres.py #   data/characters2.0
│   ├── generate_scroll2_tres.py    #   data/scrolls2.0
│   ├── generate_item_tres.py, generate_character_tres.py,
│   ├── generate_curse_tres.py, generate_event_tres.py,
│   ├── generate_encounter_tres.py  #   the pre-2.0 sets
│   ├── import-games-godot.py
│   └── import-reference-godot.py
│
└── legacy-web/            # The retired HTML/JS version (reference only)
```

---

## Getting started

1. Install **Godot 4.6** (Forward+ renderer) — see <https://godotengine.org/download>.
2. Open this folder in Godot (select the `project.godot` file).
3. On first open Godot generates its import cache in `.godot/` (gitignored) — this
   is normal and may take a moment while it imports the images.
4. Press **F5** / the play button. The game boots into
   `res://scenes/menu/MainMenu.tscn`.

### Running the tests

Tests use [GUT](https://github.com/bitwes/Gut), bundled in `addons/gut/`. The
suites live in `test/` (configured via `.gutconfig.json`). Run them from inside
the editor (the **GUT** bottom panel) or headless:

```bash
godot --headless -s addons/gut/gut_cmdln.gd
```

---

## Adding art / images

**`images2.0/` is the drop folder for all art the games-first build uses**,
organized by category. `images/` holds what's left of the pre-2.0 art (the item /
event / encounter / character sets whose `data/` resources still load it). Because
the repository root is the Godot project, Godot reads both directly as
`res://images2.0/…` / `res://images/…` — there is no second copy to keep in sync.

To add or replace art:

1. Drop a **PNG** (covers may be **JPG**) into the matching subfolder, named to
   match the content id in **PascalCase** — or, for covers, the sheet's `File`
   column. The category folders are:

   | Folder | Used for |
   |---|---|
   | `images2.0/games/` | Real-game cover art — the overworld cards + Games compendium |
   | `images2.0/items/` | 2.0 item art (`data/items2.0`) |
   | `images2.0/enemies/`, `images2.0/bosses/` | Goal-enemy and boss art |
   | `images2.0/characters/Full/`, `images2.0/characters/Icon/` | 2.0 character portrait + in-world token |
   | `images2.0/scrolls/` | Scroll art (identified art + `Unidentified.png`) |
   | `images/items/` | Legacy (1.0) item art for `data/items` |
   | `images/events/`, `images/encounters/` | Event / encounter art |
   | `images/characters/Full/`, `images/characters/Icon/` | Legacy character portraits |

2. **Reopen / refocus the Godot editor** so it imports the new file (Godot
   auto-imports anything placed under the project root).
3. Reference it from a `.tres` or script as `res://images2.0/<category>/<Name>.png`.
   Most content already resolves art by convention from its id or its sheet `File`
   column (e.g. a goal-enemy with `file = "Goblin"` looks for
   `res://images2.0/enemies/Goblin.png`).

> Art with nothing referencing it is deleted rather than kept "just in case" — the
> pruned folders (cards, statuses, covers, potions, spells, …) belonged to combat
> content whose `data/` resources are already gone. `legacy-web/images` is a
> **symlink** to `images/`, so the old HTML build resolves whatever art survives
> there; its cover/card pages are dead now that those folders are pruned.

---

## Project architecture

### Autoload singletons

Globals are registered in `project.godot` under `[autoload]` and live in
`scripts/autoload/`. They are always loaded and survive scene changes.

| Autoload | Responsibility |
|---|---|
| `GameState` | Canonical run-persistent state (inventory, HP, charges, position). Resets on new run. |
| `Data` | Loads every `.tres` under `res://data/…` at startup, exposes lookups by id, and owns the shared rarity ladder. |
| `EffectSystem` | Central dispatch for structured effects (`{type, value, target}`) applied via `EffectSystem.apply()`. |
| `TriggerBus` | Global signal hub wiring item/event triggers to game moments (`game_beaten`, `chest_granted`, …). |
| `Stats` | Stat dispatcher; loads `StatDefinition`s and answers stat queries. See `docs/stat-dispatcher.md`. |
| `GameLoop2` | The run loop: the games-beaten clock, the goal-enemy stack, and the grid the followers advance across. `Overworld2` is a view over it. |
| `ScrollSystem` | Scroll identification + reading (the unidentified-loot gamble). |
| `GameLog` | Verbose run-scope message log (teleports, pickups, item procs) — the written record behind the toasts. |
| `Notifications` | Curated player-facing "important events" channel; the overworld mounts `NotificationToasts` to show them. |
| `SaveSystem` | Save/load for a games-first run (`user://`): a named save per run plus the run's own autosave slot. Writes GameState, `GameLoop2`, and the overworld's on-screen state, and hands a loaded run back to the next `Overworld2` to boot. |
| `Settings` | Run-independent preferences (e.g. game-filter) persisted to `user://settings.cfg`. |
| `TierList` | Cross-run tier list / ranking store that outlives any single run. |
| `GameStats` | Cross-run lifetime per-game play stats (games beaten / verified). |
| `DevTools` | Developer overlay (press `` ` ``) to grant 2.0 items, scrolls, or curses to the run. Gated on `Settings.dev_mode`. |

### Screens & flow

There are only two scenes. `MainMenu.tscn` boots the game and hands off to
`Overworld2.tscn`, which **is** the game — the simulated combat modes were cut in
the games-first redesign (§11), so the real video game you go and play is the
combat. Every screen is built in code, so the scene files hold nothing but a root
node and its script.

- **`MainMenu.gd`** — new run, character select, the **Continue** list of saved
  runs, the Collection, the tier list, and Settings.
- **`Overworld2.gd`** — the run itself: the opening choose-your-start panel (three
  games, three genres, all 5–7 games from the amulet), the offering of games
  (cover cards), and
  then a two-column stage — checklist on the left (the standing goals while you're
  choosing, the honour-system report step + attempt tracker while you're playing),
  the battlefield on the right with the player's inventory and loot tray beneath
  it. Also owns the scrolls panel and hosts the toast strip, so an item's effects
  announce themselves the moment it's picked up.
  - **`BattlefieldView.gd`** — the board: the hero on the left with the shield
    pips over them, the grid the goal-enemies close in across, the off-field lane,
    the Push / Bomb toolbar, and the strike / advance animation.
  - **`EnemyInfoCard.gd`** — the click-to-inspect card for one enemy.
- **`RewardScreen.gd`** — chest rewards (level-ups, Wand of Wishing). Ordinary
  enemy drops don't open it: they land in the loot tray beside the board.
- **`RateGameModal.gd`** — the 1-10 tier-list score for a game. Strictly opt-in:
  it only ever opens from a **★ Rate** button (on the report panel while you're
  playing a game, and on the select screen for the game you last reported).
- **`EventModal.gd`** — the D20 stat-check events. Built and tested, but nothing
  on the games-first board opens it yet (see the roadmap).

`PlaySession2.gd` is the text-only precursor of the overworld, kept as a headless
harness for the loop.

### Data as Godot Resources

All game content is authored as typed Godot **Resources** (`.tres`) under `data/`,
with their schemas defined in `scripts/resources/`:

`GameData`, `GoalEnemyData`, `ItemData`, `CharacterData`, `ScrollData`,
`EventData`, `EncounterData`, `CurseData`, `StatDefinition`.

`Data.gd` loads them all on startup and serves them by id, so gameplay code never
hardcodes content — it asks `Data` for it. Random draws all share one rarity
ladder there too (`Data.roll_rarity_step` / `roll_item_rarity`): 75/20/5
common/uncommon/rare, with a 10% bump from rare to legendary.

---

## Content authoring & tooling

`tools/Roguelikes.xlsx` is the **design source of truth** for bulk content. The
Python scripts in `tools/` regenerate Godot resources from it (re-run after
editing the sheet, then review the diff):

| Script | Generates |
|---|---|
| `generate_game_tres.py` | `data/games/*.tres` from the curated games subgraph |
| `generate_item2_tres.py` | `data/items2.0/*.tres` from the 2.0 items sheet |
| `generate_goal_enemy_tres.py` | `data/enemies2.0/*.tres` from the goal-enemy sheet |
| `generate_boss_tres.py` | `data/bosses2.0/*.tres` from the boss sheet |
| `generate_character2_tres.py` | `data/characters2.0/*.tres` from the characters sheet |
| `generate_scroll2_tres.py` | `data/scrolls2.0/*.tres` from the scrolls sheet |
| `generate_item_tres.py` | `data/items/*.tres` from the items sheet (pre-2.0 set) |
| `generate_character_tres.py` | `data/characters/*.tres` (pre-2.0) |
| `generate_curse_tres.py` | `data/curses/*.tres` from the `cursesnew` sheet |
| `generate_event_tres.py` | `data/events/*.tres` from authored Python dicts |
| `generate_encounter_tres.py` | `data/encounters/*.tres` from the `encounters` sheet |
| `import-games-godot.py` | `data/games/*.tres` (incl. per-connection source + sequel flag), resolving each cover in `images2.0/games/` — then re-bakes the Atlas |
| `bake_atlas.py` | `data/atlas_layout.tres` — the Atlas star chart's positions |
| `import-reference-godot.py` | `scripts/data/ReferenceCatalog.gd` (Collection catalog) |

These require Python 3 with `openpyxl` (`pip install openpyxl`) and are run from
the repository root, e.g.:

```bash
python3 tools/generate_item2_tres.py
```

`bake_atlas.py` runs automatically at the end of `import-games-godot.py`, so
adding a game or a connection to the spreadsheet and re-importing moves the sky
with it. Run it directly to re-tune the layout:

```bash
python3 tools/bake_atlas.py --all-filters  # every sky (what the importer runs)
python3 tools/bake_atlas.py                # 8 capitals, full catalog
python3 tools/bake_atlas.py --filter owned # just the owned-games sky
python3 tools/bake_atlas.py --capitals 12  # re-cut the constellations
python3 tools/bake_atlas.py --stats        # report without writing
```

One sky is baked per `Settings.game_filter` value. The Atlas has to show the
graph the run actually travels — an owned-only run drawn over the full 751-game
sky would offer routes through games the run cannot enter — so each variant is
laid out from scratch over its own subgraph and gets its own capitals rather
than being the full map with stars hidden.

It refuses to write a layout in which any two stars overlap, so a bad run fails
loudly rather than shipping an unreadable map.

`tools/` carries a `.gdignore`, which keeps Godot from importing the working
files in there. Without it the editor rasterises `RoguelikeMap.svg` — a
133,638 × 51,748 px canvas — into a clamped 16384² texture on every fresh import.

See `docs/stat-dispatcher.md` for how stats resolve.

---

## Recent changes

- **Filters on the Collection's Constellations** — a filter row above the sky:
  **Constellations** (6 / 8 / 12), **Library** (owned / downloaded / not owned),
  **Type**, **Record** (beaten / never beaten / amulet won / has notes) and
  **Region** (one constellation), with a Clear button and a live *"88 of 757
  games"* count. Filters combine.

  Everything except the capital count **hides rather than moves**: the sky is a
  baked layout, and a star that jumps when you tick a box destroys any sense of
  where things are, so a filtered-out game dims right down in place and its links
  stop drawing. The capital count is the exception — it re-cuts every region and
  re-packs the sky, so 6 and 12 are baked as their own files
  (`atlas_layout_c6.tres` / `_c12.tres`) and switching swaps between them.
  Changing it clears the Region filter, since region indices mean different
  places in a different cut. The filter row only exists in the Collection's
  catalog view; a run's Atlas has no filters.

- **"Beatable:" on the offering** — while choosing where to travel, a card shows
  small portraits of the enemies you have **already beaten at that game before**:
  the enemy standing there now, and anything currently following you. It is not a
  prediction — it is your own record saying this pair has worked, which is
  exactly what you want while deciding where to drag a follower. Hovering a
  portrait gives the goal, how many times it fell there and whatever note you
  wrote. A card with nothing proven stays clean.

- **Per-game enemy notes** — games now remember **which enemies were beaten on
  them**, and you can write down how. Every enemy line on the end-of-game
  checklist carries a **🗒 Notes** button on its right; the button shows a pen
  once something is written, so an annotated row reads at a glance. Ticking the
  goal (or a follower you also cleared) logs that enemy against that game.

  On a game's Atlas card, **🗒 Notes — beaten enemies (n)** opens the list: each
  enemy's **art**, its goal, how many times it fell there, and your note under
  it, most-beaten first. Notes can be **edited or deleted** from there as well as
  written on the checklist — you often only work out how you beat something after
  the run is over. Deleting clears the note alone; how many times the enemy fell
  there is a record of fact, not a note, and stays.

  The Collection's **Enemies** tab shows the same record from the other side:
  each enemy's detail lists the **games it has been beaten in**, with cover,
  count and note in the same format, editable in place. The **Games** tab carries
  the mirror of it — every enemy beaten at that game.

  Both sides carry a completion stat as **x / y**: an enemy's *Games beaten in
  (3 / 91)*, a game's *Enemies beaten in (4 / 12)*. `y` is what **could** have
  happened rather than the whole catalog — enemies are rolled by matching game
  type, so an Action goal-enemy never appears at a Deckbuilder game and counting
  it against all 757 would make the number meaningless.

  A note belongs to the **pair**, not to the enemy — the same goal-enemy turns up
  on many games and how you cleared it is a fact about that combination. Notes
  are written where you actually beat the thing, which is when you remember how,
  and the Atlas panel is read-only. Stored in `game_stats.json` next to the rest
  of the lifetime record.

- **A star's rim is its genre; in the Collection, its middle is your record** —
  a game you've never played is drawn **solid in its own genre colour**, and one
  you have wears a **silver** pip once beaten or a **gold** one once you've won a
  run on it. Gold outranks silver, since winning a run implies beating it and the
  rarer fact is the one worth seeing. Putting the record in the core rather than
  on the rim keeps the sky readable **as genre at every zoom**, and a record
  reads as something *gained* rather than as the absence of dimming — the earlier
  "unplayed games are dimmed" rule is gone, since it washed out most of a catalog
  nobody has finished.

  The record is drawn **only in the Collection's Constellations**. During a run
  the sky is about the run — the route, where you stand, what you've bashed — and
  a lifetime marker competes with that, so the middles stay empty there. The
  info card still carries the numbers in either view, in the Collection's own
  vocabulary: **⚔ Beaten** and **👑 Amulet won**.

- **"Show constellation" in the Collection** — the Games tab gains a button that
  opens the whole catalog as the star chart, in **pure-catalog mode**: no run is
  laid over it. No route to the Amulet, no path taken, no you-are-here or Amulet
  rings, no strike-throughs on games bashed this run, and a transmuted node shows
  the game the catalog says lives there rather than what was pasted on it. It is
  titled *Constellations* rather than *Atlas* to make the difference plain.
  "Beaten" means the lifetime record here, where the in-run Atlas also counts what
  you've beaten on the way. Same sky, same layout — only what's drawn over it
  differs.

- **Run History, over the map** — the main menu's Run History is no longer a
  stub. Every finished run is kept as **the route it actually walked**: covers
  left to right in the order played, an arrow between each pair, the Amulet
  closing the row marked won or lost. A run that died short of the Amulet shows
  a **dashed** arrow across the stretch it never covered. The screen sits **on
  top of the Atlas**, so the strip is the route in order and the sky behind it is
  where that route went; **Show on map** throws a run onto it. Runs are written
  by `GameLoop2._finish_run`, now the single exit from a run, so one can't end
  without being recorded, and they persist in `game_stats.json` (capped at 40).

- **Bash and Transmute on the map** — a **bashed** game's star is struck through
  in red and every link into it turns red, because those routes no longer exist;
  its card says so, and so does any connection touching it. **Transmute is now a
  paste onto the spot**: it used to be a property of one offering, held locally
  by `Overworld2` and cleared on every move and scramble, so it evaporated the
  moment you walked on. It now lives in `GameLoop2` as node → replacement,
  survives moving, scrambling and saving, and the node plays that game for the
  rest of the run. `GameLoop2.game_at()` is the one place that answers "what game
  is actually here". The node keeps its place on the graph, so the map draws the
  pasted game's cover at the old spot with an ember ring and its card names both
  **Now** and **Was**; a connection card keeps naming the *original* games —
  the influence claim is between those — and adds a line saying what has been
  pasted over an endpoint.

- **Connection proof, and a card for the links themselves** — clicking a *line*
  on the Atlas now opens a card showing **both games side by side**, the
  influencer on the left with an arrow to the game it influenced, the claim in
  words ("X inspired Y"), and the **evidence** underneath. Links flagged in the
  sheet as a sequel or the same studio say so. A source that's a URL gets an
  **Open source** button; the ~280 that are notes ("check folder", "game
  credits") are shown as written rather than dressed up as links. Either game can
  be inspected from the card. Clicking a star still wins over a link under the
  same cursor, since near a hub the pointer is always over some line.

  This needed data the importer had been discarding. `Roguelikes.xlsx`'s
  `connections` sheet carries a **Source** column (884 of 1000 rows) and a
  **Dev/Series Relation** column (114 rows); `import-games-godot.py` read only
  the two game names and dropped both. `GameData` gains `influence_sources` and
  `influence_relations`, index-aligned with `games_influenced`, and the importer
  now carries them through. This closes the README's long-standing "connection
  proof" roadmap item — the evidence was gathered years ago and simply wasn't
  being imported.

  **Re-importing also caught the catalog up with the spreadsheet**, which it had
  drifted behind: **6 games** (How Many Dudes?, Inkbound, Mystery Chronicle: One
  Way Heroics, One Way Heroics, Runeveil, Zoominoes) and **11 net connections**
  that were authored in the sheet but had never reached `data/games/`. The
  catalog is now 757 games / 1000 connections, up from 751 / 988. This changes
  which routes exist, so runs will differ.

- **A staleness guard on the baked skies** — `data/atlas_layout*.tres` are
  generated and committed, so they can silently fall behind the catalog: a
  half-failed import, a hand-edited `.tres`, a merge that took one side. Star
  count alone never caught it — add a connection between two existing games and
  the count is identical while the map is wrong. The Atlas tests now rebuild the
  edge set from `data/games/*.tres` and compare it to each baked sky, and check
  every star is drawn at the size its real connection count says. A failure names
  the offending connection and tells you to re-run `tools/bake_atlas.py`.

- **The Atlas — all 751 games as a star chart** — a new full-screen map
  (`scripts/ui/AtlasView.gd`, opened from the main menu's **✦ Atlas** button, or
  from the run map's **✦ Star chart** button). Every game is a star: size is its
  connection count, the outline colour is its `GameType`. Games are grouped into
  **eight constellations** around the highest-degree hubs — Slay the Spire,
  The Binding of Isaac, Vampire Survivors, NetHack, FTL, Hades, Balatro,
  Spelunky Classic — with each game joining whichever capital it reaches in
  fewest hops. Detail follows zoom: dots and constellation names when zoomed out,
  links in the middle, every star named up close. Clicking a star isolates it —
  its links light up, the rest of the sky dims — and opens a card with the cover
  art, release year, connection count, home constellation, distance from its
  capital, and a **Play the real game** button where there's a launch target.
  While a run is under way the shortest path to the Amulet is drawn over the sky
  as an **ember trail** (green behind you, ember ahead), so the run map and the
  atlas are the same picture at two altitudes.

  There is **one sky per game filter**. Setting the path filter to *owned* (or
  *downloaded*) opens a different, independently laid out map — 457 games, its
  own capitals, Enter the Gungeon promoted where Balatro sits on the full map —
  because a route through an unowned game doesn't exist for that run and drawing
  it would be a lie.

  Positions are **baked, not computed at runtime** — `tools/bake_atlas.py` writes
  `data/atlas_layout*.tres`, and `import-games-godot.py` re-runs it for every
  filter, so editing the spreadsheet moves the sky. Inside a constellation each game orbits the game
  that influenced it, with subtrees packed as discs around their parent; a
  subtree's radius is *measured* from its realised layout rather than bounded
  from its children's, because the nested bound doubles at every level and threw
  deep chains thousands of units into the void. The bake verifies that no two
  stars overlap at their drawn radii and fails rather than writing a bad map.
  `Settings.game_filter` never moves a star — the atlas is the whole catalog.

Highlights from the most recent Godot sessions (newest first). The
spreadsheet-driven content below regenerates via the `tools/` importers, so
re-run them after pulling and review the diff.

- **Choose where you start, save the run, and bash that refills the slot** — a run
  now opens on a **choose-your-start panel**: three games, each a **different game
  type**, each **5–7 games from the randomly chosen amulet** (`RunGraph` retries
  the amulet until three genres can all fill that band rather than quietly
  offering a shorter route). The start is where you *begin* — no enemy spawns and
  no shields are granted — and its neighbours become the first offering.
  **Saving works end to end**: the overworld's **💾 Save** button names a run, the
  run keeps an **autosave** that is rewritten every time it moves and cleared the
  moment it ends, and the menu's **Continue** list resumes either. A save now
  carries all three halves of a run — GameState, `GameLoop2`'s enemy stack and
  destroyed games, and the overworld's own screen (the cards on the table, the
  game in play, the loot tray) — so a resumed run picks up exactly where it
  stopped. **Bash** still destroys a game for the rest of the run, and now
  **refills the slot it vacated** with another game *connected to where you are
  standing*, rolling a fresh goal-enemy for the replacement while every untouched
  card keeps the enemy it was already showing (bashing or transmuting one card
  used to silently re-roll the others). With nothing left to connect to, the slot
  goes with the game; bashing the **amulet game** or the **last card on the table**
  is refused, since both end the run rather than shape it. Also fixed: the
  overworld's registration as the mounted map was wiped by the run reset that
  immediately follows it, which had left scrolls unreadable and overworld actives
  (Ride the Bus) unusable for the whole run.

- **Shields are the tries: an attempt tracker, and a two-column playing screen** —
  Block is gone and **Shields** take its place as the *runs you get at a
  game*. Selecting a game grants **3** (or **5** for a Traditional roguelike);
  every run of it you lose is one tick of the new **attempt tracker**, which spends
  a shield, and once they're gone a lost run costs **1 Health** (0 Health ends the
  run there). Whatever is left when you report the game absorbs the followers' hits
  and then **expires with the game** — shields never bank forward. **Anchor** moved
  to a new **`game_selected`** trigger so its +1 Shield is a genuine extra try
  before you play, not a reward afterwards. While a game is in play the screen is
  **two columns**: on the left what you drive — the game, Play / Rate, the attempt
  strip, a tightened one-line-per-row checklist and Completed Game — and on the
  right what you read, the **battlefield with the pack (inventory + loot) under
  it**. Both halves fit one screen, where stacking them didn't. The stage keeps
  that shape **between games too** — the board is never hidden, and the checklist
  becomes a **standing-goals list** ("What you need to do": the character's
  level-up challenge and every follower's outstanding goal, tinted red once it's
  in the front column), so what you owe is answerable *before* you commit to a
  game rather than only after. The board draws the pool as
  **pips on the hero** and a tick pops one with a floating `-1 ◆` — or flashes the
  hero red for `-1 ♥` once the shields are gone. Each offered card shows the tries
  it grants, and since the pool is empty between games, hovering a card previews
  that grant in the HUD's Shields slot (`Shields +5`) instead of a flat 0.

- **Rating on a button, a bonus for rematches, revisits that redraw, and pickups
  that show their effects** — the tier-list prompt no longer pops itself up after
  a game; it opens from a **★ Rate** button (on the report panel, and on the
  select screen for the game you last reported), and the modal now actually
  covers the screen instead of leaving the board live behind it. Beating a game
  you have **already beaten this run** grants **+1 Dash**, called out as
  "⚡ Gain +1 Dash" above that game's cover in the offering (and on its hover
  preview), so doubling back is a real routing option; the clear is recorded on
  the run (`GameState.beaten_games`) and on the lifetime per-game tally the
  Collection and tier list read (`GameStats`). **Arriving** at a game salts the
  offering draw, so coming back to a node hands you a *different* subset of its
  neighbours rather than replaying the same three cards. Picking anything up now
  reports itself immediately: the HUD repaints off the state signals (Health /
  Max Health / verb counts no longer wait for the next game to resolve) and
  `GameState.add_item` diffs the run resources across the pickup to post a
  "Lunch: +2 Max Health, +2 Health" line — the toast strip is mounted on the
  overworld again, so those lines are visible at all.

- **Random Sized Chest + roster/content refresh** — the Vampire Survivors
  characters' level-up reward is a **Random Sized Chest**: the roll picks the
  chest's SIZE (Small 1 / Medium 2 / Large 3 / Huge 5 items) on the same
  75/20/5-with-a-10%-bump ladder as every other rarity draw
  (`Data.CHEST_SIZE_CHOICES`), rather than the rarity of what's inside. Ported
  **Poe Ratcho** and **Antonio Belpaese** plus new games, goal-enemies, and
  bosses from the sheet.

- **Inventory and loot beside the board; covers at box-art scale; the overworld
  split into three files** — the player's pack (inventory + a loot tray) stands
  in a column to the RIGHT of the battlefield grid, so a drop waits there to be
  claimed or skipped instead of standing on a cell. Cover art is drawn at its
  real 3:4 shape and ~1.5x bigger on the choice cards (210x280), in the
  Collection, in the rate-game modal, and on the report panel, which shows the
  game you went to play next to the enemy you went to beat. `Overworld2.gd` shed
  ~1000 lines to `BattlefieldView.gd` (the board, its animation, the Push/Bomb
  toolbar) and `EnemyInfoCard.gd` (the inspect card); the duplicated rarity rolls
  collapsed into `Data.roll_rarity_step` / `roll_item_rarity` and the
  crisp-texture helpers into `UITheme`.

- **Art reorganised into `images2.0/`** — every asset the games-first build uses
  moved to `images2.0/{games,items,enemies,bosses,characters,scrolls}/`, resolved
  from each sheet's `File` column. `images/` keeps only the pre-2.0 art that
  surviving `data/` resources still load.

- **Enemy footprints and multi-cell positioning** — an enemy occupies its whole
  `Size` footprint (`1x2`, `2x1`, `2x2`, or a shaped box like `2x3 L 90 CC`), and
  a placement is legal only when every solid cell is free. That single rule gives
  the board its behaviour: a wide body enters closer to the player and strikes
  sooner, a big body is a wall that stalls the queue behind it, an L leaves
  exactly the gap its notch describes, and **Push** needs the entire footprint to
  fit one column back. Art draws across the full bounding box and hit-testing
  follows the mask, not the box.

- **The MMBN-style grid battlefield with inline drops** — followers are drawn on
  a 4x4 grid (columns = distance, rows = lanes) with the player on the left.
  Enemies enter at the back, close one column per game beaten, and strike once
  any of their cells touch the front column; an overflow queue waits off-grid and
  slides on as space frees. Every defeated enemy's drop appears as loot to claim
  or skip instead of opening a reward screen.

- **Push + the Manager, and Deckbuilder promoted to a first-class game type** —
  **Push** (spend a charge to shove a follower one column back, delaying its next
  attack) arrived with the **Manager** character from Raccoin. The game types are
  now **Action / Deckbuilder / Traditional / Strategy** — `deckbuilder` and
  `traditional` were tags on Strategy and are authored on `GameData.type`
  directly, so each type draws its own goal-enemy pool.

- **Games-first item rewards and active item effects (§8)** — `items2.0` behaviour
  classes are wired end to end: `Pickup` (one-shot `item_acquired` effects),
  `Triggered` (the dominant `game_beaten` hook — Anchor, Burning Blood, Meat on
  the Bone), `Charged, N` (D6, Wand of Wishing), `Usable` (Ride the Bus), and
  `Passive` (Vajra's +1 Bash). Chests bank through `GameState.grant_chest` and
  redeem into `RewardScreen`s when the board is idle.

- **The games-first cut (§11)** — the simulated combat modes are gone: the
  deckbuilder / action / strategy scenes and scripts, combat cards and statuses,
  potions, spells, dice, and the combat enemy stat blocks were all removed (they
  live on in git history). What replaced them is `GameLoop2` — the goal-enemy stack,
  the games-beaten clock, the difficulty tiers and their boss rounds — plus
  `ScrollSystem` (identify-by-reading scrolls), the tiny Health / Max Health /
  Shield model, and the bash / dash / transmute / scramble / push verb layer.
  **The real video game you go and play is the combat.**

---

## Roadmap / future plans

The core loop is in and playable end to end: character select, a start/amulet
graph over 751 real games, the limited offering with its verbs, the honour-system
report step, goal-enemies that follow you across the grid, drops and chests,
level-ups, difficulty tiers with boss rounds, scrolls, the Collection, and the
cross-run tier list. What's still ahead:

- **The OBS companion HUD (§9)** — the design is stream-first: a slim always-on-top
  window showing health, shields, the current game + its goal, the follower stack,
  and the verb/consumable counts, reading the same autoloads the main window
  mutates. Deferred by decision until the mechanics lock; it is the largest
  unbuilt piece of the spec.
- **Overworld encounters** — shops, deals, teleporters, and challenge rifts are
  authored (`data/encounters/*.tres`, `EncounterData`, its sheet + generator, and
  `GameState.encounter_requirement_met`), but nothing on the games-first board
  offers them yet. They need a place in the offering / between games.
- **The D20 events** — `EventModal` + `data/events` are built and tested, and are
  likewise not reachable from the current overworld. Same question: when does a
  run stop for an event?
- **Run History** — saving and resuming a run is done (Save button, autosave,
  Continue list), but the menu's Run History is still a stub: nothing records a
  run once it's finished, so there's no post-mortem to read.
- **Keys and locked paths** (and the **Fog** scroll) — deferred by decision (§4):
  no 2.0 content grants keys, and no edge is gated behind one.
- **Tags and path requirements (§6.2)** — widen the tag vocabulary on `GameData`
  and let an edge demand a type or tag ("this route needs a Deckbuilder clear"),
  so routing becomes a collection puzzle rather than a shortest path.
- **Content depth** — the catalogs are thin next to the 751 games: 29 goal-enemies,
  32 bosses, 15 items, 6 scrolls, 9 characters. More of each (and more goals per
  type) is the cheapest way to add run variety; all of it comes from the sheet.
- **The open design decisions (§7.1 / §12)** — the boss damage band above the
  normal 1–3, whether bash / transmute / scramble should stay legal on a boss
  round (they currently are), and the goal-enemy `Ability` column, which exists
  in the schema but is `N/A` across the roster.
- **Connection proof** — surface the evidence behind each game-to-game influence
  edge (a screenshot in a `proof/` folder or a link), stored on the connection
  data and shown when inspecting a connection.
- **Unconnected games** — give a purpose to games with no edge into the current
  route. Transmute already pulls one off-graph; keys / "wild" games are the other
  half of the idea.
- **Game-space statuses** — port the HTML build's map-space statuses (Charmed,
  Devilish, Holy, Marked) that trigger when you land on a space
  (`game-statuses-data.js`).
- **More map movement** — additional movement items, loot, and mechanics beyond
  Dash / Ride the Bus / Scroll of Teleportation.
- **Curses** — shelved on purpose (§5): the enemy-with-a-goal is the challenge
  mechanic. The 16 curses and their hooks stay in the repo in case they come back
  as an opt-in gambit layer.

New content is driven by `tools/Roguelikes.xlsx`, so adding a system is largely a
matter of a Resource schema in `scripts/resources/`, a generator in `tools/`, and
the UI.

---

## `legacy-web/` — the old HTML version

The original game was a browser build (~42k lines of vanilla JavaScript across
38 modules). It has been **superseded by the Godot project** and moved wholesale
into `legacy-web/` (its `index.html`, `css/`, `js/`, `data/`, `tests/`,
`scripts/`, and Vite config). It still runs — double-click `legacy-web/index.html`
— but it is **no longer the active project** and is kept for reference and
parity-checking only.

Its art is served through the `legacy-web/images` symlink that points back to the
root `images/` folder, so there is exactly one image store for the whole repo.

---

## Conventions

- The repo tracks **source only**. Godot's generated `.godot/` cache, `*.import`,
  `*.uid`, and `export_presets.cfg` are gitignored and regenerate on open.
- Art filenames are **PascalCase** and matched to content ids by convention.
- The spreadsheet (`tools/Roguelikes.xlsx`) drives generated content — edit it
  there and regenerate rather than hand-editing generated `.tres` in bulk.
