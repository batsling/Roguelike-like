# Games-First Redesign — implementation plan (Phase 1: data foundation)

Companion to `games-first-redesign.md` (the design spec). That doc says *what*
the game becomes; this doc says *how* we build it and, critically, records the
scoping decisions taken in the discovery pass so the work can start without
re-litigating them.

Status: **decisions locked, Phase 1 scoped.** Written 2026-07-26.

---

## 1. Decisions locked in discovery

Ten forks were resolved before any code:

| # | Decision | Choice |
|---|---|---|
| 1 | **First milestone** | **Data foundation first** — resource schemas, generators, `images2.0/` scaffold, the tiny health/block/verb run-state layer, and the `game_beaten` item hook. Mechanics/UI are later milestones. |
| 2 | **Combat cut (§11)** | **Deferred.** Old deckbuilder/action/strategy code stays in place; 2.0 is built alongside it. Archive-tag + delete happens once the new loop works. |
| 3 | **ScrollSystem** | **Rewrite in place** to the 2.0 Preference + identification model (drops the old d20/crit-tier combat model). |
| 4 | **Content authoring** | I author the `items2.0.Effect` DSL from the Descriptions and use placeholder/`Unidentified` fallback art for missing PNGs. I do **not** invent new enemies/bosses/characters — that stays the owner's content call. |
| 5 | **Character schema** | **Extend `CharacterData` in place** with the 2.0 fields (small health + bash/dash/transmute/scramble/bombs/keys). Reuses the level-up mechanic that already lives on `CharacterData`. |
| 6 | **Data layout** | **Parallel `data/*2.0/` folders** (`data/characters2.0/`, `items2.0/`, `enemies2.0/`, `scrolls2.0/`). Mirrors the `images2.0/` split; old `data/` untouched. |
| 7 | **Run state** | **Extend `GameState`** with the 2.0 fields (Health, Max Health, Block, verb/consumable counts). Keeps §9's "the same GameState/autoloads" assumption true. |
| 8 | **Item Effect depth** | **Author the full structured Effect for every item now.** Add the small buildable handlers (verb grants, block, `game_beaten` wiring); leave a clearly-marked inert/TODO stub for effects that need not-yet-built systems (teleport-by-type, obtain-any-item, global enemy modifiers). |
| 9 | **Enemy schema** | **New `GoalEnemyData` resource** (Name/Type/Difficulty/Game/Health/Damage/GoalType/Goal/Ability/Tag/File). Old `EnemyData` (a combat stat block, on the cut list) is left untouched. |
| 10 | **Scroll schema** | **Rewrite `ScrollData` + `generate_scroll_tres.py` in place** to Preference + single effect + identification. Consequence: the old 4-tier combat-scroll behavior is gone even before the formal combat cut — accepted. |

---

## 2. What already exists (the reuse map, verified)

Confirmed live in the codebase — the redesign leans on these and they are real:

- **`TriggerBus.game_beaten`** — **already declared *and emitted*** (`Overworld.gd:1021`
  fires it after a game is beaten; Stats/GameState/Notifications already listen).
  The spec's "main new trigger to add" is *already there*. Phase 1 only needs to
  hang 2.0 item triggers on it — no new signal.
- **`EffectSystem`** handlers present: `block`, `gain_hp`, `gain_max_hp`,
  `gain_chest`, `gain_stat` (routes through `GameState.grant_run_stat`).
- **`GameState`**: `grant_run_stat(stat, value)`, `dash_charges`,
  `identified_scroll_types`, `grant_chest(count)` all exist.
- **`generate_item_tres.py`** already compiles an `Effect`-column DSL into
  `triggers`/`stat_bonuses` — the 2.0 item authoring reuses this exact grammar.
- **`ItemData.ItemKind`** = PASSIVE/TRIGGERED/USABLE/WEAPON/SCALING/PICKUP/CHARGED —
  maps 1:1 to `items2.0.Type` (Pickup/Triggered/Charged/Usable/Passive). No new
  item resource needed; extend in place.
- **Level-up**: `CharacterData.level_up_condition/level_up_stats/level_up_reward_type`
  + the verification-modal Yes/No + Crown (`bonus_level_up_chance`) + Snowball
  (`stat_gain_bonus`) + the Perfect-a-game path (`perfect_aware`/`perfect_effects`).
- **`PotionSystem`** identification pattern — the template `ScrollSystem` mirrors.
- **Chests**: `GameState.grant_chest` → `RewardScreen` (`BASE_ITEM_CHOICES = 2`).

