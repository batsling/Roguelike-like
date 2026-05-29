# Strategy Combat — Implementation Plan

Status: draft, agreed via design Q&A.
Scope: the strategy/tactical pillar of the Godot port. Sits alongside the existing action and deckbuilder pillars.

---

## Revision — playability pass (2026-05)

This pass supersedes parts of the original design below. Where they
conflict, this section wins.

### Movement / speed
- **Base speed = 4 tiles** for the player, and enemies match it for now
  (`BattleUnit.from_player` / `ENEMY_PRESETS`). Speed still doubles as the
  initiative weight, so a flat 4 means a uniform turn cadence until enemy
  speeds are differentiated again.
- **One move action per turn.** Movement no longer chains: committing a
  move (up to `speed` tiles) locks further movement for the turn
  (`BattleView._move_used`).

### Cards: uses + 3 slots (replaces the cooldown model)
The old "whole deck → abilities with cooldowns" model
(`AbilityPool` / `AbilityCooldownConfig`) is retired for the **player**.
Cooldown plumbing stays only for **enemy** intents (`unit.cooldowns`,
`tick_cooldowns`, `EnemyAI`).

- **Pre-combat loadout screen** (`BattleView` loadout overlay): the player
  sees the enemy + telegraphed intents and slots up to **3 cards** chosen
  from the run deck (non-basic, deduped — `CombatLoadout.available_from_deck`).
  Confirming calls `StrategyCombatSession.begin_battle()` to start the
  initiative engine (which `enter_combat` no longer auto-starts).
- **Uses, not cooldowns.** Each card has a use count
  (`CardData.max_uses`, default by rarity in
  `GameState.DEFAULT_CARD_USES_BY_RARITY = [4,4,3,2,2]`). Playing a card
  spends one use. **Uses are run-persistent**: stored on
  `GameState.card_uses` (keyed by card id), they deplete across combats and
  *save* across leaving/re-entering a strategy game within the run. Only
  refilled by "draw"-style effects (and future rest hooks). Basic
  Attack/Defend and mana spells are always available, so a depleted loadout
  never soft-locks a fight.
- **Per-turn economy: one card play baseline** (`_card_plays_remaining`,
  starts at 1). The reframed energy/draw effects:
  - `gain_energy:N` → **+N card plays this turn** (sets up multi-card turns).
  - `draw_cards:N` → **recharge N uses** on the slotted card(s) with the
    fewest current uses.
  - `discard_cards:N` / `lose_energy:N` → **−N card plays this turn** (tempo cost).

### Open follow-ups from this pass
- **Use refill points** (rest sites / shops / floor transitions) — uses
  currently only refill via draw effects; a between-fight refill path is
  likely wanted so long runs don't grind loadouts to zero.
- **Typed / equipment-backed slots** — slots are 3 generic slots picked
  from the deck for now; tying them to gear (cf. the action-mode
  `EquipmentScreen`) is a future option.
- **Decoupling move range from initiative speed**, once enemies need
  distinct initiative without also moving farther.

## Design summary

### Loop shape
- One procedurally generated rogue-style dungeon floor at a time (built on top of the existing `godot/scripts/strategy_prototype/`).
- Player explores: items, gold, lockable doors + keys, traps, stairs.
- Walking into a combat room triggers a transition into a tactical battle.
- After combat, the player returns to the floor; surviving loot stays in the room.
- Player defeat ends the run.

### Combat trigger
- "Room expands to battlefield": the source room's tiles map to a larger procedurally generated tactical grid. Items in the room are placed onto the battlefield ground (pickup-able). On combat end, surviving loot maps back to the room.

### Battlefield
- Square grid, size varies by encounter (small for trash, larger for elites/bosses).
- Procedural generation with terrain rules (minimum cover %, choke points for medium+).

### Turn order
- Speed-based initiative (Mewgenics/FFT-lite). Faster units act more often per round.

### Player turn — actions
On each of the player's turns:
1. **Move** up to `Speed` tiles.
2. **One** of (mutually exclusive):
   - **Basic Attack** — class-defined attack pattern, damage from the basic-strike card value.
   - **Defend** — block equal to the basic-defend card value.
