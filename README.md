# Roguelike-like (Godot 4)

A roguelike **played on a graph of real video games**. Every node on the map is a
real roguelike, joined to the games it influenced. A run walks that graph from a
start game to the **Amulet** game. The "combat" is going off and actually playing
each game, then reporting back on the honour system. Each game you take puts
**enemies** on a board, and every enemy is a **goal** to accomplish inside the
real game. Clear a goal and the enemy drops loot. Leave it and it follows you,
walking closer with every run of a real game you lose. Reach and beat the Amulet
to win; run out of Health to lose.

It is built **stream-first**: for most of a stream the game window isn't on
screen at all, and an OBS overlay shows the audience the run, the goals and what
a lost run will cost. A run is meant to last a day or two of streaming.

> **New here?** Read [`docs/rules.md`](docs/rules.md), the rules as a player
> sees them, then open the folder in Godot 4.6 and press play.

---

## A run, in brief

1. **Pick a character.** They set your Health, starting charges and kit, and a
   level-up goal you can meet at any game.
2. **Pick a start.** Three games, 4–8 games from the Amulet, which is named on
   the panel. The one you take is the run's first game.
3. **Play it.** Each game is a node of one of four **kinds**:
   - `!` Enemies: two bodies, each a goal.
   - `!!` Champion: a boss.
   - `?` Event: an event before you play.
   - `$` Shop: a shelf after you win.
   
   Ticking a goal resolves it on the spot. Each lost run of the real game gives
   the board a turn. After three losses (one at a Traditional roguelike), you
   can escape at a price.
4. **Report it.** You get chests sized by what you killed, loot off the floor,
   gold, maybe a level-up and an event. Then the end of the game stands more
   bodies up, more the nearer the Amulet you are.
5. **Choose the next game** from the ones connected to where you stand, with
   Bash, Dash, Transmute and Scramble to reshape the offering. Repeat until the
   Amulet or zero Health.
6. **End each stream by making camp**: rest for Health, or take what one of the
   session's games taught you.

Above a won run sit **Fractures**, ten harder levels unlocked per character.
Across runs, every game and character **ranks up**, and each rank unlocks a song
from that game on **Roguelike Radio**.

## What's in the build

As of 20 Oct 2026. Counts are measured from `data/`; run `ls data/<folder> | grep -c tres`
rather than trusting them later.