**Gaps confirmed:** no `images2.0/` folder; no 2.0 generators/schemas; `CharacterData`
& `EnemyData` & `ScrollData` are combat-shaped; `items2.0.Effect` column empty;
`enemies2.0` has only 4 rows (3 Deckbuilder + 1 Action, no Traditional/Strategy,
no bosses); several `scrolls2.0`/enemy `File` cells blank with no source PNGs.

---

## 3. Phase 1 work breakdown (data foundation)

Grouped by area; each item is a concrete deliverable.

### 3.1 Resource schemas (`scripts/resources/`)
- **`CharacterData.gd`** — add 2.0 fields: `start_health:int`, `start_max_health:int`,
  and verb/consumable starts `bash/dash/transmute/scramble/bombs/keys:int`. Existing
  combat fields stay (unused by 2.0 chars until the cut).
- **`GoalEnemyData.gd`** *(new)* — `id, display_name, game_type (Action/Deckbuilder/
  Traditional/Strategy), difficulty (Low/Medium/High + Boss later), source_game,
  health:int, damage:int, goal_type (Bounty/Restriction/Discovery), goal:String,
  ability:StringName, tag:StringName, file:String, image:Texture2D`.
- **`ScrollData.gd`** — rewrite: replace the 4 outcome-tier fields with
  `preference (Positive/Negative/Neutral)`, a single structured `effect`, plus the
  identification-facing `file`/`display_name`. Keep `id`, `source_game`.
- **`ItemData.gd`** — no schema change expected (kinds already map); confirm
  multi-Type rows (`"Pickup, Triggered"`) round-trip.

### 3.2 Generators (`tools/`)
- **`generate_character2_tres.py`** — read `characters2.0` → `data/characters2.0/*.tres`.
- **`generate_item2_tres.py`** — read `items2.0` → `data/items2.0/*.tres`, compiling
  the (newly authored) `Effect` column via the existing item DSL. Art path →
  `images2.0/items/<File>.png`.
- **`generate_goal_enemy_tres.py`** *(new)* — read `enemies2.0` → `data/enemies2.0/*.tres`.
- **`generate_scroll_tres.py`** — rewrite to read `scrolls2.0` → `data/scrolls2.0/*.tres`,
  Preference + single-effect DSL, art → `images2.0/scrolls/`.
- New generators are **separate scripts** (old generators keep working on old sheets).

### 3.3 Content authoring (sheet edits, mine per decision #4)
- **`items2.0.Effect`** — author all 14 rows in the item DSL. Handlers that exist →
  functional now; effects needing unbuilt systems → structurally authored + `# TODO`
  inert marker (Ride the Bus teleport-by-type, Wand of Wishing obtain-item, Alien
  Baby global "+1 enemy Health", Unstable Genome 3-item choice).

### 3.4 Autoloads
- **`Data.gd`** — add `_load_dir` calls for the four `data/*2.0/` folders + getters
  (`get_character2`/`get_item2`/`get_goal_enemy`/`get_scroll` repoint).
- **`GameState.gd`** — add 2.0 run-state fields: `health2/max_health2/block2` and
  `bash/transmute/scramble/bombs/keys` counts (dash reuses `dash_charges`). Extend
  `grant_run_stat` vocabulary to `bash/transmute/scramble/bombs/keys`.
- **`ScrollSystem.gd`** — rewrite to the 2.0 model: identification (reuse existing
  `is_identified`/`identify`/`unidentify`) + Preference + single-effect apply +
  the **Stun** enemy-state primitive (deferred wiring until the enemy stack exists,
  but the API lands here).
- **`EffectSystem.gd`** — extend `gain_stat` backing-field resolution to the new
  verbs; add `game_beaten`-driven item dispatch if not already covered.

### 3.5 Art scaffold
- Create `images2.0/{characters,items,enemies,scrolls}/` with the shared
  `Unidentified.png` fallback under `scrolls/`. Generators point art lookups here;
  missing PNGs fall back to `Unidentified`/placeholder rather than a broken texture.

### 3.6 Tests
- Add/extend GUT tests: generator round-trip (sheet → .tres loads), `Data` getters
  return the 2.0 resources, `grant_run_stat` handles the new verbs, item DSL parse
  for the authored `items2.0.Effect` rows.

---

## 4. Explicitly NOT in Phase 1 (later milestones)