3. **One Ability** — cast a single non-basic card from the deck. Free (no resource cost beyond cooldown). Cooldown-gated.
4. **Spells** — cast any number of learned spells from the spellbook, as long as mana is available. Each spell has a mana `cost` (from `SPELLS_DATA`).
5. **Dash** — once per combat, spend the Dash stat to immediately gain a bonus full turn after the current one ends.

Cooldowns tick at the start of the player's turn.

### Mana system (drives Spells, Mewgenics-inspired)
- `maxMana = 3 + (1 * CHA)`
- `manaRegen = 1 + floor(INT / 3)` per player turn
- Mana persists between turns, capped at `maxMana`.
- Base stats start at 0; baseline is `(maxMana = 3, regen = 1)`.
- Only the spellbook consumes mana. Abilities do not.

### Ability cooldown formula
Hybrid: formula default with per-card override.
- `cooldown = card.cooldown_override if set else (base + energy_cost * cost_weight + rarity_weight[rarity])`
- Tunable in one place; override field on the card resource for designer control.

### Enemies
- Hybrid model: internally a cooldown-based ability list. UI shows a telegraphed next-intent above the sprite (STS-style readability).
- Enemies use the same turn-engine and speed initiative.

### Defeat / rewards
- Defeat: run ends.
- Rewards: loot spawns across the floor naturally; the combat room's loot appears on the battlefield ground during combat (pickup-able) and persists after combat.

### Party
- Solo PC for now. Data model leaves room for allies (multi-unit player control) added later.

---

## Phased build plan

### Phase 1 — Floor foundations
Extend `strategy_prototype/` (already has Map, FOV, Entity, Item, MessageLog, TurnManager, autoloads):
- Remove bump-to-attack on the floor; entering an enemy room triggers combat instead.
- Add tile types: `DOOR_LOCKED`, `DOOR_OPEN`, `TRAP_HIDDEN`, `TRAP_REVEALED`.
- Add `Key` and `Gold` item types in `Item.gd`.
- Tag rooms at gen time: `start`, `combat`, `treasure`, `shop`, `stairs`.
- Lock-and-key placement: at least one key per locked door, placed in a reachable room.

### Phase 2 — Combat session model
New autoload `CombatSession`:
- `enter_combat(room: Rect2i, enemies: Array, floor_items: Array)`
- `exit_combat(result)` — collapses battlefield, ports surviving items back into the room.
- Phase enum: `OVERWORLD → COMBAT_TRANSITION_IN → COMBAT → COMBAT_TRANSITION_OUT → OVERWORLD`.
- Stub scene swap: at first this just shows a placeholder battle scene and returns when a "win" button is pressed, so the loop is testable before the real combat is built.

> **Recommended session break point.** Phases 1 + 2 leave a working overworld where entering an enemy room transitions into a stub combat and back, with loot persistence. The strategy combat content (Phases 3+) can be built in a fresh session without losing context.

### Phase 3 — Tactical battlefield generation
New `BattleMap.gd` (`godot/scripts/strategy/combat/BattleMap.gd`):
- Inputs: source room rect, encounter (sized into S/M/L), biome, items.
- Procedural rules: min cover %, choke points for M+, walkable paths between spawn zones.
- Spawn zones: player edge (south), enemy edge (north).
- Map source-room items onto battlefield tiles (scaled positions).
- `CombatSession` builds a `BattleMap` at `enter_combat` and exposes it via `combat_started(room, encounter, battle_map)`. The placeholder overlay renders an ASCII preview until Phase 4-5 ships the real renderer.

> **Session break point.** Phase 3 produces a data-complete battlefield (terrain + spawn zones + mapped items). Phase 4 turns it into a live battle by adding the initiative engine.

