# Roguelike-like (Godot 4)

A roguelike **deckbuilder played on a graph of real video games**. Every node on
the map is an actual game connected to others it influenced; each run is a 5–8
game journey from a randomly chosen **Start** game to a hidden **Amulet** game,
fought through card combat, stat-check events, and a merchant shop.

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
├── project.godot          # Godot project definition (autoloads, input map, display)
├── icon.svg               # Application icon
├── .gutconfig.json        # GUT (test framework) configuration → runs res://test/
│
├── scenes/                # .tscn scenes, grouped by game mode
│   ├── menu/              #   main menu, character select, collection, settings
│   ├── overworld/        #   the influence-graph map you navigate between fights
│   ├── deckbuilder/      #   Slay-the-Spire-style card combat
│   ├── action/           #   real-time action-combat mode
│   └── strategy_prototype/#  grid/strategy combat prototype
│
├── scripts/               # All GDScript, mirroring the scenes + shared systems
│   ├── Main.gd           #   top-level orchestrator: boots a run, swaps scenes
│   ├── autoload/         #   global singletons (see "Autoload singletons" below)
│   ├── resources/        #   Resource schemas (CardData, ItemData, EnemyData, …)
│   ├── data/             #   generated catalogs (e.g. ReferenceCatalog.gd)
│   ├── deckbuilder/      #   card-combat logic & UI
│   ├── action/           #   action-combat logic & UI
│   ├── strategy/         #   shared strategy systems
│   ├── strategy_prototype/#  prototype strategy singletons & logic
│   ├── overworld/        #   map generation and navigation
│   ├── events/           #   pre-combat D20 event system
│   ├── menu/             #   menu / collection / settings screens
│   ├── runtime/          #   misc runtime helpers
│   └── ui/               #   shared UI widgets (toasts, log panel, HUD bits)
│
├── data/                  # Game content as Godot Resources (.tres) — the source
│   │                      # of truth the game loads at startup (see Data.gd)
│   ├── cards/            #   CardData
│   ├── items/            #   ItemData
│   ├── curses/           #   CurseData
│   ├── enemies/          #   EnemyData
│   ├── action_enemies/   #   ActionEnemyData
│   ├── events/           #   EventData
│   ├── characters/       #   CharacterData
│   ├── stats/            #   StatDefinition (the stat dispatcher's vocabulary)
│   ├── games/            #   GameData — the ~600 real games that form the map
│   ├── action_translation.tres
│   └── strategy_translation.tres
│
├── images/                # ★ All sprite/art PNGs — the single drop folder (below)
├── assets/                # Imported game-cover art used by the overworld map
├── addons/gut/            # GUT — the GDScript unit-test framework
├── test/                  # GUT test suites (test_*.gd)
├── docs/                  # Design docs (card authoring, stat dispatcher)
│
├── tools/                 # Shared Python tooling + design source of truth
│   ├── Roguelikes.xlsx    #   spreadsheet that drives the importers/generators
│   ├── Roguelikes.drawio6.svg
│   ├── generate_card_tres.py
│   ├── generate_curse_tres.py
│   ├── generate_event_tres.py
│   ├── generate_game_tres.py
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

**`images/` is the single drop folder for all sprite art**, organized by
category. Because the repository root is the Godot project, Godot reads this
folder directly as `res://images/…` — there is no second copy to keep in sync.

To add or replace art:

1. Drop a **PNG** into the matching subfolder, named to match the content id in
   **PascalCase**. The category folders are:

   | Folder | Used for |
   |---|---|
   | `images/cards/` | Card art (`res://images/cards/<Name>.png`) |
   | `images/items/` | Item art |
   | `images/statuses/` | Status-effect icons |
   | `images/Stats/` | Stat icons |
   | `images/enemies/` | Enemy sprites |
   | `images/characters/Full/`, `images/characters/Icon/` | Character portraits |
   | `images/heroes/`, `images/potions/`, `images/scrolls/`, `images/Spells/`, `images/powericons/`, `images/moves/`, `images/decks/`, `images/mods/`, `images/fish/`, `images/events/` | Their respective content |
   | `images/covers/` | Real-game cover art (source for `assets/games/`) |

2. **Reopen / refocus the Godot editor** so it imports the new file (Godot
   auto-imports anything placed under the project root).
3. Reference it from a `.tres` or script as `res://images/<category>/<Name>.png`.
   Most content already resolves art by convention from its id (e.g. a card
   named `IronWave` looks for `res://images/cards/IronWave.png`).