The play-session resolver (accept game → report result → drop/damage/level-up),
the enemy **stack + one-game-grace timing** (§7.2), Bash/Transmute/Dash/Scramble
board mechanics, Bomb/Key application, the boss layer, and the **OBS companion HUD**
(§9) are the *mechanics* milestone. The combat cut (§11) is its own pass.

---

## 4a. Phase 1 — what actually shipped (and deviations)

Phase 1 is **implemented and landed** (all 804 GUT tests green, including 25 new
data-foundation tests in `test/test_redesign2.gd`). Three scope refinements were
forced by what the codebase actually looked like:

1. **ScrollSystem rewrite deferred; ScrollData extended additively.** The
   existing `ScrollSystem`/`ScrollData` API is consumed all over the *deferred*
   combat code (`ActionCombat`, `DeckbuilderCombat`, `ScrollUseModal`, `Backpack`,
   `Overworld`, and `Data`'s reward roller via `rarity_index()`). Rewriting them
   in place *now* would break the build, violating decision #2 (nothing breaks).
   So `ScrollData` gained the 2.0 fields (`effect` list + the existing
   `preference`) **additively** (old 4-tier API intact), a **new**
   `generate_scroll2_tres.py` emits `data/scrolls2.0/`, and the actual
   ScrollSystem rewrite (+ removing the old fields) moves to the mechanics
   milestone, done together with updating/cutting its combat consumers.
2. **`game_beaten` needed no new signal or trigger.** It already exists on
   `TriggerBus` **and is emitted** (`Overworld.gd:1021`). The only wiring needed
   was one line in `GameState._on_game_beaten` routing owned items through the
   pre-existing scene-less `fire_run_item_triggers()` — Anchor/Burning Blood/
   Meat-on-the-Bone now fire out of combat with no new machinery.
3. **2.0 Health/Max Health reuse `hp`/`max_hp`** (set from the character's
   `base_max_hp`), so `gain_hp`/`gain_max_hp`/Meat-on-the-Bone's if_hp/the
   level-up `max_hp` path all work unchanged. Only **Block** and the five verbs
   (bash/transmute/scramble/bombs/keys) are genuinely new GameState fields; Dash
   reuses `dash_charges`. Item verb/block grants route through the existing
   `gain_stat` → `grant_run_stat` path (its stat vocabulary was extended).

Files: `GoalEnemyData.gd` (new); `CharacterData.gd`/`ScrollData.gd`/`GameState.gd`/
`Data.gd` (extended); `generate_item_tres.py` (refactored to be reusable + add
`game_beaten`); `generate_{character2,goal_enemy,item2,scroll2}_tres.py` (new);
`data/{characters,items,enemies,scrolls}2.0/` (generated); `images2.0/` tree with
the shared `Unidentified.png`; `test/test_redesign2.gd`. Item `Effect` and scroll
`Effect` columns authored into `tools/Roguelikes.xlsx`.

## 4b. Phase 2a — the loop resolution engine (shipped)

The **headless core of the mechanics milestone** is implemented and landed (822
GUT tests green, incl. 18 in `test/test_gameloop2.gd`). This is the no-combat
replacement for the combat scenes, built scene-free/UI-free so it's unit-testable
and can later be driven by both the overworld window and the OBS HUD.

**`GameLoop2` autoload** (`scripts/autoload/GameLoop2.gd`) owns the **enemy stack
state machine** on top of GameState's tiny resources:
- `choose_game(enemy)` — the enemy spawns on choose (§7.2), returns an instance
  handle so duplicate enemy types stay distinct.
- `beat_game(goal_met, fulfilled)` — the core resolve: (1) old-goal fulfilments
  defeat + drop, (2) already-stacked enemies attack (Block then Health), (3) the
  current enemy defeats+drops or joins the stack. Step ordering **is** the
  one-game grace — a freshly-stacked enemy can't hit the game it stacked.
- `bomb(instance)` (normal-only, boss-immune, spends a bomb), `stun(instance)`
  (skips the next attack), `fulfill(instance)`, `clear_amulet()` (win),
  `roll_enemy(type, tier)` (type+tier filter with widening), and HUD helpers
  (`stacked_damage_per_game`, `stack_size`). Signals: `loop_changed`,
  `enemy_defeated`, `player_hit`, `run_lost`, `run_won`.

- `start_run(character)` — the single run-start entry point: wipes run state,
  applies the character's 2.0 loadout via `GameState.apply_character2` (tiny
  Health + verb counts + starting items through the normal `add_item` acquire
  path, so pickups fire), and clears the stack.