| Area | What there is |
|---|---|
| **The map** | 927 real games (586 owned), the influence graph between them, rifts that pull off-map games in, and an Atlas star chart of the whole catalogue |
| **Characters** | 12, each with a level-up goal; Mysterious Mask adds a second |
| **Enemies** | 66 goal-enemies and 50 bosses (some with phases) across four game types, 31 abilities, 7 statuses, tile effects and units on the board |
| **Things you carry** | 77 relics, plus eight kinds of loot in a shaped pack: 9 scrolls, 10 pills and 15 potions (each identified per run), 37 cards, 12 wands, 22 trinkets, 5 bags, 11 weapons with 6 evolutions |
| **Between games** | 16 events, 2 machines, 3 curse goals, Shop nodes with 4 shopkeepers, and the end-of-session Camp |
| **Difficulty** | Amulet pressure, a tier ladder stepped by spawns, boss capstones, Fractures 1–10 and Fracture 10's Collapse (carry the Amulet home) |
| **Across runs** | Profiles, game and character ranks, the Collection, a tier list, notes per goal, Run History, custom runs with seeds |
| **Streaming** | The OBS overlay (eight browser sources), a speedrun clock, and Roguelike Radio (1,933 songs on the sheet, the player's own audio) |

## Getting started

1. Install **Godot 4.6** (Forward+): <https://godotengine.org/download>.
2. Open this folder in Godot (select `project.godot`). The first open builds the
   import cache in `.godot/` (gitignored), which takes a moment.
3. Press **F5**. The game boots into `res://scenes/menu/MainMenu.tscn`.

**For streaming,** set up the overlay with
[`docs/streaming.md`](docs/streaming.md), and the radio with
[`docs/roguelike-radio.md`](docs/roguelike-radio.md) §7.

### Running the tests

The tests use [GUT](https://github.com/bitwes/Gut) (bundled in `addons/gut/`):
64 scripts and about 3,100 tests in `test/`.

```bash
tools/gut.sh test_gameloop2            # one file, seconds
tools/gut.sh test_overworld2 escape    # the tests in it whose name contains "escape"
tools/gut.sh                           # the whole suite, ~25 min
```

Use `tools/gut.sh` rather than `-gtest=` on its own, which silently runs
everything (CLAUDE.md explains why). CI (`.github/workflows/ci.yml`) runs three
jobs:
- **GUT**
- **the content pipeline:** `check_doc_paths`, `apply_goals_sheet --check`,
  `check_data_sync`, `check_map_sync`
- **the overlay page:** `node tools/check_overlay.js`

---

## Repository layout

The repository root **is** the Godot project, so `res://x` is `./x`.

```
.
├── project.godot           # the project: 29 autoloads, display, input
├── README.md               # this page
├── CHANGELOG.md            # what changed and why, newest first
├── CLAUDE.md               # orientation for coding agents
│
├── scenes/
│   ├── menu/MainMenu.tscn            # the boot scene (laid out in the editor)
│   └── redesign2/Overworld2.tscn     # the game: one node + a script; all UI is built in code
│
├── scripts/
│   ├── autoload/    # the 29 singletons: GameState, Data, GameLoop2, EventSystem, …
│   ├── redesign2/   # the run's screens: Overworld2, BattlefieldView, ReportChecklist,
│   │                #   GameChoiceModal, PostCombatScreen, the loot pack, the shop, …
│   ├── menu/        # MainMenu, CharacterPicker, StartPicker, CustomRunScreen, ProfilePicker
│   ├── ui/          # shared UI: UITheme, Collection, AtlasView, HowToPlay*, Radio*, Rank*, …
│   ├── runtime/     # rules that aren't screens: RunGraph, Fracture, GameRanks, LootPassives, …
│   ├── resources/   # the Resource schemas every .tres is typed by
│   └── data/        # generated catalogues (ReferenceCatalog.gd)
│
├── data/            # all content as .tres, generated from the spreadsheet:
│                    #   games/ (927), enemies2.0/, bosses2.0/, characters2.0/, items2.0/,
│                    #   abilities2.0/, statuses2.0/, tiles2.0/, units2.0/, events2.0/,
│                    #   objects2.0/, curses2.0/, the loot kinds (scrolls2.0/, pills2.0/,
│                    #   potions2.0/, cards2.0/, wands2.0/, trinkets2.0/, bags2.0/,
│                    #   weapons2.0/, evolutions2.0/), shopkeepers/, songs/, stats/,
│                    #   atlas_layout*.tres; plus the pre-2.0 items/, characters/, curses/
│
├── images2.0/       # all games-first art, one folder per kind; proof/ holds the
│                    #   connection proof clips (.ogv + poster)
├── images/          # surviving pre-2.0 art
├── fonts/           # subsetted Noto symbol fonts for the UI's glyphs
├── shaders/         # rift_swirl
├── obs/             # the OBS overlay page (html/css/js), installed to user://obs/ at boot
│
├── tools/           # Roguelikes.xlsx (the design source of truth), the generators and
│                    #   importers, the checks CI runs, research tooling, gut.sh
├── research/        # research candidates per kind (CSV), the ledger, each game's wiki
├── test/            # GUT suites (test_*.gd) and shared helpers in test/helpers/
├── docs/            # design docs for the current build (see below); docs/archive/ is
│                    #   the combat era, kept for reference
├── addons/gut/      # the test framework
├── .claude/         # session hook, and the verify skill (screenshots of real scenes)
├── .github/         # CI
└── legacy-web/      # the retired HTML/JS version, reference only
```

---

## Documentation

**Start with the first three.** Every other doc is about one system.

| You want | Read |
|---|---|
| **The rules, as a player sees them** | [`docs/rules.md`](docs/rules.md), generated from the in-game 📖 How to Play |
| **Why every rule is the way it is** | [`docs/games-first-redesign.md`](docs/games-first-redesign.md), the canonical spec (`§N` everywhere refers to it) |
| **How the code is put together** | [`docs/architecture.md`](docs/architecture.md): autoloads, every screen, the window, data loading, Luck, conventions |
| Streaming: overlay set-up, scene layouts, the clock | [`docs/streaming.md`](docs/streaming.md) |
| Adding content: art, the spreadsheet, generators, events, objects | [`docs/content-authoring.md`](docs/content-authoring.md), plus [`event-sheet-authoring.md`](docs/event-sheet-authoring.md), [`object-sheet-authoring.md`](docs/object-sheet-authoring.md), [`item-sheet-authoring.md`](docs/item-sheet-authoring.md), [`sheet-authoring-handoff.md`](docs/sheet-authoring-handoff.md) |
| Loot: trinkets, bags, weapons, evolutions, the pack's neighbour rules | [`docs/loot-passives.md`](docs/loot-passives.md), [`cards-design.md`](docs/cards-design.md), [`potions-design.md`](docs/potions-design.md), [`wands-design.md`](docs/wands-design.md) |
| Difficulty above a won run | [`docs/fracture-design.md`](docs/fracture-design.md) |
| Rifts: off-map games pulled into the map | [`docs/rifts-design.md`](docs/rifts-design.md) |
| Roguelike Radio | [`docs/roguelike-radio.md`](docs/roguelike-radio.md) |
| The end-of-session Camp | [`docs/rest-site-design.md`](docs/rest-site-design.md) |
| Locations: dealt at each difficulty up, what they do, the tag lean, the poops | [`docs/locations-design.md`](docs/locations-design.md) |
| Locations and events, the earlier brainstorm (its events half still argued from) | [`docs/locations-and-events-design.md`](docs/locations-and-events-design.md) |
| What fires first in a game: a lost run's turn, the report, kills and hits | [`docs/turn-order.md`](docs/turn-order.md), held to the code's order by `tools/check_turn_order.py` |
| Stats and how they resolve | [`docs/stat-dispatcher.md`](docs/stat-dispatcher.md) |
| The systems graph (what feeds what) | [`docs/systems-graph.md`](docs/systems-graph.md) |
| Research: influences, tags, and what each game could give this one | [`docs/research.md`](docs/research.md), [`influence-research.md`](docs/influence-research.md), [`influence-media.md`](docs/influence-media.md), [`map-organization-research.md`](docs/map-organization-research.md), [`goal-enemy-candidates.md`](docs/goal-enemy-candidates.md), [`proof-missing.md`](docs/proof-missing.md) |
| Known-slow code, layout decisions, flaky tests | [`docs/performance-backlog.md`](docs/performance-backlog.md), [`layout-review-backlog.md`](docs/layout-review-backlog.md), [`test-flakes.md`](docs/test-flakes.md) |
| What changed and why | [`CHANGELOG.md`](CHANGELOG.md) |

---

## Roadmap

The core loop, node kinds, shops, events and objects, all eight loot kinds,
enemy abilities, bosses with phases, Fractures, rifts, ranks, the radio, the
Camp, Run History and the overlay are built. What is still ahead:

- **The Camp's next steps** ([`docs/rest-site-design.md`](docs/rest-site-design.md)
  §5): the last camp on the overlay, a game's own camp card, and what a session
  that ends mid-game gets.
- **Chat interaction**: ideas are being collected and parked until the audience
  is big enough to use them.
- **Keys, locked paths and the Fog scroll** are deferred by decision (spec §4).
  No content grants keys, and no edge is gated.
- **Tags and path requirements** (spec §6.2): let an edge demand a type or tag
  ("this route needs a Deckbuilder clear"), so routing becomes a collection
  puzzle as well as a shortest path.
- **Goals that fit the game.** Enemies roll by game type and tier, not by
  whether the particular game can host the goal; the tags being researched per
  game could gate them.
- **Game-space statuses**: the HTML build's map-space statuses (Charmed,
  Devilish, Holy, Marked) that trigger on landing.