### Phase 4 — Initiative and turn engine
New `Unit.gd` (class `BattleUnit`, `extends Resource`) and `BattleTurnManager.gd`
under `godot/scripts/strategy/combat/`:
- `BattleUnit` fields: `unit_name, is_player, max_hp, hp, speed, dash_available,
  basic_attack_def, block, position, int_stat, cha_stat, mana, max_mana,
  mana_regen, cooldowns, act_counter`. Factory helpers build units from the
  overworld player (`from_player`) and enemy kind strings (`from_enemy_kind`,
  with stat presets for rat/snake/orc/troll).
- Speed-based initiative (Mewgenics/FFT-lite): every tick adds `speed` to
  each living unit's `act_counter`. First counter to cross
  `ACT_THRESHOLD = 100` takes a turn; the threshold is *subtracted* (not
  zeroed) so excess speed carries over. Higher speed → more turns per round.
- On unit's turn: emit `unit_turn_started`. On `end_current_turn`: tick the
  unit's cooldowns, clear its `block`, emit `unit_turn_ended`, then check
  battle end (player down → `defeat`, all enemies down → `victory`) before
  advancing.
- Player turn start: `mana = min(mana + mana_regen, max_mana)`.
- Dash: `consume_dash()` queues a single bonus turn for the current unit
  ahead of the natural initiative cycle.
- `CombatSession` now builds units and a turn manager at `enter_combat`,
  exposes them via `combat_started(room, encounter, battle_map, turn_manager)`,
  and listens to `battle_ended` to drive the outer overworld loop.

### Phase 5 — Player turn UI/UX
New `BattleView.gd` + `BattleGridView.gd` (`godot/scripts/strategy/combat/`).
The script-only ASCII placeholder is retired.
- `BattleGridView` (Control): draws tiles (floor/wall/cover), items, units,
  HP bars, the active-unit ring, reachable-tile overlay in move mode, path
  preview, and target rings in attack mode. 4-directional BFS movement;
  movement budget = `unit.speed`. Emits `move_requested(path)` and
  `attack_requested(target)`.
- `BattleView` (CanvasLayer): hosts the grid view, an initiative panel,
  status line, and action bar:
  - `[Move]` — opens reachability; chained moves allowed until budget = 0.
  - `[Attack]` / `[Defend]` — mutually exclusive per turn (`_action_used`).
  - `[Ability]` — opens picker (Phase-6 stub; closes immediately).
  - `[Spellbook]` — opens picker (Phase-6 stub).
  - `[Dash]` — enabled if `dash_available`; consumes it for a bonus turn.
  - `[End Turn]`.
- Damage applies through `block` first; killing the last enemy invokes
  `BattleTurnManager.check_battle_end_now()` so combat wraps without
  forcing the player to press End Turn.

### Phase 6 — Cards → Abilities; Spells → Spellbook
`AbilityPool.gd` (`godot/scripts/strategy/combat/`):
- Built from `GameState.deck` at combat start; cards tagged `strike`
  or `defend` are filtered (they live on the basic Attack/Defend
  actions). Duplicates dedupe by id.
- Cooldown = `card.cooldown_override` if `>= 0`, else
  `AbilityCooldownConfig.compute(card)` =
  `base + max(0, cost) * cost_weight + rarity_weights[rarity]` (defaults
  `base=2, cost_weight=1, rarity_weights=[0,0,1,2,3]`).
- Casting flow: open picker → pick ability → if any effect targets
  `enemy`, enter `UNIT_TARGET` mode for an enemy click → resolve via
  the shared `EffectSystem` (BattleView implements `deal_damage`,
  `gain_block`, `heal`) → `set_cooldown` (writes `base_cooldown + 1`
  so the end-of-turn tick lines up). Limited to one ability per turn
  (`_ability_used`).

`Spellbook.gd` (`godot/scripts/strategy/combat/`):
- Built from `GameState.learned_spells` (Array of StringName ids
  resolved via `SpellsCatalog.gd`, which ports the legacy
  `SPELLS_DATA` to `SpellData` resources with structured effects).
- Each spell has `cost` (mana) + structured `effects`.
- Casting flow: open picker → pick spell → spend mana → if
  `target_kind` is `enemy`/`friendly`, prompt for a click → resolve
  effects (same EffectSystem path as abilities; `dmg_fraction_max_hp`
  is registered locally for Abyss/Infinity). Unlimited casts per
  turn while mana lasts; `BattleTurnManager` handles turn-start
  regen.

