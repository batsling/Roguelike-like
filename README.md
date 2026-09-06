# Roguelike-like (Godot 4)

A roguelike **played on a graph of real video games**. Every node on the map is an
actual game connected to others it influenced; each run is a journey from a
randomly chosen **Start** game to a hidden **Amulet** game, and the "combat" is
you going off and actually playing each game to clear its goal — reported back on
the honour system, with defeated goal-enemies dropping loot where they fall and
paying out a chest of relics on the game you beat them in.

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
├── docs/performance-backlog.md  # Measured slow paths not yet fixed, with the fix for each
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
│   │                      #     PackStrip       — fills Overworld2's pack strip
│   │                      #     DropQueue       — everything the run pays out and
│   │                      #                       the order it is asked about (§8)
│   │                      #     LootWindow      — the 3x3 loot grid, floated over
│   │                      #                       the board by its toggle
│   │                      #     LootGrid/LootSlot — that 3x3 itself: drag a cell
│   │                      #                       into any slot, drag a drop into one
│   │                      #     LootTrash       — the red bin both surfaces draw
│   │                      #     LootDiscoveries — "Known this run", on both too
│   │                      #     ReportChecklist — its left column, both states
│   │                      #     CompletedGoalsPanel — the ✓ record that column opens
│   │                      #     OfferingCards   — its choice cards + hover line
│   │                      #     BattlefieldView — the grid the enemies close in on
│   │                      #     EnemyInfoCard   — click-to-inspect enemy card
│   │                      #     ItemInfoCard    — click-to-inspect item card
│   │                      #     GameChoiceModal — the popup an offered card opens
│   │                      #     ShopPanel2      — a hub's shop, mounted under the board
│   │                      #     ObjectPanel2    — the machines standing here, same place
│   │                      #     ObjectCard      — one machine, in the panel or in an event
│   │                      #     BossNoticeModal — the "⚠ BOSS INCOMING" popup
│   │                      #     RouteLadder     — the arrowed shortest-path graph
│   │                      #     RunOverScreen   — the end-of-run verdict screen
│   │                      #     LootDropModal   — "the game paid out, keep it?"
│   │                      #     RunMapModal / LootUseModal
│   ├── events/           #   the D20 event system (EventModal, D20DieView)
│   ├── menu/             #   the main menu + CustomRunScreen (the custom run's setup)
│   ├── runtime/          #   RunGraph — the real-games influence graph
│   └── ui/               #   shared UI (UITheme, RewardScreen, Collection, toasts)
│                          #     AtlasView + AtlasLayoutBuilder — the star chart
│                          #     and the runtime layout behind its filters
│
├── data/                  # Game content as Godot Resources (.tres) — the source
│   │                      # of truth the game loads at startup (see Data.gd)
│   ├── games/            #   GameData — the ~857 real games that form the map
│   ├── atlas_layout*.tres#   BAKED star positions for the Atlas, one sky per game
│   │                      #   filter: all / _owned / _downloaded (tools/bake_atlas.py)
│   ├── items2.0/         #   ItemData — the relics a beaten game's chest offers
│   │                      #   (Rating Boss / Event = a relic only a boss or an
│   │                      #   event pays; never in a random pool)
│   ├── enemies2.0/       #   GoalEnemyData — goal-enemies, one per game beaten
│   ├── bosses2.0/        #   GoalEnemyData — the difficulty-gate bosses
│   ├── characters2.0/    #   CharacterData — the playable roster
│   ├── scrolls2.0/       #   ScrollData — identify-by-reading scrolls
│   ├── scroll_names.tres #   ScrollNames — the bag of meaningless titles an
│   │                     #   unread scroll wears ("ZELGO MER", "ah bloto festr");
│   │                     #   a run deals one per scroll and redeals every run
│   ├── pills2.0/         #   PillData — identify-by-taking pills, two doses each
│   │                     #   (the horse dose is a 5% roll on the drop, §4.3)
│   ├── potions2.0/       #   PotionData — identify-by-using potions, two VERBS
│   │                     #   each: quaff it, or throw it at a cell
│   │                     #   (docs/potions-design.md)
│   ├── wands2.0/         #   WandData — identify-by-zapping wands, and the one
│   │                     #   kind that is NOT spent in one use: 4-6 charges each,
│   │                     #   a slot held until it is empty (docs/wands-design.md)
│   ├── statuses2.0/      #   StatusData — clauses bolted onto goals, plus the
│   │                     #   combat side they move numbers with (§13, §13.4).
│   │                     #   Stun lives here now: the board keeps no counter of
│   │                     #   its own, so everything that stuns is one status
│   ├── tiles2.0/         #   TileEffectData — what sits on one CELL of the board
│   │                     #   and bites whatever walks in (§17)
│   ├── units2.0/         #   UnitData — the player's own bodies on the board
│   │                     #   (the Landmine), which layer on top of a tile (§17)
│   ├── abilities2.0/     #   AbilityData — the CATALOGUE of enemy abilities: name,
│   │                     #   type, argument shape and sentence (§7.6). What each
│   │                     #   one DOES is GameLoop2, not a .tres
│   ├── events2.0/        #   EventData2 — one fires after every game played
│   ├── objects2.0/       #   ObjectData — the machines you stand in front of (§15)
│   ├── curses2.0/        #   CurseData2 — the checklist curses events hand out
│   ├── items/            #   ItemData (pre-2.0 set, still loaded)
│   ├── characters/       #   CharacterData (pre-2.0)
│   ├── curses/           #   CurseData (shelved, kept — §5)
│   └── stats/            #   StatDefinition (the stat dispatcher's vocabulary)
│
├── fonts/                 # ★ Subsetted Noto symbol fonts (OFL) — the ~70 glyphs the UI
│                          #   draws, shipped so they don't cost a host font search each
│                          #   time a Label is made. Built by tools/build_glyph_font.py
├── images2.0/             # ★ Games-first art — covers, items, enemies, bosses, characters,
│                          #   scrolls, pills, and 37 potion vials + 9 identified bottles
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
│   ├── generate_pill2_tres.py      #   data/pills2.0
│   ├── generate_potion2_tres.py    #   data/potions2.0
│   ├── generate_wand2_tres.py      #   data/wands2.0
│   ├── generate_status_tres.py     #   data/statuses2.0 (owns the reward-token DSL)
│   ├── generate_tile_tres.py       #   data/tiles2.0 (owns the tile/unit trigger DSL)
│   ├── generate_unit_tres.py       #   data/units2.0 (imports the parsers above)
│   ├── generate_ability_tres.py    #   data/abilities2.0 (owns the Ability-column grammar)
│   ├── generate_event2_tres.py     #   data/events2.0
│   ├── generate_curse2_tres.py     #   data/curses2.0
│   ├── _xlsx_surgery.py            #   edit one sheet without losing the charts
│   ├── audit_systems_graph.py      #   read-only audit of the `chart` sheet (systems graph)
│   ├── _chart_system_vocabulary.py #   one-shot: settle the chart sheet's System vocabulary
│   ├── _chart_abilities_review_fixes.py #  one-shot: the ability-review fixes
│   ├── _chart_summoners_and_tiles.py #  one-shot: summoner payouts + the tile rules
│   ├── _chart_enemy_goals.py       #   one-shot: enemy goals — the central loop
│   ├── generate_item_tres.py, generate_character_tres.py,
│   ├── generate_curse_tres.py      #   the pre-2.0 sets
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
   | `images2.0/pills/` | Pill capsules — 13 colours, each with a `<Colour>Horse.png` twin. Bound to pills by the RUN, not by a `.tres` (`PillSystem.COLORS`), so adding art means adding its name to that list too |
   | `images2.0/statuses/` | Status art (`data/statuses2.0`) |
   | `images2.0/tiles/` | Tile-effect art (`data/tiles2.0`) |
   | `images2.0/units/` | Unit art (`data/units2.0`) |
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
| `EventSystem` | Events (`docs/event-sheet-authoring.md`): dealing an event from the per-rarity shuffle bag when a game is played, the Requirement/`needs` gates, and resolving a choice into effects, an event goal, a curse, or a `chance` roll. Objects go through the same resolution. |
| `ObjectSystem` | Objects (`docs/object-sheet-authoring.md`): the machines standing in front of the player, spawning them by tag, and their state — jams, what has been blown off the run, and the Donation Machine's cross-run bank. |
| `GameLoop2` | The run loop: the games-beaten clock, the enemy stack, and the grid the followers advance across. Committing to a game spawns **two** bodies — the one the card advertised and an **escort** rolled from the same pool (§7.5), boss rounds included. **Neither belongs to the game.** There is no "this game's enemy": what walks on is a follower like every other body from the moment it lands — bombable, pushable, one ordinary row in the report checklist — and `arrivals` is only the record of which bodies came with the game in play, kept so a Scramble can supersede them. `Overworld2` is a view over it. It also owns what every **ability** does (§7.6) — the catalogue is `data/abilities2.0`, but the turn resolver, the mover, the spawner and the death path are all here, which is why they are one file's business and not a per-row effect string. |
| `ShopSystem` | Shops (`docs/games-first-redesign.md` §14): which games are the run's ten hubs, each shop's three-item shelf and its prices, buying, and the Scramble reroll. State lives on `GameState` (`hub_games` / `shops`), the same split `EventSystem` uses. |
| `ObsCompanion` | The **stream overlay** (`docs/games-first-redesign.md` §9). Mirrors the run to `user://obs/` for an OBS **Browser Source** — no server, no port: the state is written as `state.js` (`window.OBS_STATE = {…}`), because a `file://` page may *load* a sibling as a script where it may not `fetch()` one. Registered **last** among the autoloads and a pure reader of the rest. Writes are debounced to 4/sec and deduped on content, over a 5-second heartbeat that lets the page tell "the run has not moved" from "the game is not running". The page itself lives in `obs/` and is reinstalled at every boot; `user://obs/custom.css` is the seam left alone for the streamer. See "The stream overlay" below. |
| `ScrollSystem` | Scroll identification + reading (the unidentified-loot gamble). |
| `PillSystem` | Pills (`docs/games-first-redesign.md` §4.3): the per-run deal of 10 of the 13 capsule colours (three mean nothing, so the tenth pill can't be deduced), the 5% horse-dose roll on a drop, colour-scoped identification — either dose teaches both — and the ops a dose runs. Bad Trip names itself from your Health: at or below its own damage it heals to full and reads "Full Health" while that is true. |
| `PotionSystem` | Potions (`docs/potions-design.md`): the per-run deal of 15 of the 37 vials (22 mean nothing, which is what stops the fifteenth being deducible — and the deal is by COLOUR NAME, since Golden and Magenta each ship twice and an unknown bottle introduces itself by its colour), type-scoped identification that covers BOTH verbs at once, the art fallback for the six potions with no bottle of their own, and the two verbs themselves: `quaff_potion` applies the sheet's `On Player` side to the drinker, `throw_potion` takes an aimed cell in `ctx.target` and applies the `On Tile` side around it. The shapes an `area=` token names are the BOARD's (`GameLoop2.area_cells`); Sacred Bark widens one by a rung of `AREA_LADDER` rather than by a multiplier, because a grid has no way to be exactly twice as big. |
| `CardSystem` | Cards (`docs/cards-design.md`): the fourth loot consumable and the one that is **not a gamble** — no identification, no Preference, one use, what it does printed on it. What a card withholds is *which* card it is, and only while it is lying on a battlefield square: the floor draws its DECK'S icon (five icons over thirteen cards) and the hover names the deck and stops, and it turns over for good when it is picked up. That side is `LootSystem.art_texture(entry, face_up)`, false at three call sites and true everywhere else — "face down" is a fact about where the card is, not about the card. Owns the roster's ops too: the three teleports and the ? Card copy resolve as REQUESTS the overworld fulfils, and Temperance's `spawn_object` puts a named machine under the board through `ObjectSystem`. |
| `WandSystem` | Wands (`docs/wands-design.md`): the fifth loot consumable and the only one **not spent in a single use**. Every row authors 1-4 charges; zapping one spends a charge and leaves the wand in its slot, and only the last charge takes the wand with it. The per-run deal is 12 of 28 materials (16 mean nothing, which is what keeps the twelfth wand undeducible), and one zap identifies the type and **every charge behind it**. Eight of the twelve aim at a **Unit** — an enemy, a boss, or one of the player's own bodies (§17) — through the six verbs in `GameLoop2`'s wand-verbs block (`kill_instance`, `cancel_abilities`, `grant_ability`, `split_unit`, `polymorph_instance`, `teleport_unit`), all resolved by one `WandSystem._zap_unit`. A boss is a Unit like any other here, held in place by the one rule that keeps it a boss: **only its goal takes its last point of Health**, and Wand of Death is the single authored exception. The `Type` column is what it wants pointed at it — `ray` takes an aimed cell in `ctx.target`, `non_directional` fires where it stands, and `random` rolls one of the two afresh every zap, which is Wand of Nothing's whole disguise. An UNIDENTIFIED wand always asks for a square whatever its type, or the aiming step would leak which half of the roster it is in — and for the same reason it does **not say how many charges it has**: the count is the rarity ladder read a second way (one on each Legendary, three or four on the Commons), so `LootSystem.charges_known` gates every surface that draws it while `LootSystem.charges` stays the unconditional mechanical answer. |
| `LootSystem` | The one place a piece of carried loot is SPENT. Each kind owns its own resolution; what they share is everything around a use — consuming the entry, **Echo Chamber**'s copies of the last three used, and the memory they read (`GameState.loot_used_memory`). It belongs to neither system because an echo of a pill can be a scroll. Isaac's ordering: the copies fire off the memory as it stood *before* this use, so nothing echoes itself and no echo is remembered. **A wand is outside all of it in both directions**: it never joins the memory and zapping one fires no copies, because the relic copies pieces that were *consumed* and a wand that could pay it six times per slot would be worth more than the relic. |
| `GameLog` | Verbose run-scope message log (teleports, pickups, item procs) — the written record behind the toasts. |
| `Notifications` | Curated player-facing "important events" channel; the overworld mounts `NotificationToasts` to show them. |
| `SaveSystem` | Save/load for a games-first run (`user://`): a named save per run plus the run's own autosave slot. Writes GameState, `GameLoop2`, and the overworld's on-screen state, and hands a loaded run back to the next `Overworld2` to boot. |
| `Profiles` | **Save profiles** — separate players on one install. Owns the profile list (`user://profiles.cfg`) and the active one's directory (`user://profiles/<id>/`), which is where runs, stats, the tier list, ownership and the run-shaping prefs all live; every store asks `Profiles.path()` rather than naming a `user://` path itself. `switch_to()` flushes the profile being left and reloads all of them, then emits `profile_switched`. Window mode / size / dev mode stay **global** in `user://settings.cfg` — they describe the machine, not the player. An install that predates profiles is migrated into its first profile on boot. |
| `Settings` | Preferences, split by the profile line: **global** (window mode, window size, dev mode) in `user://settings.cfg`, **per-profile** (path filter, amulet rule, transmute rule) in the profile's own `prefs.cfg`. |
| `Ownership` | Which real games the player owns, and where that answer comes from: the catalog's shipped `GameData.owned` column, or **the player's own list**, built by ticking the mark at the top-left of a game's cover in the Collection. `Ownership.is_owned(game)` is the single read; every owned filter, the atlas's owned rings and the settings counts go through it, and the `.tres` column is never written to. Per-profile, in the active profile's `ownership.cfg`. There is deliberately **no Steam sync** — see the note at the top of `Ownership.gd` for what was tried and why it cannot work. |
| `RunConfig` | A **custom run**'s setup, held for the run it configures: three independent filters (**map** / **start** / **amulet**, each with library, genre, record and release-year axes), the run-length band, and an optional named target game. Off by default, in which case `RunGraph` reads `Settings.game_filter` exactly as before. Written by `CustomRunScreen`, read by `RunGraph`, and saved with the run — the filters *are* the map, so a save resumed without them comes back on a different one. `RunConfig.describe()` is what the menu's Continue list prints on a custom run's row, read off that save's own stored block rather than off the loaded run. |
| `TierList` | Cross-run tier list / ranking store that outlives any single run. |
| `GameStats` | Cross-run lifetime per-game play stats (games beaten / verified), plus the Donation Machine's bank — the one number in the build that deliberately outlives a run. |
| `DevTools` | Developer panel (press `` ` ``), gated on `Settings.dev_mode`. Five tabs: **Grant** (items / scrolls / pills / statuses, with a player-or-enemy target picker — the item list is `DevTools.item_pool()`, the **2.0 set only**: it used to append the 112 combat-era relics from `data/items`, which grant cleanly and then do nothing because no games-first code honours them), **Run** (vitals, every board verb, gold, chests, level, games played), **Board** (spawn a goal-enemy or boss; stun / push / bomb / defeat / remove or status any standing body), **Flow** (jump to a game, heal, clear the board, force the win or loss), **Events** (start any authored event where you stand and read the state of the shuffle bag, each row saying why it is or isn't turning up on its own — see [Authoring an event](#authoring-an-event); the same tab spawns any **object** under the board, which is the only way to reach the non-event half of how a machine appears). Everything routes through the same public API the game uses. |

### Screens & flow

There are only two scenes. `MainMenu.tscn` boots the game and hands off to
`Overworld2.tscn`, which **is** the game — the simulated combat modes were cut in
the games-first redesign (§11), so the real video game you go and play is the
combat. Every screen is built in code, so the scene files hold nothing but a root
node and its script.

- **`MainMenu.gd`** — new run, character select, the **Continue** list of saved
  runs, the Collection, the tier list, Settings, and **Exit Game**. Quitting from
  here doesn't confirm: nothing is live on the menu and the saves are already on
  disk, so a prompt between the player and the door only ever gets in the way.
  **Exit Game is a MAIN MENU button and only works on the main menu.** It is
  moved to the bottom-right corner in code (`_move_quit_to_corner`), and that
  used to append it *last* — above `%ModalLayer`, where every screen the menu
  raises mounts — so the door out of the application sat on top of the character
  picker, the Collection and the Atlas, live and clickable through their own
  backdrops. The corner is mounted under the modal layer now.
  - **`Collection.gd`** — the compendium: Games, Items, Characters, Enemies,
    Bosses, **Loot**, Events, Objects. It is also **the only door onto the Atlas
    that is always open** — the Games tab's *✦ Show constellation* draws the same
    catalog as the star chart, which is why the main menu no longer carries an
    Atlas button of its own (Run History still lays its routes over the sky).
    Enemies and Bosses sort by A-Z, Tier, Damage and **Ability** — an ability is
    the one thing about a body that isn't a number, and it is what the roster is
    browsed for. **Loot is one tab with four sub-tabs** —
    Scrolls, Pills, Potions and Cards — because they are one thing to the run: one
    four-way payout, one nine-piece pack, one window, and four top-level tabs
    would say the opposite. **A potion's cell shows its identified art and both
    verbs**, which is the one place this tab does not draw a stand-in: a pill's
    picture is the colour the run deals it, but what a potion looks like once you
    know it is a fact about the potion rather than a per-run secret. **A card's
    cell shows BOTH SIDES** — its face and its deck icon — because the difference
    between them is the whole of what the kind withholds, and it is the one half of
    this tab that spoils nothing: a card is readable in a run the moment it is in
    the pack.
    Both halves are the **revealed reference**, which a run hides until you
    identify it. A pill cell wears a **stand-in capsule and says so**: a pill
    carries no art of its own (`PillData` has no image field) because its picture
    is the colour the run deals it out of `PillSystem.COLORS`, and this screen
    opens from the main menu where no run has dealt one — drawing each pill in
    some particular colour would teach an association the game randomises on
    purpose. It shows **both doses**, since the 5% horse roll is the same colour
    and the same identification, and a card showing only the normal one would be
    describing half of what taking it can do.
  - **`HowToPlayScreen.gd`** — **📖 How to Play**, the written manual: a chapter
    list down the left, one chapter down the right. Every word of it is data in
    **`HowToPlayText.gd`**, which the screen draws and does not read — so the
    text, which changes every time the build does, is edited without touching
    layout code. The manual's **numbers are interpolated from the constants that
    govern them** (`GameLoop2.SHIELDS_PER_GAME`, `RunDifficulty.bonus_turns_for_hops`,
    `ShopSystem.BASE_PRICE`, `RunGraph.NUM_HUBS` …), and `test_how_to_play.gd`
    asserts the prose still quotes them, so a balance change cannot leave the
    manual lying. The menu's **bottom-left corner is its table of contents** —
    built from the same array, opening chapters **by id** rather than by index.
  - **`CustomRunScreen.gd`** — **⚙ Custom Run**: build a run out of a chosen set of
    games. Three columns, because there are three independent questions — what
    **the map** is made of, which of those may be **the start**, and which may be
    **the amulet** — each with the same four axes (library, genre, record, release
    years) and a live count of the games that survive it. Under them, the run
    length (how many games from start to Amulet) and an optional **named target**,
    which composes with the band rather than overriding it. Begin hands the
    configuration to `RunConfig` and then opens the ordinary character picker, so
    a custom run is the normal flow with a screen in front of it.
- **`Overworld2.gd`** — the run itself: the opening choose-your-start panel (three
  games, three genres, all 5–7 games from the amulet — and the one you take is
  the run's first game, enemy and all), the offering of games
  (cover cards), and
  then a two-column stage — checklist on the left (the standing goals while you're
  choosing, the honour-system report step + attempt tracker while you're playing;
  most boxes on it are a **confirm** that resolves the row on the spot, mid-game,
  and lock — see spec §2.1. The exception is the **`On a winning run:`** section:
  the player's standing status goals and the character's level-up nest under one
  header there, and they ARM rather than resolve — the box goes on and off freely,
  there is no confirm, and handing the game in is what cashes it, because what
  they ask about is a run rather than the hour just spent. Their safeguard is on
  the **`✓ Completed Game`** confirm instead, which carries those rows again with
  the ticks as they stand and a **notes** field beside each: it is the moment
  that is final for them, and the only place their note can be asked for),
  the battlefield on the right with the player's pack (items **and** scrolls,
  one strip of tokens) above it. **The two halves point at each other**: hovering
  a goal row lights the body it belongs to on the board, and hovering a body
  lights its row — they are the same fact written twice, and nothing else answers
  "which of these lines is that thing" without reading names. Hosts the toast strip, so an item's effects
  announce themselves the moment it's picked up.

  **It fits one 1280×720 canvas, in every phase and at every board size**, with
  no horizontal scrollbar ever (the page's axis is `SHOW_NEVER` — still
  scrollable, never drawn) and no vertical one unless a run's checklist genuinely
  outgrows the page. That is the whole screen, not a small window:
  `window/stretch/mode="canvas_items"` scales that fixed canvas up to fill the
  display, so a 2560×1440 monitor draws this same page at 2×. Fitting the box is
  a constraint, not an accident, and the things below are what pay for it.

  **The Amulet is named from the first screen.** It used to be the run's one
  secret until a start had been committed to: the picker quoted the DISTANCE
  (`5 games from the Amulet`) and the maps drew the destination as an unnamed
  `The Amulet — ???` box that opened no card. All of that is gone. The picker's
  heading names it, each start card's distance line names it
  (`5 games from Guild of Dungeoneering`, via `Overworld2.amulet_name` /
  `_start_distance_text`), and the map a start card opens names it on its last
  rung. (That map is the ladder alone — the star chart stays down on the picker;
  see `RouteLadder.gd`.) Choosing a start is a routing decision, and
  the game the road ends on is half of what makes one road different from
  another.

  **And every card after the first says how far it is.** The distance used to be
  on the start cards and then nowhere: from the second choice on, a card said
  which *way* it went — the route badge, and only inside the popup it opened —
  but never how far there was left to go, which is the number the run is counting
  down. Each offered card now carries `N games away from the Amulet` in its own
  row, under the 🏆/🛒 flag and over the art, from
  `Overworld2.amulet_distance_text`; it says "the Amulet" rather than naming the
  game (the card is 150px wide, and the tooltip names it) and is blank on the
  Amulet's own card, where the flag a line above has already said it. The row is
  **paid for by merging the 🏆/🛒 flag and the ⚡ `+1 DASH` badge onto one line** —
  two stacked rows both blank on most cards — because the page's worst case (a
  hub's shop under the board) has about two spare pixels and a third row does not
  fit in them. The **hover
  line under the cards** names what is *waiting* there and not the game itself —
  the mouse is on that cover with its title printed under it, the line is one line
  wide, and the goal is the half that was getting truncated to pay for the repeat.

  **The header is the road you have walked, and it never leaves the screen.**
  Across the top, between the health and gold chips and the `☰ Menu`: the games
  played as small covers with arrows between them — the same picture the
  end-of-run screen draws, live, for the whole run. It is the only view of the run
  as a *journey*; the checklist says what you owe, the board says what is chasing
  you, and neither said where you have been. The title moved to the right to make
  room, which is also the honest ranking of the two. Covers are small and unnamed
  (the name is on the hover) because the strip shares its row with everything else
  and the page still has to fit 720; past `STRIP_MAX_STOPS` the oldest stops are
  dropped behind an ellipsis.

  Two rules about what is on it. It is **games played only** — it does not close
  on the Amulet, because the road ahead has two screens of its own (the 🗺 map and
  the route ladder) and a cover for a game you have never been to, drawn beside
  the ones you have, reads as the next stop. And it **keeps the repeats**: it
  draws `GameState.walked_path()`, the run's walk in order, rather than
  `visited_games`, which is a set and so showed a run that doubled back over a hub
  four times as one stop.

  The whole bar is mounted on a **`CanvasLayer` of its own** (`HEADER_LAYER`, 135)
  rather than being the first row of the scrolling page: it stays put when the
  player scrolls to the bottom of a tall board, and it floats above every modal
  the run raises — the event (123), the game-choice popup (124), the map (130) —
  which is exactly where Health is most worth reading. It sits *below* the
  end-of-run verdict (150), and it stands down while the tier-list board is up,
  since that one is a full screen with its own way out. The page is inset by the
  bar's height (`_fit_page_under_header`), so nothing is hidden underneath it.

  **And so is everything else on the screen.** The bar is opaque, so anything
  centred on the viewport loses its top row to it. `_fit_page_under_header`
  publishes the bar's height as **`ModalScaffold.reserved_top`**, and three
  things read it: `ModalScaffold.centre` centres a modal in the band *below* the
  bar and never lets its top edge start above it; the map window
  (`RunMapModal`) sizes, opens and clamps its drag inside that band; and
  **`AtlasView` offsets its whole page down by it**, so the chart's own header —
  which holds its search box, its ✦ jump buttons and the `←  Back to the run`
  button that is the only way off it — lands under the bar instead of beneath it.
  It is cleared when the page leaves the tree and while the bar is down, so the
  main menu's own screens are unaffected.

  **Where the numbers are.** There is **no HUD strip** — every number is drawn
  once, by whatever owns it:
  - **the player** (Health, Shields, statuses) is on the **board's hero**:
    `♥ hp/max` under the portrait, the shields over it — one **shield sprite**
    each (`images2.0/general/Shield.png`), the ones that stay nearest the
    portrait and bare, the Temporary Shields this game granted after them and
    each wearing the **clock badge** (`Timer.png`) — and status pips between.
    The clock is the run's one mark for "this is going away": every status pip
    drawn from a borrowed stack carries it too, on the board, on the enemy card
    and on the checklist (`UITheme.timed_art`). The **shields that stay** are the
    exception that proves it — they also ride the header's Health chip, as the
    same sprite with no clock on it, because that pool is gained off the board and
    has to be readable with no board on screen.
    A shield **breaks on screen**: during a resolve the row is the playback's
    rather than the run's (`_shields_shown`), and each blow the loop marked
    `blocked` swells and fades one sprite as its damage number lands — the
    Temporary ones first, which is the far end of the row.
  - **the board's verbs** are on the **board's own bars**: its pressure bar ends
    `▦ 4×4 · Low` (that's the tier) and its toolbar buttons read `⇤ Push (1)` /
    `✸ Bomb (3)`.
  - **the choosing verbs** — **Bash / Dash / Transmute / Scramble** — are chips on
    a row under the offering, since all four change what is on the table. **All
    four are buttons.** Dash and Scramble act on the offering as a whole and fire
    on the press; Bash and Transmute need a target, so pressing one *arms* it —
    the offering becomes a row of targets, drawn in the verb's colour, and the
    click on a card is what spends the charge (`Overworld2._armed_verb`). Arming
    is free and cancelling costs nothing; a refused aim (bashing the Amulet) says
    why and stays armed.
  - **the shields a game grants** ride the offering's one-line hover, which also
    carries the enemy's **portrait** — sized by the line rather than setting its
    height, so it costs the page nothing (`Overworld2.HOVER_ART`).
  - **everything else on the page describes itself on hover**, as a small themed
    card rather than Godot's grey tooltip — see "Hover cards" below.
  - **the pack has no heading.** A bordered strip of relic and scroll tiles is
    its own label, and that row is the page's whole margin against its 720p
    budget (with it, the page was already a pixel over before a shop mounted).
  - Keys and Chests aren't shown at all — Keys are deferred and unauthored, and a
    chest is redeemed the moment it lands.

  **The header is the title and one `☰ Menu`** (Save run / New run / Main menu /
  Exit game). Exit is the only entry that asks first, since a live run is
  standing behind it — and it asks the question that is actually open, offering
  **Save & exit** beside Exit and Cancel rather than a bare "are you sure".
  The 🗺 Map moved into the offering's own heading row, beside the cards it is a
  map of.
  - **`GameChoiceModal.gd`** — what clicking an offered card opens. A card is the
    cover, the name and the Amulet's flag; everything else about the decision
    lives here — the **optimal path from that game drawn as the real route
    ladder**, the enemy waiting there and its goal, the shields the game grants, the
    pace it puts the board on, your record in it — over the one button that
    answers it: **Travel**. (Bash and Transmute used to stand beside it and are
    armed from the offering's chips instead — this screen is about whether to go
    somewhere, not the place to bury two destructive verbs.) The cover is drawn
    small on purpose: it is the one thing you have already seen (it is what you
    clicked), and the room it gives back goes to the enemy and its goal. It decides
    nothing itself; every answer calls the overworld's `pick` / `bash_choice` /
    `transmute_choice`.
  - **`RouteLadder.gd`** — the shortest-path DAG as a top-to-bottom ladder of
    boxes with green arrows between them, colour-coded by role. Shared: the 🗺 map
    window (`RunMapModal`) and `GameChoiceModal` draw the same graph from it.
    Over the star chart the map window has **no Close of its own** — the chart
    owns the screen and its Close takes the window with it — so the button in its
    corner rolls it up to its title bar instead. Opened without a chart under it
    it is the only thing on screen, and there it keeps one — which is what the
    **start picker** gets: its 🗺 Map opens the ladder ALONE, no chart. The
    question on that panel is "which of these three roads", the ladder is the
    answer to it, and 852 stars with nothing on them to orient by (the run has no
    position yet) is not; the chart is one `✦ Star chart` button away on the
    window itself.
    **Every rung is named, the Amulet included**: the ladder used to draw the
    destination as `The Amulet — ???` on a start-picker map, and no longer does
    (see "The Amulet is named from the first screen" below).
  - **`HoverCard.gd` / `HoverPanel.gd` / `HoverBox.gd`** — the small themed card
    that appears when the mouse rests on something you could click to read in
    full. Four things open a card when clicked — an **enemy** on the board, a
    **status** on a body, an **item** in the pack, and the **enemy-turns**
    readout on the pressure bar — and all four used to spend their hover on
    `tooltip_text`: grey system chrome with a wall of plain text in it, on a page
    that is otherwise entirely hand-drawn. They carry a *condensed version of the
    card* now: the art, the name in the thing's own colour, its statuses as pips,
    and the one or two lines that actually decide something.
    `HoverCard.attach(node, {...})` stores the model and seeds the plain
    fallback; the node has to be a `HoverPanel` (a PanelContainer) or a
    `HoverBox` (a VBoxContainer), or define the two-line
    `_make_custom_tooltip` override itself, because Godot only calls that on a
    Control's own script. A status's model comes from `StatusData.hover_card`,
    beside the string it replaces, so the board, the enemy card and the hero
    strip cannot describe the same status differently.
    **The offering is the one thing that gets none** — no card and no tooltip:
    the hover line under the cards already says what is waiting, and a popup over
    three covers being scanned is the noisiest possible way to repeat it.
  - **`BattlefieldView.gd`** — the board: the hero on the left with the shield
    pips over them, the grid the goal-enemies close in across, the off-field lane,
    the Push / Bomb toolbar, and the strike / advance animation. **Both verbs are
    armed then aimed**, and neither spends anything until the aiming click.
    Pressing `⇤ Push` arms it, clicking an enemy picks the body, and an arrow
    appears on every side of it a shove could legally land on — back, forward, or
    up/down, which is the only lane change on the board; the arrow is what
    spends. Pressing `✸ Bomb` arms it and the **click on a body is what fires
    it**, since a bomb has no direction to pick. Arming either puts the other
    away. Bomb used to go off on the button press, at whatever was still
    selected — routinely a body clicked several turns earlier to read its card,
    so the charge went into an enemy the player was not looking at.
    **The instruction is the board, not a caption**: arming lights every body the
    verb could land on (`armed_targets` / `ARMED_TINT`) and the toolbar stops
    printing "click an enemy" — a verb that has to caption its own highlight is a
    highlight that isn't working. **The enemy of the game you are
    playing stands on the board with the rest** (§7.2), drawn on a washed fill so
    it is tellable from its neighbours; the off-field lane is for bodies with
    nowhere to stand. Nothing is drawn over the top of a body — the boss skull and
    the "in 2" that used to be there covered the picture that identifies it.
  - **`EnemyInfoCard.gd`** — the click-to-inspect card for one enemy.
  - **`ShopPanel2.gd`** — a hub's shop (§14), mounted **under the battlefield** on
    the page rather than opened over it: it blocks nothing, stays for the whole
    visit, and travelling on is what closes it. The overworld floats a
    `🛒 Shop ↓` pointer at the foot of the screen until it has been scrolled to.
    The shelf is drawn as **one row per item** — thumbnail, name, price — with
    the full card and its Buy button opening over the page on click. Three cards
    on the page ran the overworld to 1231px inside a 688px window; the page is a
    fixed 1280x720 canvas that `stretch/mode` scales into any window, so there is
    no monitor big enough to buy that space back. `ObjectPanel2` draws machines
    the same way for the same reason, and the board shrinks to a tighter height
    budget (`BattlefieldView.set_sharing_column`) while either is under it.
  - **`BossNoticeModal.gd`** — the "⚠ BOSS INCOMING" popup (§7.1), opened once per
    boss round. It replaced a banner strip that shoved the whole page down. Its
    boss portraits are **clickable**: each opens the ordinary `EnemyInfoCard` over
    the popup, read-only (no body exists yet, so no Push / Bomb), which is where
    "what does it want and what does it hit for" gets answered.
  - **`PostCombatScreen.gd`** — **the screen a game ends on** (§18). A report used
    to fire six independent surfaces — one relic modal per defeated body, the loot
    payout, the event, the shop appearing under the board, the boss notice, toasts
    under all of it — and the first two of those opened **on top of the resolve
    animation**, which is the one place the run's consequences are ever shown. The
    haul is one screen now, and it opens when the board has stopped moving: the
    verdict, the fight in numbers (out of `beat_game`'s result, which used to be
    thrown away), **every** relic chest down the left and the loot payout down the
    right at once, and the boss warning as a banner. All the
    chests together is the point: a queue hides what the *other* relics are, and
    there is often an order worth taking them in. A chest banked while the screen
    is up lands on it too (`add_chest`) rather than opening a `RewardScreen`
    underneath it. **The payout does not close on its last piece
    and has no Take/Leave buttons**: the piece has just gone into the pack, and the
    pack is the reason to still be looking.
    **★ Rate this game sits beside the cover**, and nowhere else in the run — it
    was on the play panel's checklist, which offered the score while the game was
    still in front of you. It saves and stays put rather than opening the
    tier-list board over a haul nobody has finished taking.
    **The chest shows the sum that sized it** (`chest_terms`): 🏆 +1, then a face
    per body with its own difficulty as its value, `=` the chest. Read off
    `GameLoop2.chest_point_breakdown()`, banked at each kill and claimed before
    the pool is spent — *not* re-derived from the report's defeat list, which
    misses a body a mine killed during a lost run.
    **One button out, and it names where it goes**: "Go to Event" when the node
    owes one (clicking it is what opens the event), "Go to Shop" at a hub that
    owes no event, "Travel on" otherwise; the event wins when both are owed. It
    counts what it is about to bin, because a Legendary left on the ground should
    be a decision and not a side effect of pressing Continue. The sections are the
    **real modals, embedded** (`ItemDropModal.embed` / `LootDropModal.embed` /
    `BossNoticeModal.embed`): same cards, same drag, same signals, minus the
    backdrop and the layer. The standalone modals stay, because
    `GameState.offer_loot` fires from `EffectSystem` and a payout that didn't
    arrive with a report has no haul screen to be part of. **The shelf is not
    here** — it was briefly borrowed and handed back, which left four sections
    fighting for a 720p canvas and an exit button pointing at something already on
    screen; it stays under the board per §14, and this screen keeps only the hub's
    id so its button can name it.
- **`RewardScreen.gd`** — chest rewards (level-ups, and the **Wand of Wishing**,
  which is a piece of loot rather than a relic now — `docs/wands-design.md` §5.2).
  **The obtain-any screen is its own layout**: reaching into the whole catalogue is a different decision
  from picking one of three cards, so `setup_obtain` takes the viewport (less a
  margin), shrinks the cards to art-name-and-class chips with the description in
  the hover card, and adds a search over both name and description — around thirty
  items on screen at 720p instead of three, rarest first. The chest a
  report pays doesn't open it either: a beaten game banks 1 point plus each
  defeated body's difficulty (Low 1 … Insane 4, bosses excluded — they bank a
  chest of their own), and `Overworld2._queue_report_chests` spends that on the
  size ladder and hands the chests to the post-combat screen (above). What a body
  drops **on the board** is a piece of LOOT, on the square it fell in
  (`GameLoop2.drops`, drawn wearing its own art by `BattlefieldView._drop_node`);
  whatever is still lying there when the game is reported is swept onto the
  post-combat screen too, win or lose.
- **`FloorLoot.gd` / `DragPackPanel.gd`** — how a piece leaves the floor. The
  token is a drag **handle**, not a button: dragging it mounts the pack to the
  left of the board for the length of the drag (`Overworld2._notification` on
  `NOTIFICATION_DRAG_BEGIN` → `_mount_drag_pack`), and dropping it in a slot, on
  the bin, or on nothing ends both. The grid is the same `LootGrid` every other
  loot surface draws; the one rule it adds is that a floor piece may land on an
  OCCUPIED slot, trading places with what was there — the evicted piece goes back
  onto the square the new one came off, so a full pack is a decision rather than a
  refusal. There is no click: it used to open a `LootDropModal` whose only job was
  to put those nine cells on screen.
- **`RateGameModal.gd`** — the 1-10 tier-list score for a game. Strictly opt-in:
  it only ever opens from a **★ Rate** button (on the report panel while you're
  playing a game, and on the select screen for the game you last reported).
- **`EventModal.gd`** — the D20 stat-check events. Built and tested, but nothing
  on the games-first board opens it yet (see the roadmap).

`PlaySession2.gd` is the text-only precursor of the overworld, kept as a headless
harness for the loop.

### The window

The game opens **windowed** (`display/window/size/mode=0`). That is deliberate:
the core loop is leaving the game to go and play a real one and coming back to
report, so the player alt-tabs out several times a run — and a window is the only
mode that leaves the OS's own taskbar/dock on screen to do it with.

**The window and the canvas are two different numbers.** `viewport_width/height`
is the CANVAS — the fixed 1280x720 box the layout is built to fit — and it never
changes. `window_width/height_override` is how big the window that canvas is
scaled into opens: **2560x1440**, so a 1440p screen draws the page at 2x instead
of in a quarter of the desktop. `Settings.WINDOWED_SIZE` holds the same pair for
every later switch back to windowed, and a test pins the two together — if they
drift, the window resizes itself the moment you press F11 twice.

That size is a **request**. `Settings.windowed_fit()` clamps it to the screen's
usable rect (what is left once the taskbar / dock / menu bar have taken theirs)
*minus the window frame*, since the title bar sits outside the size being set —
so a smaller monitor gets as much as fits and the taskbar stays clear either way.
It is floored at 1280x720: a page shown whole under a taskbar beats a page
cropped to fit above one. The arithmetic is a pure static function precisely
because none of it can be exercised on a headless runner, which has no window
manager and therefore no decorations and no taskbar.

Both fullscreens are still on the list. `Settings → Display` offers **Windowed**,
**Windowed fullscreen (borderless)** (`FULLSCREEN` — a borderless window the size
of the screen, *not* `EXCLUSIVE_FULLSCREEN`) and **Exclusive fullscreen**; **F11**
toggles windowed ⟷ borderless from any screen, and the choice is persisted to
`user://settings.cfg`. Leaving either fullscreen re-fits and re-centres the
window, so "windowed" never comes back the size of the screen with the taskbar
still buried under it.

The stored preference lives under a **versioned key** (`Settings.DISPLAY_KEY`)
because the default moved from borderless to windowed after saves existed: a
`settings.cfg` written under the old default holds an explicit borderless value
for a player who never chose one, and reading a new key is what tells those two
apart — exactly once.

The **layout's size does not change with the monitor**. `stretch/mode` is
`canvas_items` over a fixed 1280×720, so a bigger screen draws the same page
bigger rather than giving it more room — which is exactly why the overworld is
built to fit 1280×720 and why `test_overworld2` pins that. `stretch/aspect` is
`expand` rather than the default `keep`, so a screen that isn't 16:9 gets its
extra pixels as real canvas instead of black bars (16:10 → 1280×800, ultrawide →
1706×720); `expand` can only ever give *more* than the base, so the one-screen
guarantee holds.

### The stream overlay

The build is stream-first: the "combat" is you going off and playing a real game,
so for most of a stream **the Godot window is not on screen at all**. The overlay
is what the audience sees instead — and what tells them why this person is
playing Hollow Knight right now, and what happens if they fail.

It is **not a second Godot window**. `ObsCompanion` mirrors the run onto disk and
OBS renders the page:

```
user://obs/overlay.html   the page          ┐ reinstalled from obs/ at
user://obs/overlay.css    its styling       │ EVERY boot — edit the repo's
user://obs/overlay.js     its ticker        ┘ copies, not these
user://obs/custom.css     yours — created empty once, never overwritten
user://obs/state.js       the run, as `window.OBS_STATE = { … }`
user://obs/covers/        covers lifted out of the .pck (exported builds only)
```

**Setting it up.** Settings → *Stream overlay* → tick "Mirror the run for OBS",
and copy the path it prints. In OBS: **add a Browser Source, tick "Local file"**,
point it at that `overlay.html`, and size it **440 × 850**.

**Do not resize the scene item.** The Browser Source's own Width/Height is the
canvas the page renders into; stretching the item afterwards resamples the result
and softens the pixel art. Set 440 × 850 and leave the transform at 100%.

**How tall the page gets.** It is content-height, so it grows with the run — the
figures below are `tools/check_overlay.js` measuring the real page at 440 wide,
and the last column is the one to size a source against.

| | light run | median | heavy (hour three) | pathological |
|---|---|---|---|---|
| `overlay.html` | 505 | 674 | 695 | **745** |
| `overlay.html#top` | 324 | 306 | 327 | **377** |
| `overlay.html#bottom` | 197 | 384 | 384 | **384** |
| `overlay.html#road` | 118 | 118 | 118 | **118** |

**Almost nothing moves any more, and that is new.** A heavy run and a run twice
its size measure the same 695, because the two things that used to grow the page
are gone: the hero card's status strip (every status is a checklist row now) and
the cost line's strip of swing marks (it is a sentence). `#bottom` stops at 384
because the checklist scroller is capped at 320px and walks the rest, and `#road`
is a fixed 118 whatever the run's length — a longer road is a wider strip, not a
taller one.

The one thing left that can push it is **the shields row wrapping**: thirteen
shields fit one row, and every thirteen after that costs 25px. "Pathological"
above is thirty of them, which no run realistically reaches.

**The ticker is not in those numbers, on purpose.** It is pinned to the bottom of
the browser source and grows upward — at most three toasts, ~91px — so a burst
floats over the foot of the page instead of pushing it out the bottom of the
source, which is what used to happen, silently, at exactly the busiest moment of a
run.

That means the toasts do briefly cover the last ~30px of the road on a heavy run
at 850, which is a strip of cover art for six seconds. **If you would rather they
never touch it, give the source 900** and they land in the slack instead. Taller
than that only buys headroom for a pathological run; the extra is transparent
either way.

#### Rendering part of the page

The overlay is one column, but a scene usually wants the camera partway *down*
that column rather than under all of it — and OBS cannot interleave scene items
with the inside of a browser source. So the page can render part of itself:

| URL | Shows | Height (median → ceiling) |
|---|---|---|
| `overlay.html` | everything except the road | 674 → 745 |
| `overlay.html#top` | hero card + the headline | 306 → 377 |
| `overlay.html#bottom` | checklist + ticker | 384 (fixed) |
| `overlay.html#road` | the road, and nothing else | 118 (fixed) |

Point **several** browser sources at the same file with different fragments and
put whatever you like between them. They read the same `state.js`, so they stay in
step for free.

**The road is opt-in**, and it is the only piece that is. It is a horizontal
scroller, and at 440px it could not be read: measured on a 22-stop run, the stop
the player is standing on was fully on screen for **6 seconds in every 50** and
took 42 seconds to first appear — and every change to the road reset the walk to
the *start* of the run, which is exactly when a viewer looks up. What the road
uniquely says (which games were beaten, which the run walked away from) is worth a
source of its own on a between-games scene, at a width where it does not have to
scroll at all — a 22-stop run is 1008px wide. The **distance** it used to carry is
now on the headline, in a number that never moves.

`#offline` is in none of these lists, so a source that is up before the game is
still says so. The ticker rides with `#bottom`.

#### A scene layout that fits

**C — camera inside the overlay column.** The recommended one: the camera sits
between the overlay's halves, and the game keeps 77% of the width.

| Source | Position | Size |
|---|---|---|
| Game capture | `0, 0` | `1472 × 828` (16:9) |
| **Overlay `#top`** | `1476, 0` | `440 × 360` |
| Camera | `1476, 372` | `440 × 248` (16:9) |
| **Overlay `#bottom`** | `1476, 632` | `440 × 390` |
| Chat | `0, 836` | `1472 × 244` |

**Everything fits now, with room to spare.** 360 + 248 + 390 is 998 of the 1080,
where the old layout needed 26px more than existed and had to under-size `#top` to
get there. `#top`'s 360 clears every run up to the heavy column above (327) and
`#bottom` is at its fixed 384 with 6px of slack. Only a run carrying more than
thirteen shields at once — the one thing that still grows the page — would clip,
and it clips the bottom of a shield row and nothing else.

**There is now room for the road too**, if you want it: the 82px left over takes
`overlay.html#road` at `440 × 118` if you drop the camera to `400 × 225`. It is
the between-games source, so a scene where it sits under the checklist and only
gets looked at while the streamer is picking their next game is exactly what it
is for.

**Chat still cannot go in the column.** 82px of chat is not chat. It goes in the
bar under the game, or on a second monitor. If chat *must* sit directly under the
camera, that is a second sidebar and the game pays for it — see A.

**A — three columns, nothing overlaps.** Camera top-left, chat directly under it,
overlay on the right.

| Source | Position | Size |
|---|---|---|
| Camera | `0, 0` | `384 × 216` |
| Chat | `0, 224` | `384 × 856` |
| Game capture | `392, 236` | `1080 × 608` (16:9) |
| **Overlay** | `1480, 0` | `440 × 850` |

The game drops to 56% of the width and the middle column carries ~470px of dead
band above and below it — the unavoidable cost of two sidebars with a fixed 16:9
rectangle between them.

**B — full-bleed game, columns over its edges.** Game `0, 0` at `1920 × 1080`;
camera `16, 16` at `384 × 216`; chat `16, 240` at `384 × 700`; overlay
`1464, 16` at `440 × 850`. The game keeps every pixel and the columns cover ~20%
of the width at each edge. The games on this map are *real* games with their own
HUDs, so check the one you are about to play — a minimap in a covered corner is
the failure case.

Either way the columns can swap sides; nothing on the overlay cares which edge it
is on.

**If the overlay reads small** for viewers on 720p or a phone, don't scale the
scene item — put `#overlay { zoom: 1.25; }` in `user://obs/custom.css` and set the
Browser Source to **550 × 1065**. `zoom` re-lays the page out at the larger size,
so the text is rendered crisply rather than resampled, and the sprites stay sharp
because everything pixel-art on this page already carries
`image-rendering: pixelated`.

**Why a script file and not JSON over `fetch()`.** OBS renders the page from a
`file://` URL, and Chromium refuses every `fetch()`/XHR a `file://` page makes at
a sibling file — there is no origin to grant, so it is a CORS failure with no fix
short of launching OBS with `--allow-file-access-from-files`. A `<script src>`
has no such restriction. So the state is written *as* an assignment and
`overlay.js` re-loads it four times a second with a cache-buster on the end; the
covers ride the same way, as `<img src="file://…">`. No server, no port.

It shows health with **the shields as sprites** beside it, the character, **what a
lost run would cost you** as a sentence, **the headline** — the game in play, how
many hops to the Amulet, and the Amulet itself — and **the checklist as it ticks**,
which is the page's centre of gravity: every row wearing its own art, scrolling
itself when there is more of it than there is room, flashing a row green as it is
crossed off. **The road** walked so far, ending on the Amulet, is the same strip
`RunOverScreen` draws at the end of a run — it is drawn live but lives at
`overlay.html#road`, its own source, rather than on the default column.

**Every row of the checklist carries its own picture**, and that is the layout's
one big idea. A goal *is* an enemy (§7.2), so a body's row wears its face and, on
the corner of it, the damage that body lands if the run is lost; a status's row
wears its pip art and its stack total; a curse's and an event's wear theirs. That
one change paid for three others — the hero card's status strip went (every
player-side status is claimable, so every one already had a row here, and the
strip was saying it twice), the cost line stopped drawing a *parallel* strip of
faces the viewer had to match against this one, and the six kinds of row stopped
being told apart by **text colour alone**, which was the weakest encoding on a
page read across a room through a lossy encode.

### What a lost run costs

The most important thing on the overlay, and the reason the hero card is shaped
the way it is. A lost run is not an abstract penalty: the enemies take a turn
(§3.2), every body that can reach you swings once, **one shield stops one hit
outright whatever that hit was for**, and the swings past your last shield are
what reaches Health.

That rule is invisible in a summed "12 incoming" — two shields against three
small swings is a completely different position from two shields against one
enormous one — so the page states it: **"2 shields break, −12 Health"**, and
"Health" rather than "damage" because the bar directly above says `7 / 20` and the
two numbers a viewer has to connect should have the same name. The same forecast
is hatched onto the health bar over the HP that would go, and one that would end
the run says so in words.

**Who is throwing each swing is answered on the checklist**, not here. This line
used to draw one mark per swing — the body's own face at 28px, badged with a
shield when the swing was eaten whole or with the damage when it was not — because
it was the only place the page said *who*, and the boss's swing and the fly's are
not the same problem. Now every body has a row in the checklist with its face and
its own damage on the corner, so the identity sits beside the sentence naming it
instead of in a parallel strip the viewer had to align against the real list by
eye. The art holds up at that size because the roster's is bold and
silhouette-driven — checked by rendering the widest range in the set (a 19×10
sprite through a 734×841 painting) at four sizes, not assumed. A row with no art
falls back to an initial; a test asserts every goal-enemy and boss has some, so it
doesn't.

**And a board that cannot reach you does not make the line go quiet.** It used to
hide itself entirely on an empty forecast, which is honest about this turn and
silent about the only question that follows: the board is still walking towards
you. It now says *"nothing reaches you for at least 2 more lost runs"* —
`threat.turns_away`, from `GameLoop2.turns_until_strike`, which is `can_strike`'s
own inequality (`_front_col <= 1 + strike_range`) solved for turns so the two
cannot drift. **It is measured against each body's own reach, never against column
1**: a Ranged body swings from several columns back, and counting steps to the
front line would promise a quiet turn to somebody a Host can already shoot. It is
also a **floor** — a blocked lane, a stun, a turn spent on an ability all make the
real wait longer, never shorter — which is why the page words it "at least".

`ObsCompanion._threat()` mirrors `GameLoop2._take_hit` step for step rather than
re-deriving the arithmetic — damage-taken mods first, a swing modded to nothing
spends no shield, Pierce takes both pools past, timed shields block first — and
excludes the bodies that sit a turn out (staggered, stunned, out of reach). Reach
is `can_strike`, not `in_front`: a Ranged body hits from further back. It is a
forecast, not a promise, since an ability can spend a body's turn on something
else, and **nothing in it mutates** — a test asserts the live shield pools are
untouched by forecasting, and another one takes the prediction and then makes the
board resolve a real `attempt_turn()` to check the Health that actually went.

Four things worth knowing if you change it:

- **A game has no goal of its own, so the overlay has no headline goal line.**
  The goals are the **bodies'** goals — every body following the run, not just
  the one that arrived with the game in play (§7.2) — plus what a status, an
  event or a curse is asking of the player. The checklist is the whole of it, and
  a row belongs to the body or the clause that owns it, never to the game.
- **Goal text is always `GameLoop2.goal_text_for`**, never `enemy.goal` — the
  resource's stem says nothing about the clauses a status has bolted on (§13).
- **Nothing on this page may guess at a rule the game owns.** The cost forecast
  mirrors `_take_hit`; the goal text comes from `goal_text_for`; the pip tint
  comes from `_status_pip`'s rule. An overlay that promises a shield will hold
  and then watches Health go is worse than one that says nothing at all.
- **The road says how each stop went.** Green for a game beaten on that visit,
  **orange (`UITheme.UNBEATEN`) for one the run walked away from** — a missed
  goal, an escape (§3.2), or a teleport that passed straight through without
  playing at all. One colour, because to the road they are one fact: you were
  there and the game is still standing. The same two colours are used by the
  overworld's own header strip and by `RunOverScreen`, all three reading
  `GameState.walked_outcomes()`.
- **Statuses and shields are drawn, not written.** They are `StatusData.image` /
  `UITheme.SHIELD_ART` with `UITheme.TIMER_ART` in the corner for anything
  borrowed — the same art as `BattlefieldView._status_pip`, quoted from the same
  constants so the board and the stream cannot disagree. The colour follows **what
  the side does** (gold for a `bonus`/`goal`, red for anything that taxes), never
  Buff/Debuff. The shields keep their own row under the hero because they are not
  a status — they are what the cost line spends — while a status now rides its
  checklist row at 26px.
- **A status's row is one instance; its badge is the total.** `status_objectives()`
  is one row per instance (a permanent Strength 1 and a borrowed Strength 3 are
  two offers with two deadlines) while `status_list()` totals them, because what a
  stack *does* is felt as a total. The hero card's pip strip was the only thing
  carrying that total, so the badge on the row's art carries it now — that is the
  one thing cutting the strip could have lost, and a test pins it.
- **The rows are read from `GameLoop2`/`GameState`, never from `ReportChecklist`.**
  That is a Control tree which only exists while the overworld is on screen, and
  being right when the game window is behind a stream is the whole job.

**Testing the page itself.** `test/test_obs_companion.gd` pins the *payload* — its
shape, that no `Resource` escapes into it, that the swing forecast matches the
turn the board really takes. It cannot say anything about the page, because the
page is a browser and GUT is Godot. `tools/check_overlay.js` is the other half: it
renders `obs/overlay.html` in headless Chromium against a heavy synthetic run and
asserts the things that only exist once it is on a screen — that `hidden` really
hides, that the road's outcome colours survive the cascade, that the checklist and
the road actually walk while payloads keep arriving, that a burst of toasts stays
inside the browser source, that an undrawable payload is announced rather than
frozen over, and the heights the tables above promise.

```bash
npm install playwright-core          # once
node tools/check_overlay.js          # --browser=/path/to/chrome if it can't find one
```

It is deliberately not wired into GUT — different runtime, different dependency —
so run it by hand when anything under `obs/` changes. Every check in it is a
regression that shipped once.

`obs/` holds plain `.html`/`.css`/`.js`, which Godot does not treat as resources.
Running from source they are read straight out of `res://obs/`; if you ever
**export** the project, add `*.html, *.css, *.js` to the export preset's
"Filters to export non-resource files" or `ObsCompanion` will warn that the page
is missing. (`export_presets.cfg` is gitignored, so this cannot be committed for
you.)

### Data as Godot Resources

All game content is authored as typed Godot **Resources** (`.tres`) under `data/`,
with their schemas defined in `scripts/resources/`:

`GameData`, `GoalEnemyData`, `ItemData`, `CharacterData`, `ScrollData`,
`StatusData`, `TileEffectData`, `UnitData`,
`CurseData`, `StatDefinition`.

(`TileEffectData` rather than `TileData` because Godot ships a native `TileData`
for TileMaps and a `class_name` that shadows one is a parse error — the sheet, the
data folder and the ids all stay "tile".)

`Data.gd` loads them all on startup and serves them by id, so gameplay code never
hardcodes content — it asks `Data` for it. Random draws all share one rarity
ladder there too (`Data.roll_rarity_step` / `roll_item_rarity`): 75/20/5
common/uncommon/rare, with a 10% bump from rare to legendary.

---

## Content authoring & tooling

`tools/Roguelikes.xlsx` is the **design source of truth** for bulk content. The
Python scripts in `tools/` regenerate Godot resources from it (re-run after
editing the sheet, then review the diff):

**The sheets lost their `2.0` suffixes.** `enemies2.0` is now `enemies`,
`items2.0` is `items`, and so on for characters, bosses, statuses, tiles, units,
scrolls, pills, potions, events, curses and objects; the pre-2.0 sheets they
displaced gained `old` (`itemsold`, `eventsold`, `charactersold`,
`encountersold`, `cursesold2`). The **output folders did not move** — the
generators still write `data/enemies2.0/` — so only the `SHEET_NAME` at the top
of each script changed. If a generator ever reports zero rows, this is the first
thing to check: openpyxl raises on a missing sheet, but a *renamed* one that
still exists under an old name silently generates the wrong content.

| Script | Generates |
|---|---|
| `generate_game_tres.py` | `data/games/*.tres` from the curated games subgraph |
| `generate_item2_tres.py` | `data/items2.0/*.tres` from the 2.0 items sheet |
| `generate_goal_enemy_tres.py` | `data/enemies2.0/*.tres` from the goal-enemy sheet |
| `generate_boss_tres.py` | `data/bosses2.0/*.tres` from the boss sheet |
| `generate_character2_tres.py` | `data/characters2.0/*.tres` from the characters sheet |
| `generate_scroll2_tres.py` | `data/scrolls2.0/*.tres` from the scrolls sheet — **and `data/scroll_names.tres`**, the bag of meaningless titles an unread scroll wears, off the same sheet's two right-hand columns (`Random Scroll Name` / `Random Scroll Part`) |
| `generate_pill2_tres.py` | `data/pills2.0/*.tres` from the `pills` sheet — one row is one pill and BOTH its doses, so it parses two effect columns onto one resource |
| `generate_potion2_tres.py` | `data/potions2.0/*.tres` from the `potions` sheet — two effect columns again, but they are two VERBS rather than two doses, so they parse in two dialects: the quaff side targets the drinker, the throw side takes an `area=` around the aimed cell |
| `generate_wand2_tres.py` | `data/wands2.0/*.tres` from the `wands` sheet — one effect column, plus the two columns only a wand has: `Charges` (what a fresh one holds) and `Type` (what it wants pointed at it). `nothing` is a verb here, and every *other* empty Effect cell is refused — Wand of Nothing is the roster's authored blank and a hole must not be able to look like one |
| `generate_status_tres.py` | `data/statuses2.0/*.tres` from the `statuses` sheet — owns the reward-token DSL, and the `Decrease` column's table: `On Completion` sheds a stack when a SIDE is completed, while `On Trigger` and `Each Turn` are worn away by the BOARD (an attack, a turn) and mean *per game* on the player, who has neither |
| `generate_tile_tres.py` | `data/tiles2.0/*.tres` from the `tiles` sheet — owns the trigger / interaction DSL both board kinds use (§17) |
| `generate_unit_tres.py` | `data/units2.0/*.tres` from the `units` sheet — imports the parsers above rather than restating them |
| `generate_ability_tres.py` | `data/abilities2.0/*.tres` from the `abilities` sheet — and owns the **grammar of the enemy `Ability` column** (`Ranged (2), Fireproof, Infliction (1, Burn)`), which the goal-enemy generator imports rather than restating (§7.6) |
| `generate_event2_tres.py` | `data/events2.0/*.tres` from the `events` sheet — see [Authoring an event](#authoring-an-event) |
| `generate_curse2_tres.py` | `data/curses2.0/*.tres` from the `curses` sheet |
| `build_glyph_font.py` | `fonts/*.ttf` — the UI's symbol glyphs, subsetted from Noto. Not sheet-driven: it scans `scripts/**/*.gd` for the glyphs actually used. Run it after adding a new one; `--check` verifies without writing |
| `generate_item_tres.py` | `data/items/*.tres` from the items sheet (pre-2.0 set) |
| `generate_character_tres.py` | `data/characters/*.tres` (pre-2.0) |
| `generate_curse_tres.py` | `data/curses/*.tres` from the `cursesold2` sheet |
| `import-games-godot.py` | `data/games/*.tres` (incl. per-connection source + sequel flag), resolving each cover in `images2.0/games/` — then re-bakes the Atlas |
| `bake_atlas.py` | `data/atlas_layout.tres` — the Atlas star chart's positions |
| `import-reference-godot.py` | `scripts/data/ReferenceCatalog.gd` (Collection catalog) |
| `_relics_events_sheet_edit.py` | one-shot: the Boss/Event relic effects, the curse penalties, and the two new event rows |
| `_events2_ranwid_setup.py` | one-shot: the Ranwid the Elder event row |
| `_events2_tiny_rogues_setup.py` | one-shot: the `Opens With` column, the Potion Lab and Golden Monkey rows, and Ranwid's credit line |
| `_events2_we_meet_again_setup.py` | one-shot: the We Meet Again! event row |
| `_events2_woman_in_blue_setup.py` | one-shot: the Woman in Blue row, and Ranwid's gold ask settling at a flat 2 |
| `_punch_off_robot_edit.py` | one-shot: Punch Off's "I Can Take Them" also spawns a robot (`spawn_enemy tag=robot 1`) |
| `_abilities_sheet_setup.py` | one-shot: settled the `abilities` sheet (the two riders' wording, the new **Agile** row), gave The Obscura and the two thieves their arguments, and turned the boss sheet's `Notes` column into `Phases` — with Guillatina as the first three-phase boss (§7.6) |
| `_chart_system_vocabulary.py` | one-shot: settled the `chart` sheet's System column on plural (`Bomb`/`Bombs` and three more collided, and a group-by rendered each as two systems), trimmed stray whitespace, and renamed the `Arcade` node to `Arcade Room`. |
| `_chart_abilities_review_fixes.py` | one-shot: the ten fixes off the systems-graph ability review — dropped the duplicate `Loot Amount` Good Direction, pointed Haste at `Speed on Enemy`, renamed the Gold system to `Economy`, settled the new trigger names (`Enemy Attack`, `Enemy Passive`, `On Player Debuff`), and added the three structural rows (Enemy Damage, Shield Absorption, Lost Game). |
| `_chart_summoners_and_tiles.py` | one-shot: gave the five summoners the loot/gold payout §7.6 says a summoned body owes, and added the two tile rules (Fire applies Burn, Web applies Stun, both to enemies) — which took Tiles off the systems graph's sink list. |
| `_chart_enemy_goals.py` | one-shot: added `Goals · Goal Amount` and the `Enemy Goal` structural row, so the systems graph carries the game's central loop — a body arriving puts a real game on your evening, and beating that game is what takes a point of its Health (§7.6, "Health here is goal completions"). |
| `audit_systems_graph.py` | read-only audit of the `chart` sheet — the systems graph (`docs/systems-graph.md`). Reports uncoloured arrows, vocabulary collisions and dangling `Otainable` refs; coverage against every content sheet; and the collapsed system→system graph with its cycles and its sinks. Writes nothing, so it is safe to run any time. |
| `_xlsx_surgery.py` | shared helper: edit ONE sheet of `Roguelikes.xlsx` in place. An openpyxl round-trip drops the workbook's eight charts, so the sheet-editing one-shots (`_statuses_sheet_setup.py`, `_statuses2_combat_setup.py`, `_statuses2_burn_setup.py`, `_items2_statuses_setup.py`, `_events2_sheet_setup.py`, `_curses2_sheet_setup.py`, `_abilities_sheet_setup.py`) rewrite just that sheet's XML parts and copy every other zip entry through untouched. |

The `_*_setup.py` scripts are **bootstraps, not generators**: they lay a sheet's
header row down and re-author the rows they hold in Python. Once you are editing
a tab by hand you never need them again — and they will refuse to run rather than
overwrite a row they don't know about. `_relics_events_sheet_edit.py` is the same
kind of one-shot pointed at a single change (the Boss/Event relics, the curse
penalties, the Golden Idol and Relic Trader rows, and the two extra `Choice N`
column groups); it is idempotent and kept as the record of that edit.

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

---

### Authoring an event

An **event** is what the run does between games. One fires after **every** game
the run plays — win, loss, or escape — on top of whatever the game itself paid.
The games this is a graph of are hour-long roguelikes, and an event is the beat
between two of them: a decision that takes a minute and costs something.
Everything about one lives in the **`events2.0` tab** of
`tools/Roguelikes.xlsx` — one row per event — and nothing about it lives in code.

**Which event you get** is dealt from a **shuffle bag**, per rarity:

- roll the rarity ladder (Luck rerolls it, like every other roll in the build),
  falling down to the nearest stocked rung — today everything is Common;
- draw from the events of that rarity **not yet seen this run**. Opening one
  marks it seen whether or not you engaged with it;
- when a rarity's bag empties it reshuffles, except that the event which just
  emptied it may not open the next bag;
- an event gated out right now (Requirement unmet, wrong tier) is **skipped and
  stays in the bag** rather than being burned.

Each **game** pays one event and then is spent for the run, so walking a
two-node loop is not an event faucet. A **detour** (`play_game`) pays none — its
destination is somewhere the run was sent, and an event there would land on top
of the stay-or-return question. Nor does the **Amulet** game: the run is over.

> Events used to hang off dead ends only, with placement **hashed** from the node
> id so the offered card's `✦ EVENT` badge could not change under the player.
> Both are gone — an event after every game means there is no subset of nodes to
> badge, and no honest answer to "which event is over there" before you arrive.

The full design rationale is [`docs/event-sheet-authoring.md`](docs/event-sheet-authoring.md);
this is the how-to.

#### The loop

```bash
# 1. edit the events2.0 tab in Excel
python3 tools/generate_event2_tres.py --list   # 2. dry run: parse it, write nothing
python3 tools/generate_event2_tres.py          # 3. write data/events2.0/*.tres
godot --headless -s addons/gut/gut_cmdln.gd    # 4. (optional) the suite still passes
```

The generator is **strict on purpose** — a typo'd stat or a dangling curse id is
an event that silently never fires, so it raises instead. Read the error, it
names the row and the cell.

#### The row: fifteen event columns, then four choice groups

| Column | Fill in |
|---|---|
| `Event` | Display name. Slugified, this is the id (`Scrap Ooze` → `scrap_ooze`) and the `.tres` filename. |
| `Game` | The real game it's lifted from. Shows as "From: *game*" in the modal. |
| `Tier` | `All`, or a comma list of `Low` / `Medium` / `High` / `Insane`. |
| `Where` | **Leave blank.** An event fires after every game, so this answers nothing today. It stays wired (`Dead End` / `Any` / `Game`) for the per-location work. |
| `Requirement` | A gate on the run: `<stat> <op> <value>`, `%` reads against the max. `hp <= 70%`, `games >= 6`. Several clauses joined by **`and`** when an event needs more than one thing at once (`gold>=2 and potions>=1 and relics>=1` — Ranwid, whose every button spends a different kind of thing). Blank = always eligible. A gated event is skipped and stays in the bag. |
| `Trigger` | `After` (fires once the game at the node is played). ⚠ `Before` parses and is stored, but **nothing reads it yet**. Leave it `After` until that is wired up. |
| `Rarity` | `Common` / `Uncommon` / `Rare` — which bag it is dealt from. |
| `Image` | Art base name → `images2.0/events/<Image>.png`. Blank falls back to the de-spaced `Event`. |
| `Prompt` | The prose at the top of the modal. Blank is legal — a wordless event stacks its art *above* the choices instead of beside them (see "Art"). |
| `Opens With` | What the event is already doing when it opens, before anything is pressed. One token: `offer_loot <kind> <n>` — n rolled pieces laid out as the **real drop table inside the event's body**, with the player's live 3×3 and its bin beside them, so taking one is the same drag it is anywhere else (the Potion Lab). Blank on every other event — and note that loot an event PAYS lands on the same table, so a `gain_potion 3` in an `Effect` cell needs nothing here. |
| `Goal Met` / `Goal Missed` | Only if a choice uses `add_goal`: what the event says when that goal lands or lapses, games later. |
| `Chance Won` / `Chance Lost` | Only if a choice uses `chance`: what it says when the roll lands or doesn't. |

Then `Choice N | Repeat N | Result N | Effect N` for N = 1…6, in display order.
**A blank `Choice N` ends the list** — the generator stops reading there, so a
two-option event just leaves the remaining cells empty. (Six because the Golden
Idol is a five-button event — Take and Leave, then the three ways out from under
the boulder.)

`Result N` is the prose printed once that choice resolves; blank is legal (the
modal then prints only the mechanical line). `Effect N` is the payload.

#### The `Effect` cell

Semicolon-separated tokens. It is the same reward DSL `statuses2.0` and
`items2.0` speak, so a chest an event pays is the chest an item pays.

| Token | Does |
|---|---|
| `gain_chest small\|medium\|large\|huge N` | N chests. The size is **how many items it offers to pick from** — small = 1, medium = 2, large = 3, huge = 5. |
| `gain_chest reward N` | The sheet's **`[chest reward]`** — N chest *points* spent on the size ladder instead of N chests of one size. Small 1, Medium 2, Large 3, Huge 4, then greedily Huge + a remainder: 3 = one Large, 6 = a Huge and a Medium, 8 = two Huges. Use this wherever the payout has to grow with something (a status's stack count); `gain_chest small {X}` grows into X screens each worth less than the last. |
| `gain_hp N` / `gain_max_hp N` / `gain_empty_max_hp N` / `heal_full` | Health. `gain_max_hp` raises the cap **and heals by the same amount** — the container arrives full. `gain_empty_max_hp` is the half that doesn't heal, for the item that means an empty container (Hollow Heart). |
| `lose_hp N` / `lose_max_hp N` | The same, pointed the other way — except `lose_max_hp` **costs no Health**: it takes the room, and Health only moves when it no longer fits. A `lose_hp` that empties Health ends the run — no separate kill token. |
| `take_damage N` | Damage rather than a bill: it resolves through `GameLoop2.damage_player`, so a Shield (§3) stops the whole instance and the player's own statuses scale it. `lose_hp` goes straight to Health past both. Burn's "or take 3 Damage" is what it was added for. |
| `gain_gold N` / `lose_gold N` / `lose_gold all` | Gold. `all` empties the purse — the one amount settled when the choice is taken rather than when the `.tres` is written. |
| `gain_stat <verb> N` / `lose_stat <verb> N` | `bash`, `dash`, `push`, `transmute`, `scramble`, `bombs`, `keys`, `shields`. |
| `gain_loot N` | A loot drop, rolled across every loot type there is — it widened on its own as pills and then potions arrived, with no row ever touched. `gain_scroll N`, `gain_pill N` and `gain_potion N` name one alphabet instead, for a row that is *about* that kind of thing (the Battleworn Dummy pays a potion because the dummy it is translated from does). |
| `apply_status <status> N` | A `statuses2.0` status on the player. On an **item** an optional `target=` says who instead: `current` / `all` / `random` name bodies by rule, and **`target=enemy` means one the player POINTS AT** — `ItemData.wants_target()` reads it, so the overworld arms the board and the click fires the item (Staff of Flame). A **scroll** takes the same words plus `player` and `front` (everything touching the front column — Scroll of Fire burns you and them at once). |
| `apply_tile <tile> …` | A `tiles2.0` TILE EFFECT on the GROUND (§17). On a **scroll**, `front` / `back` / `all` name a strip of the board (Scroll of Fire lights the front column). On an **item**, `target=tile` means a CELL the player POINTS AT — `ItemData.target_kind()` reads it, so the board arms a cell picker instead of lighting up the stack — and `cols=A-B` fences how far it reaches (Red Candle's columns 2-3). |
| `apply_unit <unit> …` | The same, for a `units2.0` UNIT (§17). `target=random_empty` puts it on a cell with nothing on it at all — no body, no unit, no tile effect (Landmines). |
| `random_item_choice N` | Pick 1 of N random items. |
| `gain_item <item_id>` | A **named** `items2.0` relic, handed straight over — the one token that says *which* item. The generator checks the id against the sheet. |
| `spawn_enemy [N] [tag=<t>]` | Conjures N enemies at the run's current difficulty onto the following stack. What every curse costs. `tag=` narrows the roll to the goal-enemies carrying that synergy tag (`spawn_enemy tag=robot 1` — Punch Off's Constructs); the generator checks the tag against the `enemies` sheet's Tag column, and a tagged roll widens by difficulty rather than dropping the tag. |
| `trade_relic <slot>` | The Relic Trader's swap: one of your relics for one of his. Fills `<give>` / `<get>` in the choice's prose. |
| `gain_random_item N` | N relics off the rollable pool, straight into the pack — not a chest opened a screen later. Prefers what you don't own, and fills `{ITEM}` with what it rolled. |
| `lose_potion` / `lose_relic` / `lose_card [uncommon+]` | A price paid in **things**: one bottle, one tradeable relic, one card. Which one is rolled when the event opens and named on the button through the `<potion>` / `<relic>` / `<card>` holes, so the player knows what they are handing over before they press (Ranwid the Elder, We Meet Again!). |
| `obtain_item` | Pick **any** item in the catalogue. This is Wand of Wishing's picker (the WAND's, since the relic became one — `docs/wands-design.md` §5.2) — much stronger than a chest, use deliberately. |
| `nothing` | An explicit no-op. Write it where a blank cell would read as unfinished. |

And the event-only forms:

```
needs keys 1                           only offered if the player HAS it (a check, not a charge)
needs Immerse > 0                      only offered at this point in the event (names another Choice)
add_goal "<condition>" [for <n> games] -> <reward>
add_curse <curse_id> | random [for <n> games]
play_game tag=<tag> -> <reward>
chance <p>% -> <reward>
```

- **`needs <resource> <n>` only checks.** It does not deduct — a locked chest
  that costs a key is `needs keys 1; lose_stat keys 1; gain_chest medium 1`, with
  the gate and the charge written separately. Gate stats: `hp`, `max_hp`, `gold`,
  `games`, `keys`, `bombs`, `bash`, `dash`, `push`, `transmute`, `scramble`,
  `shields`, `relics` (tradeable ones only) and `potions` (bottles carried).
- **`add_goal`** bolts an objective onto the next *n* games, in the same
  honour-system voice enemy goals use. Pays if met, costs nothing if not.
- **`add_curse random`** draws the curse when the button is pressed instead of
  naming one, and **never draws a permanent one** — a random roll that could hand
  out Curse of the Bell would make an idle button a coin flip on the rest of the
  run. The Golden Monkey is what it is for.
- **`add_curse`** is that inverted — an objective you want to *not* meet, which
  bills you every time you do. It takes an id from the **`curses2.0` tab**, so
  the curse is authored once and any event can hand out the same one. On the
  report checklist it is a row like any other — an **instruction** with its price
  after it (`CurseData2.goal_text()`, then `if failed, <penalty>`: "don't use a
  rest site to replenish health   if failed, Spawn a random enemy") — ticked if
  you followed it, and **left unticked is what fires the penalty**. Conditions
  authored as an absence ("you don't ring a bell") have the negation stripped
  rather than doubled, so the row reads "ring a bell".
- **`play_game`** sends the player to a random game carrying `tag`, off their
  route; the `->` payload lands when they beat it. **Check the tag has games
  behind it first** — the thin end of that vocabulary has single-game buckets.
- **`chance`** rolls. A win pays the `->` payload *and closes the event*; a loss
  pays nothing. The costs in front of it are charged either way.

`add_goal`, `play_game` and `chance` are **arrow verbs**: everything past the
`->` is their payload, so each has to be the last clause in its cell — which is
also what limits a cell to one of them, since a second could only come after the
first.

#### Making a choice repeat, and escalate

Two columns do all the push-your-luck work:

| `Repeat N` | After the choice resolves |
|---|---|
| blank / `End` | The event closes. |
| `Again` | Stays open, choice still available. `Again x3` caps it. |
| `Stay` | Stays open, but this choice is now **spent** — which is how a two-stage event fits on one row. |

And inside an `Effect`, **`{X}` is how many times this choice has already been
taken** (0 on the first press) — and a hole may also name the run itself,
`MAX_HP` / `HP` / `GOLD` / `GAMES`, which is how the Golden Idol charges 25% of
Max Health and still prints "-3 Health" on the button. So one authored group is a
whole ladder:

```
Linger        Again   needs Immerse > 0; gain_max_hp 1; lose_hp {4+X}     4, then 5, then 6…
Deeper        Again   lose_hp {2+X}; chance {35+10*X}% -> gain_chest small 1
```

Arithmetic is evaluated at press time, so the button can print what *this* press
costs ("−3 Health · 55%: +1 Small Chest") and the player never sees the formula.

A **staged** event is `Stay` plus a `needs <Choice>` gate: the first press spends
itself and reveals a different button. Abyssal Baths (Immerse → Linger) and
Scrap Ooze (Reach Inside → Deeper) are both built that way.

#### Art

Drop a PNG in `images2.0/events/` named after the `Image` column — PascalCase,
like the rest (`ScrapOoze.png`). Portrait suits the modal's left column best. The
generator prints a `!` warning if the art is missing; the event still works.

Where the picture goes depends on the `Prompt`. With prose, it stands in a fixed
column to the LEFT of the words and buttons, costing no vertical room. With a
BLANK prompt — the Arcade Room — there is no page of words for it to sit beside,
so the modal stacks: art on top, centred and height-capped, choices under it. The
shape is chosen when the modal opens and does not change if a `Result` prints
later.

#### Seeing it in the game

**Use the dev panel's Events tab.** Turn on dev mode in Settings, press `` ` ``
in a run, and open **Events**. Every authored event is listed, and each row
carries the thing that is otherwise invisible — *why it is or isn't turning up
where you stand*:

```
Scrap Ooze    (3 choices)    ✓ eligible here
Unrest Site   (2 choices)    ✗ not a dead end, needs Health <= 70%
Punch Off     (2 choices)    ✗ used 1/1 this run
```

Clicking a row **starts it right there**, blockers and all — the one you can't
reach is exactly the one you need to look at. It goes through the same path an
earned event takes, so the modal, the `finished` handling and a `play_game`
detour all behave as they will in a real run (which also means starting one puts
it in the bag — there's an **Empty the bag** button for that, and an **Un-spend
this node** one for the game you are standing on).

Why it's needed: an event you cannot get to tells you nothing about which gate
stopped it, and waiting for the bag to deal you the one you are editing is not a
workflow. Every row prints its blockers straight from `EventSystem.blockers_for`
— the same call the dealer makes.

The tab also **spawns objects**. Objects are only spawned by events today, so
without that button the under-board panel — the whole non-event half of how a
machine reaches the screen — would have nothing that could reach it.

The panel is the fast path; driving
`EventModal2.open(host, Data.get_event2(&"your_event"))` from a throwaway scene
with the `verify` skill (`.claude/skills/verify/`) still works and will
screenshot it.

#### Rules of thumb

- **Worth well under one game's reward.** One fires after every game now, so a
  6–12 game run sees 6–12 of them; anything that would be a fair payout for a
  two-game detour is, at this cadence, the run's main income.
- **Health is 5–10, not 75.** A source game's damage numbers almost never come
  across unscaled; 3 damage is a third of a character here.
- **Be careful with events that can kill you.** They no longer sit at the end of
  a detour the player chose to walk; they turn up after any game at all.
- **Quote the source game verbatim** where you can, and leave a `Result` blank
  rather than inventing prose and presenting it as the game's.
- **Don't run `tools/_events2_sheet_setup.py`** once you've authored by hand. It
  is the bootstrap that laid the tab down and it rewrites it wholesale from a
  Python list; it will refuse rather than drop your rows, but it has nothing you
  want. The same goes for `tools/_objects2_sheet_setup.py`.

### Authoring an object

An **object** is a machine you stand in front of — the Blood Donation Machine,
the Donation Machine. Same authored shape as an event (one row on the
**`objects2.0` tab**, choices in numbered column groups, Effect cells in the same
DSL), differing in that it **persists** while the run is on that game, is
**spawned** rather than arriving on its own, and is **stateful**.

```bash
python3 tools/generate_object2_tres.py --list   # dry run
python3 tools/generate_object2_tres.py          # write data/objects2.0/*.tres
```

Full format spec, the eight object-only verbs, and the two authored machines:
[`docs/object-sheet-authoring.md`](docs/object-sheet-authoring.md).

### Luck

**Every point of Luck buys one more roll, and the better result is kept.**

That is the whole model, and it applies to every random decision the run makes.
At 1 Luck a 25% chance is really **43.75%** (`1 - 0.75²`); at 3 Luck it is
**68%**. Luck compounds rather than adding, so it is not `p × (1 + luck)`.

Negative Luck is the same machine pointed the other way — `|Luck|` extra rolls,
keep the **worse** — so a run at −2 sees that same 25% land at **1.6%**.

> This replaced a 10%-per-point chance of *advantage* (roll twice, sometimes).
> The difference is not a tuning change: at a single point the old one did
> nothing at all nine times in ten, so Luck was a stat you could hold and never
> see. A guaranteed reroll is felt on the first roll after you pick up a Clover.

**Which way is "better"** cannot be guessed, so every roll site declares it
(`Stats.Favour`):

| | |
|---|---|
| **`HIGH`** | a bigger number or a success is what you want — the rarity ladder, a chest gamble, how many pickups a bombed machine scatters, the Donation Machine's 5% Luck payout |
| **`LOW`** | success is the bad outcome — the Donation Machine's jam, Curse of Decay's item downgrade |
| **`NONE`** | there is no better side, so Luck stays out — *which* of the twelve Commons you drew, whether a burst machine dropped a Blood Bag or an IV Bag, heads-or-tails on a pickup |

The one that reads backwards is worth spelling out: the Blood Donation Machine's
6.7% explosion is **`HIGH`**. Bursting pays an Event relic and one gold does
not, so Luck makes the machine *more* likely to go off in your face — which is
the outcome you were feeding it for. At 1 Luck the button reads **13%**, not
6.7%.

**Where it lives.** `Stats.roll_chance` / `roll_range` / `roll_rarity_step_with_luck`
are the four entry points, and `Data.roll_item_rarity` calls the last of them —
which is what makes "Luck affects every roll" true without thirty call sites
having to remember it. Item rewards, chest sizes, scrolls, shop stock and the
object pools all walk that one ladder.

**What the player sees.** A `🍀 Luck` chip sits with the verbs under the
offering, and any button quoting odds quotes the ones Luck **will actually
roll** — `Stats.effective_chance`. A button that said 6.7% to a player holding a
Clover would be lying to them about the thing they bought it for.

**Where it comes from.** The **Clover** (Uncommon, `items2.0`) is `+1 Luck` as a
passive bonus, so the Luck goes away with the item. The **Lucky Hat** (Common) is
the same point of Luck with a shorter life expectancy — it is destroyed by the
first enemy attack that costs Health, and the Luck leaves with it. The Donation
Machine pays a point on a 5% roll per coin. There is no cap.

---

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
cross-run tier list, and the OBS companion overlay (§9, "The stream overlay"
above). What's still ahead:

- **Overworld encounters** — deals, teleporters and challenge rifts are a design
  with no code behind it any more. The seven-row `data/encounters` scaffold,
  `EncounterData`, its generator and `GameState.encounter_requirement_met` were
  **deleted**: they loaded on every boot, were read by nothing, and were guarded by
  tests that made dead content look maintained. The `encountersold` sheet is still
  in the workbook when they are picked back up. **Shops are not on this list** —
  they landed as their own thing at the ten hub games (§14).
- **The D20 events** — likewise deleted, for the same reason: `scripts/events/`
  (`EventModal`, `D20DieView`), `EventData` and the four ported `data/events` rows
  had no scene, no caller and no way to be reached. Events 2.0 (§12,
  `docs/event-sheet-authoring.md`) is the event layer the run actually has.
- **Run History** — saving and resuming a run is done (Save button, autosave,
  Continue list), but the menu's Run History is still a stub: nothing records a
  run once it's finished, so there's no post-mortem to read.
- **Keys and locked paths** (and the **Fog** scroll) — deferred by decision (§4):
  no 2.0 content grants keys, and no edge is gated behind one.
- **Tags and path requirements (§6.2)** — widen the tag vocabulary on `GameData`
  and let an edge demand a type or tag ("this route needs a Deckbuilder clear"),
  so routing becomes a collection puzzle rather than a shortest path.
- **Content depth** — the catalogs are thin next to the 857 games: 48 goal-enemies,
  38 bosses, 25 items (3 of them Boss relics, 1 an Event relic), 6 scrolls,
  11 characters, 10 events, 3 curses. More of each (and more goals per type) is
  the cheapest way to add run variety; all of it comes from the sheet.
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
  Dash / Scroll of Teleportation / the three teleport cards (Ride the Bus, The
  Hermit, The Fool).
- **Curses** — the combat-era `data/curses` cards are shelved on purpose (§5):
  the enemy-with-a-goal is the challenge mechanic. The 16 of them and their hooks
  stay in the repo in case they come back as an opt-in gambit layer. The live
  **curse goals** (`curses2.0`) are a different thing and are built.

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