- **Content depth**: more curses (3), machines (2), tile effects (2) and
  Traditional enemies (7, against 26 Action). All of it comes from the sheet.

---

## Conventions

- **The repo tracks source only.** `.godot/`, `*.import`, `*.uid` and
  `export_presets.cfg` are gitignored and regenerate.
- **Content is data, never code**, and the spreadsheet is upstream of `data/`.
  Edit `tools/Roguelikes.xlsx` and regenerate; never hand-edit generated `.tres`
  in bulk. See [`docs/content-authoring.md`](docs/content-authoring.md).
- **Art filenames are PascalCase**, matched to content ids by convention.
- **Font sizes, gaps and CanvasLayer numbers come from `UITheme`'s scales**, and
  `test_design_tokens.gd` fails a bare integer
  ([`docs/architecture.md`](docs/architecture.md#conventions)).
- **The docs are the navigation layer.** `python3 tools/check_doc_paths.py`
  fails on a path in a live doc that doesn't exist. `docs/rules.md` is
  generated; `test_rules_doc.gd` fails when it is stale.

---

## `legacy-web/` — the old HTML version

The original browser build (~42k lines of vanilla JavaScript) is superseded by
the Godot project and kept in `legacy-web/` for reference and parity checks. It
still runs: double-click `legacy-web/index.html`. Its art comes through the
`legacy-web/images` symlink to the root `images/`, and `legacy-web/.gdignore`
keeps Godot from importing that art a second time.