- `scramble()` — the D6 verb (§4): rerolls the current game's enemy within the
  same type+tier, spending a scramble charge.

A full run can be driven end-to-end through `GameLoop2` + `GameState` with **no
UI** — the loop is playable at the logic level and fully unit-tested (827 total
GUT tests). Drops bank a chest via the existing `grant_chest`; the tier →
chest-size mapping (§8.2) is left to the RewardScreen wiring in the
overworld-integration pass.

**Board verbs (pool logic) also landed** as headless, combat-safe operations on
`GameLoop2`: `bash_game` (destroy a game out of the pool for the run),
`transmute_game` (swap for a random same-type off-graph game), and a
`game_type_key` adapter that promotes today's `deckbuilder`/`traditional` tags to
the §6.1 four-type model **without re-authoring the 737 games** (so the live
combat type routing is untouched). Dash already exists on the overworld;
Scramble is on GameLoop2. So all four verbs' logic is done and tested.

**Not yet built — the overworld-integration sub-phase (UI-coupled, needs the
decisions below):** wiring GameLoop2 into the actual map scene (drawing games
that skip `is_bashed`, applying transmute/bash to nodes, choosing a game →
`choose_game_of_type(game_type_key(game), tier)`), the post-game verification
modal as the self-report UI, the boss layer (spawn-on-difficulty-change +
content), the OBS companion HUD, and the still-deferred ScrollSystem rewrite
(bundled with the combat cut so it doesn't break the build).

The headless core is now complete: **a full run is playable through
`GameLoop2` + `GameState` with zero UI**, covered by 833 GUT tests.

## 4c. PlaySession2 — a playable harness (shipped)

`scenes/redesign2/PlaySession2.tscn` (+ `scripts/redesign2/PlaySession2.gd`) is a
minimal, **combat-safe, additive** play harness that drives `GameLoop2` from
buttons: pick a game type (spawns its goal-enemy at the run's tier), report the
result (Goal MET / NOT met), and use the verbs (Scramble / Bomb / Stun) — with a
live readout of Health/Block, the verb counts, the current enemy + its goal, and
the following-enemy stack. It does not touch the overworld graph or combat
scenes. It is both a way to play/validate the loop today **and the seed of the
real overworld panel + the OBS companion HUD** (§9): the whole UI just reads
`GameLoop2` + `GameState` and refreshes on `loop_changed`. Built in code and
covered by `test/test_playsession2.gd` (drives a run through the same public
methods the buttons call). Total suite: 838 GUT tests green.

To run it, open `scenes/redesign2/PlaySession2.tscn` as the main scene in the
editor (or set it as the run target). It is not yet wired into the main menu.

## 4d. Bosses (shipped)

The owner authored a `bosses2.0` sheet (12 bosses) and dropped art into
`images2.0/bosses/`. Bosses use the **same `GoalEnemyData` resource** with a new
`boss = true` flag, so the loop treats them uniformly (they stack, follow, drop,
and are bomb-immune via `is_boss()`), while carrying the §7.1 boss traits: higher
damage (3/5/7/9, above the 1–3 band), a tier gate that now reaches **Insane**
(The Creator), and a new **Fetch** goal type (flows through as a free
`goal_type`). Key refactor: `GoalEnemyData.Difficulty` became
`LOW/MEDIUM/HIGH/INSANE` (matching `RunDifficulty.Tier`) and boss-ness moved to
its own `boss` flag — tier and boss are now orthogonal.

Pipeline: `generate_goal_enemy_tres.py` was made reusable and a thin
`generate_boss_tres.py` emits `data/bosses2.0/*.tres` (art → `images2.0/bosses/`).
`Data` loads them into a separate `_bosses` pool with `get_boss`/`all_bosses`;
`GameLoop2.roll_boss`/`choose_boss` roll from it (reaching Insane), and
`roll_enemy` is guaranteed boss-free. PlaySession2 shows a ☠ BOSS marker and a
boss-spawn button. Total suite: 846 GUT tests green.

## 4e. Overworld2 — the click-to-choose overworld (shipped)

The first slice of the **overworld-integration** milestone. `scenes/redesign2/
Overworld2.tscn` (+ `scripts/redesign2/Overworld2.gd`) replaces the old
walk-around-and-open-a-door overworld with a **click-to-choose board**, and takes
over the main-menu "Games-First" button from `PlaySession2` (which stays in the
repo as the headless harness). It is still a thin, additive view over
`GameLoop2` + `GameState` — combat and the live `Overworld.gd` are untouched
(decision #2).

What it does, matching the owner's UX direction:
- **No walker, no doors.** The reachable games are shown as **cards: the game's
  cover art with its name below** (falling back to the name when a cover is
  missing). Clicking a card travels there.
- **Hover previews the goal-enemy** that game would spawn — its **art**
  (`GoalEnemyData.image`) beside its name, goal (type + text), and
  type/tier/damage; the same art shows on the now-playing panel once chosen.
  (Bosses have art today; normal-enemy PNGs are a pending owner drop, §5 Q5, and
  fall back to a blank slot until then.) The enemy is **rolled up-front** per card
  so the hover and the enemy that actually spawns on click are the *same* roll
  (`roll_enemy` → stored → `choose_game`).
- **Difficulty gate = boss round (§7.1).** Every `RunDifficulty.GAMES_PER_TIER`
  (3) games a **"⚠ BOSS INCOMING ⚠"** banner shows above the choices and every
  card spawns a **boss** (`roll_boss`). The boss is the **capstone of the tier
  just played**, not the opener of the next one: the game-4 boss is **Low** and
  beating it is what advances the run to Medium, so a boss rolls at
  `tier_for(games_played - 1)` (`_current_tier()`), one below the normal-game
  formula, and the HUD shows that tier during the round. Normal games in between
  use the plain `tier_for(games_played)`, so they land on the *new* tier right
  after each boss. Once the run reaches **Insane** the cap holds, so Insane bosses
  keep appearing every 3 games. The boss is tied to the **gate, not the game**: `_is_boss_round()` reads
  only `games_played`, so bash/transmute (and a future teleport) can change *which*
  game you play at the gate but you still face a boss — a bashed slot backfills
  with another boss card, and a transmuted game rolls a boss too. (Owner call:
  boss rounds are escapable-but-still-a-boss, superseding the earlier
  "unskippable" default; resolves §5 Q1.)
- **Limited offering + board verbs.** The offering is capped (`OFFER_COUNT = 5`,
  the amulet always kept when reachable) in a stable position-seeded order — Dash
  (§4) is the verb meant to bypass it (its UI is a later slice). **Bash** destroys
  a card's game out of the pool; **Transmute** swaps a card for an off-graph
  same-type game via a per-position override map (keeping the graph slot). Both
  are available on boss rounds too (see above).
- **Self-report + resolve.** Choosing a game shows the honour-system report (Beat
  → Goal MET / NOT met) that drives `GameLoop2.beat_game`, advances
  `GameState.games_played`, banks drops as chests, and rebuilds the next offering.
  The amulet card + goal-met wins the run; a lethal stack hit loses it.

Run bootstrap reuses `RunGraph.pick_amulet_and_starts` for the start/amulet graph
and `GameLoop2.start_run` for the 2.0 character loadout. Covered by
`test/test_overworld2.gd` (boots a graph, picks/reports, boss round, bash,
boss-round bash lockout). Total suite: 853 GUT tests green.

**Next slices (unchanged):** the richer verification-modal self-report UX (this
slice uses plain buttons), the Dash "pick any connected game" UI, the OBS
companion HUD (§9), and the still-deferred ScrollSystem rewrite bundled with the
combat cut.

## 5. Design questions still open (needed before the mechanics milestone)

Not blocking Phase 1, but must be answered before the loop is built:

1. **Boss escapes & damage (§7.1/§12.1)** — are scramble/bash allowed on a boss
   node, or are difficulty-gate bosses fully unskippable? Exact boss damage value
   (above the 1–3 band)?
2. **Honour-system input UX** — with no simulated combat, the *whole* loop is
   self-report. Exact per-game flow for "did you beat the game? / did you meet the
   goal?" (reuse the verification modal, but the 2.0 wording/flow needs authoring).
3. **Enemy `Ability` column (§12.3)** — all `N/A` today; reserve for later specials
   or drop the column?
4. **Content depth** — only 4 enemies exist (no Traditional/Strategy, no bosses).
   Owner to author more per type/tier before the loop feels complete.
5. **Art** — no 2.0 PNGs exist yet; Phase 1 ships placeholder/`Unidentified`
   fallbacks. Real art is an owner drop into `images2.0/`.
6. **OBS HUD (§9)** — architecture (Godot `Window` vs always-on-top scene) + layout,
   deferred by the spec until mechanics lock.
