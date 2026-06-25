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
│   ├── generate_item_tres.py
│   ├── generate_enemy_tres.py     #   data/enemies from the enemiesD sheet
│   ├── build_enemiesD_sheet.py    #   (re)builds the enemiesD sheet itself
│   ├── generate_strategy_enemy_tres.py # data/strategy_enemies from enemiesS
│   ├── build_enemiesS_sheet.py    #   (re)builds the enemiesS sheet itself
│   ├── add_status_addon_rows.py   #   adds status/addon rows to the sheets
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
| `DevTools` | Developer overlay (press `` ` ``) to grant any card/curse/item, or tick up to 5 enemies and start a test combat in any engine (deckbuilder / action / strategy via the combat-type selector). Gated on `Settings.dev_mode`. |
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
| `generate_evolution_tres.py` | the evolved card `.tres` + `scripts/data/EvolutionCatalog.gd` from the `Evolutions` sheet |
| `generate_curse_tres.py` | `data/curses/*.tres` from the `cursesnew` sheet |
| `generate_item_tres.py` | `data/items/*.tres` from the items sheet |
| `generate_event_tres.py` | `data/events/*.tres` from authored Python dicts |
| `generate_game_tres.py` | `data/games/*.tres` from the curated games subgraph |
| `generate_enemy_tres.py` | `data/enemies/*.tres` from the `enemiesD` sheet (+ copies enemy art into `assets/enemies/`) |
| `build_enemiesD_sheet.py` | (re)builds the deckbuilder-enemy `enemiesD` sheet from the legacy `enemies` rows |
| `generate_strategy_enemy_tres.py` | `data/strategy_enemies/*.tres` from the `enemiesS` sheet (Strategy / tactical-grid enemies) |
| `build_enemiesS_sheet.py` | (re)builds the Strategy-enemy `enemiesS` sheet from its `ENEMIES` list |
| `add_status_addon_rows.py` | adds/updates status + addon rows in `statusesnew` / `addonsnew` |
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

## Recent changes

Highlights from the most recent Godot sessions (newest first). The
spreadsheet-driven content below regenerates via the `tools/` importers, so
re-run them after pulling and review the diff.

- **Weighted enemy encounters** — combats now field a **scaled group** instead of
  a single random enemy. `scripts/runtime/EnemySpawner.gd` ports the legacy
  budget/tier "weight" spawn: the run's **RunDifficulty** tier sets a spend budget
  (first combat 2, then Low=4 / Med=6 / High=9 / Insane=12), enemies are picked
  weighted by their `weight` cost up to the 5-enemy cap, the pool is gated by tier
  (Boss-difficulty reserved for boss fights), and a new
  `GameState.total_combats_completed` counter eases the opening fight. Wired into
  `GameMap` / `Main`; pure logic covered by `test/test_enemy_spawner.gd`.
- **Deckbuilder enemy system (data-driven)** — deckbuilder enemies are now
  generated from a dedicated **`enemiesD`** sheet by `tools/generate_enemy_tres.py`
  into `data/enemies/*.tres` (12 Slay-the-Spire enemies). Each enemy's **Moves**
  column compiles into a weighted **intent pattern** (`t1` forced opener +
  `any @ weight` moves → per-turn probabilities), and the legacy ability column
  becomes structured data (split target/count, starting statuses). A minimal
  **Slimed** status card was added to `cardsnew` for the slimes' card pressure,
  and a **5-enemy battlefield cap** (`DeckbuilderCombat.MAX_ENEMIES`) bounds spawns
  and Splits. Regenerate with `build_enemiesD_sheet.py` → `generate_enemy_tres.py`.
  See `docs/enemy-plan.md`.
- **Strategy enemy system (data-driven)** — tactical-grid enemies are authored in a
  dedicated **`enemiesS`** sheet by `tools/generate_strategy_enemy_tres.py` into
  `data/strategy_enemies/*.tres` (`StrategyEnemyData`). One sheet is the single
  source of truth for stats, the **Intents** move-set (each intent carries a
  StrategyAttackLibrary `shape`, cooldown, priority, target and condition), the
  spawn-pool gate (`Min Floor` / `Spawn Weight`) and the loot table (`Gold` /
  `Item %`) — replacing the dictionaries that used to live in `Unit.gd`,
  `EnemyCatalog.gd`, `BattleView.gd` and `Map.gd` (kept only as fallbacks). A single
  **Speed** stat now drives both initiative cadence and tile budget. Regenerate with
  `build_enemiesS_sheet.py` → `generate_strategy_enemy_tres.py`. See
  `docs/strategy-enemy-authoring.md`.
- **Enemy status mechanics across all combats** — eight enemy-facing mechanics now
  run in the shared `Stats.gd` status core, so deckbuilder, action, and strategy
  all get them: **Determined** (a value rolled once per combat), **Split** (slimes
  spawn copies at ≤50% HP), **Shifting** / **Shackled** (Transient's power-shift
  cycle, fed by a shared damage-taken tally), **Ritual** (gains Power each turn),
  **Curl Up** (Block on the first hit each turn), **Fading** (turn countdown to
  death), and **Confused** (randomizes card energy costs each turn — shown on the
  Action card art during cooldown), plus **per-turn damage scaling**
  (`dmg:N:per_turn=M`, Transient's +10/turn). Authored in `addonsnew` /
  `statusesnew` and folded into `ReferenceCatalog`.
- **Dev test-combat menu** — the `` ` `` DevTools overlay gains an **Enemies** tab:
  pick a **combat type** (deckbuilder / action / strategy — the roster switches to
  that engine's enemies), tick up to 5, and **Start Combat** to drop straight into
  that engine's fight against the roster, mid-run and with no run-progress side
  effects, for isolated mechanic testing.
- **Games/connections refresh + new items** — regenerated the games graph from the
  spreadsheet (now **685** games, incl. 6 new traditional roguelikes) with
  refreshed influence edges and launch links; added the **Empty Tome**
  (combat-start weapon cost discount via the new `reduce_card_cost` effect) and the
  **Dexecutioner / Lil' Bomber / Glass Eye** weapon items.
- **Weapon evolutions + Finesse / Explosive / element UX** — a new **Evolution**
  mechanic (sheet-authored in the `Evolutions` tab) irreversibly transforms a
  base weapon card the instant its two requirements are met: **Lil' Bomber** + any
  Crown item → **King Bomber** (gains 5–9 Gold on an enemy hit, art swaps to the
  `images/Evolutions/` form), with a notification and an **Evolutions** sub-tab in
  the Collection. Lil' Bomber also gains the **Fire** element (1 Burn on hit) and
  an **Explosive** projectile that bursts into an AOE on impact in both Action and
  Strategy. **Dexecutioner** carries the new **Finesse** addon (bonus damage also
  scales with Defense / Dexterity). Cards now show an **element badge**, the
  backpack card-zoom explains a card's elements/addons/statuses in a tooltip
  sidebar, and dragging a targeting card over an enemy shows a **dynamic hover
  card** reflecting conditional effects against that specific target. Regenerate
  with `generate_card_tres.py --attacks`, `generate_evolution_tres.py`, and
  `import-reference-godot.py`.
- **Strategy combat → grid deckbuilder** — the tactical mode now plays like the
  deckbuilder on a grid. Combat starts immediately (no pre-combat loadout); your
  whole run deck shuffles into a draw pile and you draw a fresh hand each turn
  with **energy** (`GameState.max_energy`). **Movement costs energy** — each move
  spends 1 energy to walk up to your Speed-stat tiles, repeatable. The basic
  attack is just a **Strike card**; attacks are **in-range only** (footprint
  aiming via `StrategyAttackLibrary`) so positioning matters, and AOE hits only
  units inside the footprint. **Block** resets at the start of your turn, **Dash**
  is a once-per-combat bonus turn, and **curse cards** clog the hand and fire
  their eot / on_play_other triggers — all matching the deckbuilder. Drops the
  old loadout, weapon-slot, per-run card-uses, empower-charge translation, and
  the in-combat Spellbook/mana (shelved). See `scripts/strategy/combat/BattleView.gd`.
- **Status-effect system + Fear** — a mode-aware status system wired across
  deckbuilder, action, and strategy combat, with **Fear** as the first fully
  designed status (`docs/fear-status-design.md`). `statusesnew`/`addonsnew`
  now drive the Collection Reference tab, including the **Fear** status and
  the **Unplayable** / **Eternal** card addons.
- **Curse-synergy items** — Death Orb, Du-Vu Doll, Golden Beetle, and
  Vitality Orb, plus the EffectSystem/TriggerBus hooks they ride on.
- **Dice & combat inventory** — early dice items (D6, Wooden Nickel), a
  charge-bar widget, and a combat inventory panel shared across modes.
- **Event content port** — the first authored pre-combat events (Watching
  Eyeballs, Fruit Basket, A Note For Yourself, The Ssssserpent) generated from
  the `events` sheet, a reworked `EventModal`, and a Collection Reference tab.
- **D20 die view & rewards polish** — overhauled D20 roll view, rarity styling,
  the Backpack history panel, treasure-room/shop tweaks, and new items
  (Burning Blood, Ring of the Snake).
- **Combat feel & UX fixes** — run-map scrolling, dungeon combat feel, pause
  menu, mouse controls, and a RateGameModal soft-lock fix.

---

## Roadmap / future plans

The Godot port already covers the core loop (overworld map, deckbuilder &
action combat, events, curses, items, status effects, curse-synergy items,
shop, escape phase, characters, saves, collection, and game verification). The
work still ahead — much of it porting remaining systems from the legacy HTML
build:

- **Loot system** — add the consumable loot tables: **potions**, **scrolls**,
  and **fish**, and introduce **bombs** and **keys**.
- **Fix the deckbuilder map screen** — polish/repair the in-combat map view.
- **Finish the content catalogs** — port the remaining **cards**, **items**,
  and **addons** so the Godot catalog matches the spreadsheet.
- **Spells** — port the spell system and add new spells (`SpellData` exists;
  the deckbuilder-side spells panel still needs wiring).
- **Events** — the event system and first authored events are in (see Recent
  changes); port the remaining pre-combat events and author new ones.
- **Attack / weapon card → action-combat translation** — *first pass done.* A
  named, data-driven **attack-archetype** vocabulary (poke/swing/smash/nova/
  projectile/lob/beam/homing/smite/auto_aoe) now drives delivery in the action
  arena, authored in the sheet's Attack column and tuned in
  `data/action_attacks.tres`. See `docs/action-attack-translation.md`. Still
  ahead: per-archetype art/polish, the unused `lob`/`homing` shapes wired to
  real cards, and tuning passes on reach/radius feel.
- **Shop / gold scaling** — tune merchant pricing and gold rewards so they
  scale across a run (the shop screen itself is in place).
- **Difficulty-change boss** — a boss encounter triggered when the run's
  difficulty tier changes, granting a reward on victory (possibly **curse
  removal**).
- **Start-of-run reward** — a free reward granted at the start of a run, chosen
  to match the **game type** the player picks.
- **Connection proof** — surface the evidence behind each game-to-game
  influence edge. Most connections have proof: a screenshot stored in a
  `proof/` folder or a website link showing the link between the two games.
  Add this to the connection data and display it in-game when viewing a
  connection.
- **Unconnected games** — give a purpose to games that have no influence edge
  into the current path (a mechanic, reward, or way to reach/use them).
- **Game-space statuses** — port the HTML system where map spaces carry
  statuses that trigger when landed on (e.g. Charmed, Devilish, Holy, Marked),
  from `game-statuses-data.js`.
- **More map movement** — give players more ways to move around the map:
  additional movement items and loot, a new movement mechanic, and/or
  movement-themed events.

Larger systems from the HTML build still to be ported (surfaced from a scan of
`legacy-web/`):

- **Dice tray & combat dice** — named die cards with face outcomes (the
  "slot items onto dice" feature), backed by the combat-**moves** vocabulary
  (`dice` / `moves` sheets, `dice-data.js`, `moves-data.js`). First dice items
  (D6, Wooden Nickel) have landed; the full dice tray + face authoring is still
  ahead.
- **Allies** — heroes that provide dice in combat (`allies-data.js`), tied to
  the dice system above.
- **Bingo** — the 3×3 bingo-goal grid with progressive item-choice rewards
  (`bingo.js`).

All of the above are driven by `tools/Roguelikes.xlsx`, so porting each is
largely a matter of adding the matching Resource schema in `scripts/resources/`,
a generator in `tools/`, and the UI.

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
