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
