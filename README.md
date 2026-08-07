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
├── CHANGELOG.md           # The running change narrative (was this file's biggest section)
├── CLAUDE.md              # Orientation for coding agents working in the repo
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
│   │                      #     RunOverScreen   — the end-of-run verdict screen
│   │                      #     RunMapModal / ScrollReadModal
│   ├── events/           #   the D20 event system (EventModal, D20DieView)
│   ├── menu/             #   the main menu
│   ├── runtime/          #   RunGraph — the real-games influence graph
│   └── ui/               #   shared UI (UITheme, RewardScreen, Collection, toasts)
│                          #     AtlasView + AtlasLayoutBuilder — the star chart
│                          #     and the runtime layout behind its filters
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
│   ├── statuses2.0/      #   StatusData — clauses bolted onto goals (§13)
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
├── docs/                  # Design docs for the CURRENT build. `games-first-redesign.md`
│   └── archive/           #   is the canonical spec. The combat-era docs (card
│                          #   authoring, action attacks, Fear, …) describe systems
│                          #   the games-first cut removed — kept for reference,
│                          #   see docs/archive/README.md before trusting a path.
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
│   ├── generate_status_tres.py     #   data/statuses2.0
│   ├── _xlsx_surgery.py            #   edit one sheet without losing the charts
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
   | `images2.0/statuses/` | Status art (`data/statuses2.0`) |
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
`StatusData`, `EventData`, `EncounterData`, `CurseData`, `StatDefinition`.

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
| `generate_status_tres.py` | `data/statuses2.0/*.tres` from the `statuses2.0` sheet |
| `generate_item_tres.py` | `data/items/*.tres` from the items sheet (pre-2.0 set) |
| `generate_character_tres.py` | `data/characters/*.tres` (pre-2.0) |
| `generate_curse_tres.py` | `data/curses/*.tres` from the `cursesnew` sheet |
| `generate_event_tres.py` | `data/events/*.tres` from authored Python dicts |
| `generate_encounter_tres.py` | `data/encounters/*.tres` from the `encounters` sheet |
| `import-games-godot.py` | `data/games/*.tres` (incl. per-connection source + sequel flag), resolving each cover in `images2.0/games/` — then re-bakes the Atlas |
| `bake_atlas.py` | `data/atlas_layout.tres` — the Atlas star chart's positions |
| `import-reference-godot.py` | `scripts/data/ReferenceCatalog.gd` (Collection catalog) |
| `_xlsx_surgery.py` | shared helper: edit ONE sheet of `Roguelikes.xlsx` in place. An openpyxl round-trip drops the workbook's seven charts, so the sheet-editing one-shots (`_statuses_sheet_setup.py`, `_items2_statuses_setup.py`) rewrite just that sheet's XML parts and copy every other zip entry through untouched. |

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

**The same layout also runs at runtime.** `scripts/ui/AtlasLayoutBuilder.gd` is
a GDScript port of the baker's layout half (`build_graph` / `span_tree` /
`cluster_layout` / `pack_around` / `pack_discs`), because the sky for a filter
the player assembles in the Collection — "Deckbuilder + never beaten + owned" —
is one of hundreds of combinations and cannot be baked. The two agree about the
*shape* of a sky (same capitals, same regions, same hops, same no-overlap
guarantee) but are not bit-identical: `math.hypot` is not `sqrt(x*x + y*y)` in
the last bits, and the packer picks positions with strict comparisons a one-ulp
difference can flip. That never shows, because the unfiltered catalog is drawn
from the baked file. Keep the two in step when either changes — the tests in
`test/test_atlas_layout_builder.gd` assert the agreement.

`tools/` carries a `.gdignore`, which keeps Godot from importing the working
files in there. Without it the editor rasterises `RoguelikeMap.svg` — a
133,638 × 51,748 px canvas — into a clamped 16384² texture on every fresh import.

See `docs/stat-dispatcher.md` for how stats resolve.

---

## Recent changes

The running change narrative lives in **[`CHANGELOG.md`](CHANGELOG.md)**, newest
first.

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
