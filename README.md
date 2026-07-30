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
│   └── ui/               #   shared UI (UITheme, RewardScreen, Collection, toasts)
│
├── data/                  # Game content as Godot Resources (.tres) — the source
│   │                      # of truth the game loads at startup (see Data.gd)
│   ├── games/            #   GameData — the ~750 real games that form the map
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
| `SaveSystem` | Two-layer save/load: numbered autosave slots + named saves (`user://`). Not yet wired into a games-first run — see the roadmap. |
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

- **`MainMenu.gd`** — new run, character select, the Collection, the tier list,
  and Settings.
- **`Overworld2.gd`** — the run itself: the offering of games (cover cards), the
  honour-system report step, the scrolls panel, and — right of the board — the
  player's inventory with the loot tray under it. Also hosts the toast strip, so
  an item's effects announce themselves the moment it's picked up.
  - **`BattlefieldView.gd`** — the board: the hero on the left, the grid the
    goal-enemies close in across, the off-field lane, the Push / Bomb toolbar, and
    the strike / advance animation.
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
| `import-games-godot.py` | `data/games/*.tres`, resolving each cover in `images2.0/games/` |
| `import-reference-godot.py` | `scripts/data/ReferenceCatalog.gd` (Collection catalog) |

These require Python 3 with `openpyxl` (`pip install openpyxl`) and are run from
the repository root, e.g.:

```bash
python3 tools/generate_item2_tres.py
```

See `docs/stat-dispatcher.md` for how stats resolve.

---

## Recent changes

Highlights from the most recent Godot sessions (newest first). The
spreadsheet-driven content below regenerates via the `tools/` importers, so
re-run them after pulling and review the diff.

- **Shields are the tries: an attempt tracker, and the board and checklist in one
  panel** — Block is gone and **Shields** take its place as the *runs you get at a
  game*. Selecting a game grants **3** (or **5** for a Traditional roguelike);
  every run of it you lose is one tick of the new **attempt tracker**, which spends
  a shield, and once they're gone a lost run costs **1 Health** (0 Health ends the
  run there). Whatever is left when you report the game absorbs the followers' hits
  and then **expires with the game** — shields never bank forward. **Anchor** moved
  to a new **`game_selected`** trigger so its +1 Shield is a genuine extra try
  before you play, not a reward afterwards. The report step and the battlefield are
  now **one panel**: the board on top, then the attempt strip, a tightened
  one-line-per-row checklist, and Completed Game. Outside a game the board is put
  away behind a **⚔ Board (N)** button in the header, so choosing a game is the
  only thing on screen. The board draws the pool as **pips on the hero** and a tick
  pops one with a floating `-1 ◆` — or flashes the hero red for `-1 ♥` once the
  shields are gone — and each offered card shows the tries it grants.

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
- **Saving a run** — `SaveSystem` snapshots and restores run state, but the menu's
  Continue list is gated off and Run History is a stub; a games-first run can't be
  resumed yet.
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
