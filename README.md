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
│   │                      #     ItemInfoCard    — click-to-inspect item card
│   │                      #     GameChoiceModal — the popup an offered card opens
│   │                      #     ShopPanel2      — a hub's shop, mounted under the board
│   │                      #     ObjectPanel2    — the machines standing here, same place
│   │                      #     ObjectCard      — one machine, in the panel or in an event
│   │                      #     BossNoticeModal — the "⚠ BOSS INCOMING" popup
│   │                      #     RouteLadder     — the arrowed shortest-path graph
│   │                      #     RunOverScreen   — the end-of-run verdict screen
│   │                      #     RunMapModal / ScrollReadModal
│   ├── events/           #   the D20 event system (EventModal, D20DieView)
│   ├── menu/             #   the main menu + CustomRunScreen (the custom run's setup)
│   ├── runtime/          #   RunGraph — the real-games influence graph
│   └── ui/               #   shared UI (UITheme, RewardScreen, Collection, toasts)
│                          #     AtlasView + AtlasLayoutBuilder — the star chart
│                          #     and the runtime layout behind its filters
│
├── data/                  # Game content as Godot Resources (.tres) — the source
│   │                      # of truth the game loads at startup (see Data.gd)
│   ├── games/            #   GameData — the ~849 real games that form the map
│   ├── atlas_layout*.tres#   BAKED star positions for the Atlas, one sky per game
│   │                      #   filter: all / _owned / _downloaded (tools/bake_atlas.py)
│   ├── items2.0/         #   ItemData — the relics that drop from a defeated enemy
│   │                      #   (Rating Boss / Event = a relic only a boss or an
│   │                      #   event pays; never in a random pool)
│   ├── enemies2.0/       #   GoalEnemyData — goal-enemies, one per game beaten
│   ├── bosses2.0/        #   GoalEnemyData — the difficulty-gate bosses
│   ├── characters2.0/    #   CharacterData — the playable roster
│   ├── scrolls2.0/       #   ScrollData — identify-by-reading scrolls
│   ├── statuses2.0/      #   StatusData — clauses bolted onto goals (§13)
│   ├── events2.0/        #   EventData2 — one fires after every game played
│   ├── objects2.0/       #   ObjectData — the machines you stand in front of (§15)
│   ├── curses2.0/        #   CurseData2 — the checklist curses events hand out
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
│   ├── generate_status_tres.py     #   data/statuses2.0 (owns the reward-token DSL)
│   ├── generate_event2_tres.py     #   data/events2.0
│   ├── generate_curse2_tres.py     #   data/curses2.0
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
| `EventSystem` | Events (`docs/event-sheet-authoring.md`): dealing an event from the per-rarity shuffle bag when a game is played, the Requirement/`needs` gates, and resolving a choice into effects, an event goal, a curse, or a `chance` roll. Objects go through the same resolution. |
| `ObjectSystem` | Objects (`docs/object-sheet-authoring.md`): the machines standing in front of the player, spawning them by tag, and their state — jams, what has been blown off the run, and the Donation Machine's cross-run bank. |
| `GameLoop2` | The run loop: the games-beaten clock, the goal-enemy stack, and the grid the followers advance across. `Overworld2` is a view over it. |
| `ShopSystem` | Shops (`docs/games-first-redesign.md` §14): which games are the run's ten hubs, each shop's three-item shelf and its prices, buying, and the Scramble reroll. State lives on `GameState` (`hub_games` / `shops`), the same split `EventSystem` uses. |
| `ScrollSystem` | Scroll identification + reading (the unidentified-loot gamble). |
| `GameLog` | Verbose run-scope message log (teleports, pickups, item procs) — the written record behind the toasts. |
| `Notifications` | Curated player-facing "important events" channel; the overworld mounts `NotificationToasts` to show them. |
| `SaveSystem` | Save/load for a games-first run (`user://`): a named save per run plus the run's own autosave slot. Writes GameState, `GameLoop2`, and the overworld's on-screen state, and hands a loaded run back to the next `Overworld2` to boot. |
| `Settings` | Run-independent preferences (e.g. game-filter) persisted to `user://settings.cfg`. |
| `RunConfig` | A **custom run**'s setup, held for the run it configures: three independent filters (**map** / **start** / **amulet**, each with library, genre, record and release-year axes), the run-length band, and an optional named target game. Off by default, in which case `RunGraph` reads `Settings.game_filter` exactly as before. Written by `CustomRunScreen`, read by `RunGraph`, and saved with the run — the filters *are* the map, so a save resumed without them comes back on a different one. `RunConfig.describe()` is what the menu's Continue list prints on a custom run's row, read off that save's own stored block rather than off the loaded run. |
| `TierList` | Cross-run tier list / ranking store that outlives any single run. |
| `GameStats` | Cross-run lifetime per-game play stats (games beaten / verified), plus the Donation Machine's bank — the one number in the build that deliberately outlives a run. |
| `DevTools` | Developer panel (press `` ` ``), gated on `Settings.dev_mode`. Five tabs: **Grant** (items / scrolls / statuses, with a player-or-enemy target picker — the item list is `DevTools.item_pool()`, the **2.0 set only**: it used to append the 112 combat-era relics from `data/items`, which grant cleanly and then do nothing because no games-first code honours them), **Run** (vitals, every board verb, gold, chests, level, games played), **Board** (spawn a goal-enemy or boss; stun / push / bomb / defeat / remove or status any standing body), **Flow** (jump to a game, heal, clear the board, force the win or loss), **Events** (start any authored event where you stand and read the state of the shuffle bag, each row saying why it is or isn't turning up on its own — see [Authoring an event](#authoring-an-event); the same tab spawns any **object** under the board, which is the only way to reach the non-event half of how a machine appears). Everything routes through the same public API the game uses. |

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
  choosing, the honour-system report step + attempt tracker while you're playing),
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

  **The header is the road you have walked.** Across the top, between the health
  and gold chips and the `☰ Menu`: the games played as small covers with arrows
  between them, then a dashed arrow to the Amulet — the same picture the
  end-of-run screen draws, live, for the whole run. It is the only view of the run
  as a *journey*; the checklist says what you owe, the board says what is chasing
  you, and neither said where you have been. The title moved to the right to make
  room, which is also the honest ranking of the two. Covers are small and unnamed
  (the name is on the hover) because the strip shares its row with everything else
  and the page still has to fit 720; past `STRIP_MAX_STOPS` the oldest stops are
  dropped behind an ellipsis.

  **Where the numbers are.** There is **no HUD strip** — every number is drawn
  once, by whatever owns it:
  - **the player** (Health, Shields, statuses) is on the **board's hero**:
    `♥ hp/max` under the portrait, the shield pips over it, status pips between.
  - **the board's verbs** are on the **board's own bars**: its pressure bar ends
    `▦ 4×4 · Low` (that's the tier) and its toolbar buttons read `⇤ Push (1)` /
    `✸ Bomb (3)`.
  - **the choosing verbs** — **Bash / Dash / Transmute / Scramble** — are chips on
    a row under the offering, since all four change what is on the table. Dash and
    Scramble are buttons; Bash and Transmute need a target, so they are readouts
    pressed inside a game's popup.
  - **the tries a game grants** ride the offering's one-line hover.
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
    ladder**, the enemy waiting there and its goal, the tries the game grants, the
    pace it puts the board on, your record in it — over the three buttons that
    answer it: **Travel**, **Bash**, **Transmute**. The cover is drawn small on
    purpose: it is the one thing you have already seen (it is what you clicked),
    and the room it gives back goes to the enemy and its goal. It decides nothing itself;
    each button calls the overworld's `pick` / `bash_choice` / `transmute_choice`.
  - **`RouteLadder.gd`** — the shortest-path DAG as a top-to-bottom ladder of
    boxes with green arrows between them, colour-coded by role. Shared: the 🗺 map
    window (`RunMapModal`) and `GameChoiceModal` draw the same graph from it.
    Over the star chart the map window has **no Close of its own** — the chart
    owns the screen and its Close takes the window with it — so the button in its
    corner rolls it up to its title bar instead. Opened without a chart under it
    (the start picker) it is the only thing on screen, and there it keeps one.
  - **`BattlefieldView.gd`** — the board: the hero on the left with the shield
    pips over them, the grid the goal-enemies close in across, the off-field lane,
    the Push / Bomb toolbar, and the strike / advance animation. **Push is armed
    then aimed**: pressing `⇤ Push` arms the verb, clicking an enemy picks the
    body, and an arrow appears on every side of it a shove could legally land on
    — back, forward, or up/down, which is the only lane change on the board.
    Nothing is spent until an arrow is pressed. **The enemy of the game you are
    playing stands on the board with the rest** (§7.2), drawn on a washed fill so
    it is tellable from its neighbours; the off-field lane is for bodies with
    nowhere to stand. Nothing is drawn over the top of a body — the boss skull and
    the "in 2" that used to be there covered the picture that identifies it.
  - **`EnemyInfoCard.gd`** — the click-to-inspect card for one enemy.
  - **`ShopPanel2.gd`** — a hub's shop (§14), mounted **under the battlefield** on
    the page rather than opened over it: it blocks nothing, stays for the whole
    visit, and travelling on is what closes it. The overworld floats a
    `🛒 Shop ↓` pointer at the foot of the screen until it has been scrolled to.
  - **`BossNoticeModal.gd`** — the "⚠ BOSS INCOMING" popup (§7.1), opened once per
    boss round. It replaced a banner strip that shoved the whole page down. Its
    boss portraits are **clickable**: each opens the ordinary `EnemyInfoCard` over
    the popup, read-only (no body exists yet, so no Push / Bomb), which is where
    "what does it want and what does it hit for" gets answered.
- **`RewardScreen.gd`** — chest rewards (level-ups, Wand of Wishing). Ordinary
  enemy drops don't open it: they land in the loot tray beside the board.
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
| `generate_event2_tres.py` | `data/events2.0/*.tres` from the `events2.0` sheet — see [Authoring an event](#authoring-an-event) |
| `generate_curse2_tres.py` | `data/curses2.0/*.tres` from the `curses2.0` sheet |
| `generate_item_tres.py` | `data/items/*.tres` from the items sheet (pre-2.0 set) |
| `generate_character_tres.py` | `data/characters/*.tres` (pre-2.0) |
| `generate_curse_tres.py` | `data/curses/*.tres` from the `cursesnew` sheet |
| `generate_event_tres.py` | `data/events/*.tres` from authored Python dicts |
| `generate_encounter_tres.py` | `data/encounters/*.tres` from the `encounters` sheet |
| `import-games-godot.py` | `data/games/*.tres` (incl. per-connection source + sequel flag), resolving each cover in `images2.0/games/` — then re-bakes the Atlas |
| `bake_atlas.py` | `data/atlas_layout.tres` — the Atlas star chart's positions |
| `import-reference-godot.py` | `scripts/data/ReferenceCatalog.gd` (Collection catalog) |
| `_relics_events_sheet_edit.py` | one-shot: the Boss/Event relic effects, the curse penalties, and the two new event rows |
| `_punch_off_robot_edit.py` | one-shot: Punch Off's "I Can Take Them" also spawns a robot (`spawn_enemy tag=robot 1`) |
| `_xlsx_surgery.py` | shared helper: edit ONE sheet of `Roguelikes.xlsx` in place. An openpyxl round-trip drops the workbook's seven charts, so the sheet-editing one-shots (`_statuses_sheet_setup.py`, `_items2_statuses_setup.py`, `_events2_sheet_setup.py`, `_curses2_sheet_setup.py`) rewrite just that sheet's XML parts and copy every other zip entry through untouched. |

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

#### The row: fourteen event columns, then four choice groups

| Column | Fill in |
|---|---|
| `Event` | Display name. Slugified, this is the id (`Scrap Ooze` → `scrap_ooze`) and the `.tres` filename. |
| `Game` | The real game it's lifted from. Shows as "From: *game*" in the modal. |
| `Tier` | `All`, or a comma list of `Low` / `Medium` / `High` / `Insane`. |
| `Where` | **Leave blank.** An event fires after every game, so this answers nothing today. It stays wired (`Dead End` / `Any` / `Game`) for the per-location work. |
| `Requirement` | A gate on the run: `<stat> <op> <value>`, `%` reads against the max. `hp <= 70%`, `games >= 6`. Blank = always eligible. A gated event is skipped and stays in the bag. |
| `Trigger` | `After` (fires once the game at the node is played). ⚠ `Before` parses and is stored, but **nothing reads it yet**. Leave it `After` until that is wired up. |
| `Rarity` | `Common` / `Uncommon` / `Rare` — which bag it is dealt from. |
| `Image` | Art base name → `images2.0/events/<Image>.png`. Blank falls back to the de-spaced `Event`. |
| `Prompt` | The prose at the top of the modal. Blank is legal — a wordless event stacks its art *above* the choices instead of beside them (see "Art"). |
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
| `gain_hp N` / `gain_max_hp N` / `gain_empty_max_hp N` / `heal_full` | Health. `gain_max_hp` raises the cap **and heals by the same amount** — the container arrives full. `gain_empty_max_hp` is the half that doesn't heal, for the item that means an empty container (Hollow Heart). |
| `lose_hp N` / `lose_max_hp N` | The same, pointed the other way — except `lose_max_hp` **costs no Health**: it takes the room, and Health only moves when it no longer fits. A `lose_hp` that empties Health ends the run — no separate kill token. |
| `gain_gold N` / `lose_gold N` / `lose_gold all` | Gold. `all` empties the purse — the one amount settled when the choice is taken rather than when the `.tres` is written. |
| `gain_stat <verb> N` / `lose_stat <verb> N` | `bash`, `dash`, `push`, `transmute`, `scramble`, `bombs`, `keys`, `shields`. |
| `gain_loot N` | A loot drop — a scroll today, and widens on its own as more loot types exist. `gain_scroll N` names the scroll directly. |
| `apply_status <status> N` | A `statuses2.0` status on the player. |
| `random_item_choice N` | Pick 1 of N random items. |
| `gain_item <item_id>` | A **named** `items2.0` relic, handed straight over — the one token that says *which* item. The generator checks the id against the sheet. |
| `spawn_enemy [N] [tag=<t>]` | Conjures N enemies at the run's current difficulty onto the following stack. What every curse costs. `tag=` narrows the roll to the goal-enemies carrying that synergy tag (`spawn_enemy tag=robot 1` — Punch Off's Constructs); the generator checks the tag against the `enemies2.0` Tag column, and a tagged roll widens by difficulty rather than dropping the tag. |
| `trade_relic <slot>` | The Relic Trader's swap: one of your relics for one of his. Fills `<give>` / `<get>` in the choice's prose. |
| `obtain_item` | Pick **any** item in the catalogue. This is Wand of Wishing's picker — much stronger than a chest, use deliberately. |
| `nothing` | An explicit no-op. Write it where a blank cell would read as unfinished. |

And the event-only forms:

```
needs keys 1                           only offered if the player HAS it (a check, not a charge)
needs Immerse > 0                      only offered at this point in the event (names another Choice)
add_goal "<condition>" [for <n> games] -> <reward>
add_curse <curse_id> [for <n> games]
play_game tag=<tag> -> <reward>
chance <p>% -> <reward>
```

- **`needs <resource> <n>` only checks.** It does not deduct — a locked chest
  that costs a key is `needs keys 1; lose_stat keys 1; gain_chest medium 1`, with
  the gate and the charge written separately. Gate stats: `hp`, `max_hp`, `gold`,
  `games`, `keys`, `bombs`, `bash`, `dash`, `push`, `transmute`, `scramble`,
  `shields`.
- **`add_goal`** bolts an objective onto the next *n* games, in the same
  honour-system voice enemy goals use. Pays if met, costs nothing if not.
- **`add_curse`** is that inverted — an objective you want to *not* meet, which
  bills you every time you do. It takes an id from the **`curses2.0` tab**, so
  the curse is authored once and any event can hand out the same one.
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
passive bonus, so the Luck goes away with the item. The Donation Machine pays a
point on a 5% roll per coin. There is no cap.

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
cross-run tier list. What's still ahead:

- **The OBS companion HUD (§9)** — the design is stream-first: a slim always-on-top
  window showing health, shields, the current game + its goal, the follower stack,
  and the verb/consumable counts, reading the same autoloads the main window
  mutates. Deferred by decision until the mechanics lock; it is the largest
  unbuilt piece of the spec.
- **Overworld encounters** — deals, teleporters, and challenge rifts are authored
  (`data/encounters/*.tres`, `EncounterData`, its sheet + generator, and
  `GameState.encounter_requirement_met`), but nothing on the games-first board
  offers them yet. They need a place in the offering / between games. **Shops are
  no longer on this list** — they landed as their own thing at the ten hub games
  (§14), and what is left of the encounter sheet's two shopkeepers is flavour a
  hub's shop can adopt once the roster is authored.
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
- **Content depth** — the catalogs are thin next to the 846 games: 45 goal-enemies,
  37 bosses, 25 items (3 of them Boss relics, 1 an Event relic), 6 scrolls,
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
  Dash / Ride the Bus / Scroll of Teleportation.
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