> The `legacy-web/images` entry is a **symlink** back to this same `images/`
> folder, so the old HTML build keeps resolving its art without a duplicate copy
> in the repo. You only ever drop art in **one** place: `/images`.

---

## Project architecture

### Autoload singletons

Globals are registered in `project.godot` under `[autoload]` and live in
`scripts/autoload/` (plus the strategy-prototype singletons under
`scripts/strategy_prototype/`). They are always loaded and survive scene changes.

| Autoload | Responsibility |
|---|---|
| `GameState` | Canonical run-persistent state (deck, inventory, HP, position). Resets on new run. |
| `Data` | Loads every `.tres` under `res://data/…` at startup and exposes lookups by id. |
| `EffectSystem` | Central dispatch for structured effects (`{type, value, target}`) applied via `EffectSystem.apply()`. |
| `TriggerBus` | Global signal hub wiring item/card/event triggers to game moments (`combat_start`, `on_action`, …). |
| `Stats` | Mode-aware stat dispatcher; loads `StatDefinition`s and answers stat queries. See `docs/stat-dispatcher.md`. |
| `GameLog` | Verbose run-scope message log the HUD log panel subscribes to. |
| `Notifications` | Curated player-facing "important events" channel (toasts + Backpack history). |
| `SaveSystem` | Two-layer save/load: numbered autosave slots + named saves (`user://`). |
| `Settings` | Run-independent preferences (e.g. game-filter) persisted to `user://settings.cfg`. |
| `TierList` | Cross-run tier list / ranking store that outlives any single run. |
| `GameStats` | Cross-run lifetime per-game play stats (games beaten / verified). |
| `DevTools` | Developer overlay (press `` ` ``) to grant any card/curse/item. Gated on `Settings.dev_mode`. |
| `StrategyState` / `StrategyTurnManager` / `StrategyLog` / `StrategyCombatSession` | Singletons for the strategy-combat prototype. |

### Game modes & scene flow

`scripts/Main.gd` is the top-level orchestrator: it boots a run and swaps between
full scenes (no overlaying one mode on another).

- **Menu** (`scenes/menu/`) — main menu, character select, the Collection screen,
  and Settings.
- **Overworld** (`scenes/overworld/`) — the influence-graph map of real games you
  navigate between encounters.
- **Deckbuilder combat** (`scenes/deckbuilder/`) — the primary Slay-the-Spire-style
  card combat (hand, energy, draw/discard/exhaust).
- **Action combat** (`scenes/action/`) — a real-time variant where "turns" run on a
  timer rather than discrete turn structure.
- **Strategy prototype** (`scenes/strategy_prototype/`) — an in-progress grid /
  strategy combat experiment with its own autoload singletons.

### Data as Godot Resources

All game content is authored as typed Godot **Resources** (`.tres`) under `data/`,
with their schemas defined in `scripts/resources/`:

`CardData`, `ItemData`, `CurseData`, `EnemyData`, `ActionEnemyData`,
`EventData`, `CharacterData`, `GameData`, `SpellData`, `StatDefinition`,
`AbilityCooldownConfig`, `ActionTranslation`, `StrategyTranslation`.

`Data.gd` loads them all on startup and serves them by id, so gameplay code never
hardcodes content — it asks `Data` for it.

---

## Content authoring & tooling

`tools/Roguelikes.xlsx` is the **design source of truth** for bulk content. The
Python scripts in `tools/` regenerate Godot resources from it (re-run after
editing the sheet, then review the diff):

| Script | Generates |
|---|---|
| `generate_card_tres.py` | `data/cards/*.tres` from the `cardsnew` sheet |
| `generate_curse_tres.py` | `data/curses/*.tres` from the `cursesnew` sheet |
| `generate_event_tres.py` | `data/events/*.tres` from authored Python dicts |
| `generate_game_tres.py` | `data/games/*.tres` from the curated games subgraph |
| `import-games-godot.py` | `data/games/*.tres` + copies covers into `assets/games/` |
| `import-reference-godot.py` | `scripts/data/ReferenceCatalog.gd` (Collection catalog) |

These require Python 3 with `openpyxl` (`pip install openpyxl`) and are run from
the repository root, e.g.:

```bash
python3 tools/generate_card_tres.py          # curses only
python3 tools/generate_card_tres.py --all     # whole card sheet
```

See `docs/card_authoring.md` for the full card Effects DSL and `docs/stat-dispatcher.md`
for how stats resolve across modes.

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