Plumbing:
- `CardData` gains `cooldown_override: int = -1`.
- `GameState` gains `learned_spells: Array[StringName]` (resets with
  the run).
- `SpellData.gd` + `AbilityCooldownConfig.gd` resources land under
  `scripts/resources/`.
- `BattleGridView` gains a `UNIT_TARGET` mode with `TargetFilter`
  (enemy / ally / any) and right-click cancel; emits
  `target_requested` / `target_cancelled`.
- `BattleView` builds the pool + spellbook at `set_encounter`, holds
  the `_pending_*` state during targeting, and replaces the Phase-5
  stub dialogs with scrollable pickers that show cooldown / mana
  costs.
- For the standalone strategy prototype, `strategy_prototype/Main.gd`
  seeds `GameState.deck` with the existing demo cards and
  `GameState.learned_spells` with `SpellsCatalog.default_starter_ids()`
  so the pickers have content immediately.

### Phase 7 — Enemy AI with hybrid intents
Tactical AI lives under `godot/scripts/strategy/combat/` (the overworld
`strategy_prototype/EnemyAI.gd` is kept for the legacy bump-attack flow
and unrelated to combat AI):

- `EnemyIntent.gd` — one declarative action: id, display name, short
  icon glyph, range, cooldown, priority, target_kind, structured
  effects, and an optional `condition` ("self_low_hp" for now).
- `EnemyCatalog.gd` — per-archetype intent lists (rat, snake, orc,
  troll). Unknown archetypes get a single melee fallback built from the
  unit's `basic_attack_def`.
- `EnemyAI.gd` — RefCounted attached to each non-player `BattleUnit`
  via `unit.ai`. `plan_next(units)` picks the highest-priority
  off-cooldown intent with a valid target and writes a telegraph dict
  onto `unit.intent_telegraph` (`{id, name, icon, value, color}`).
  `execute_turn(scene, units, battle_map)` resolves a fresh target,
  BFS-steps into range (capped at `unit.speed`), applies effects
  through `BattleView.apply_effects` (same EffectSystem path as the
  player), and writes `unit.cooldowns[intent.id] = cooldown + 1` so
  the engine's end-of-turn tick lines up.

Wiring:
- `BattleUnit` gains runtime fields `ai` and `intent_telegraph`.
- `CombatSession.enter_combat` attaches an `EnemyAI` to each enemy
  (`EnemyAI.build_for(unit, kind)`) and calls `plan_next` before
  emitting `combat_started`, so the player sees telegraphs from turn 1.
- `BattleView._auto_end_enemy_turn` is now the AI driver: execute →
  refresh HUD → `check_battle_end_now` → `plan_next` → `end_current_turn`.
- `BattleGridView` draws a compact `icon+value` badge above each
  living enemy, colored by intent kind (red attack, orange AoE,
  green self/buff). The initiative panel adds a `next:` line per
  enemy with the full intent name.

### Phase 8 — Loot persistence
- Items on the battlefield are real entities (`StrategyItem` instances
  stored in `BattleMap.items` as `{item, pos, source_pos}` entries; the
  `item` reference is shared with `StrategyState.map.items` for room
  originals).
- Pickup during combat: when the player's move path passes over an item
  tile, `BattleView._try_pickup_at` collects it. Gold goes to the shared
  `GameState.gold` (live sync across sections); keys go to
  `StrategyState.keys` (strategy-only mechanic); other items go to
  `StrategyState.player.inventory` while there's room. Items the player
  takes are removed from both the battlefield and the overworld items
  list so they don't double-persist.
- Enemy loot drops: `BattleView._apply_damage` detects the alive →
  dead transition for non-player units and rolls
  `ENEMY_LOOT_TABLE` (per-archetype gold/item odds). Drops are added
  to the battlefield at `unit.position` via `BattleMap.add_dropped_item`
  with a sentinel `source_pos = (-1, -1)`.
- Persistence back: `CombatSession._sync_loot_back` runs in
  `resolve_combat` after the player-HP sync. Each surviving battle
  entry's tactical position is mapped back to a floor tile inside the
  source room — preferring the original `source_pos` when still valid,
  otherwise the inverse-mapped tile from
  `BattleMap.battle_pos_to_source`, otherwise a spiral search. New
  drops get appended to `StrategyState.map.items`; room originals
  just have their `grid_pos` updated.

### Phase 9 — Death / end-of-run
- `Main._on_player_defeated` is the single end-of-run entry point; both
  the `CombatSession` `combat_ended("defeat")` signal and overworld
  death (`_check_death` after trap damage, etc.) route through it.
- Sets `StrategyState.phase = DEAD`, logs the death, and shows a
  defeat overlay modeled on `DeckbuilderCombat._show_end_overlay`
  (dimmed background, centered panel, "DEFEAT" title, current floor,
  Continue/Restart button).
- `_new_game` clears the defeat overlay (and any lingering battle
  overlay) before resetting `StrategyState`, so restart is clean.

### Project integration — overworld ↔ strategy
- The strategy prototype scene now obeys the same close-on-finish
  contract as `ActionFloor`: `signal closed(was_victory, target_game_id)`
  + `target_game_id: StringName` field. Project `Main.gd` routes
  `GameData.GameType.STRATEGY` portals to it via `_show_strategy_floor`
  and listens for `closed` to return to the overworld with the standard
  victory/defeat outcome.
- One strategy "game" = one roguelike floor. The staircase calls
  `_close_floor(true)`. Multi-floor descent only happens in standalone
  mode (running the scene from the editor).
- Shared vitals: HP and gold live on the run-wide `GameState`. Entry
  reads `GameState.max_hp/hp` into the strategy player; gold pickups
  (overworld + combat) call `GameState.change_gold` directly so the
  number is live across sections; `_sync_vitals_to_gamestate` pushes
  the strategy player's HP back to `GameState.set_hp` on close.
- Cards and learned spells are already shared (the Phase 6
  `AbilityPool` and `Spellbook` read from `GameState.deck` /
  `GameState.learned_spells`). The standalone bootstrap applies the
  Ironclad character and seeds the demo loadout so the prototype boots
  into a playable state from the editor.
- Strategy-local state stays local: `StrategyState.keys`,
  `StrategyEntity.inventory` (`StrategyItem` types — distinct from the
  deckbuilder's `ItemData`), `dungeon_floor`, generated map/entities.
- The defeat overlay's button text is mode-aware: "Continue" (closes
  to overworld for a project-level run reset) when embedded,
  "Restart run" (in-place `_new_game`) when standalone. `[R]` is
  standalone-only for the same reason.

### Phase 10 — Polish
- Camera transition animation for room→battlefield.
- Trap reveal animations.
- Allies: extend `Unit` for multi-unit player control; control switches per initiative tick. Skeleton only; full allies later.

---

## Open items deferred to later sessions
- Status effects system (poison, burn, weakness, etc.) — likely reuses the deckbuilder's status registry.
- Trap variety + DC checks.
- Shops on the floor.
- Boss encounters (likely a fixed authored map per boss).
- Meta-progression hooks.

## File layout (target)

```
godot/
  scripts/strategy/
    overworld/
      FloorMap.gd            (extends current Map.gd; doors, keys, traps)
      FloorMain.gd           (extends current Main.gd; combat trigger)
      Door.gd
      Trap.gd
    combat/
      CombatSession.gd        (autoload)
      BattleMap.gd
      BattleTurnManager.gd
      Unit.gd
      AbilityPool.gd
      Spellbook.gd
      EnemyIntent.gd
      effects/                (shared card/spell effect runner)
    resources/
      SpellData.gd
      AbilityCooldownConfig.gd
  scenes/strategy/
    overworld/FloorScene.tscn
    combat/BattleScene.tscn
```

(Existing `strategy_prototype/` is preserved during the transition; new code lives under `strategy/` and the prototype is retired once the new pieces are stable.)
