# Strategy Combat — Implementation Plan

Status: draft, agreed via design Q&A.
Scope: the strategy/tactical pillar of the Godot port. Sits alongside the existing action and deckbuilder pillars.

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
New `BattleMap.gd`:
- Inputs: source room rect, encounter size class (S/M/L), biome.
- Procedural rules: min cover %, choke points for M+, walkable paths between spawn zones.
- Spawn zones: player edge, enemy edge.
- Map source-room items onto battlefield tiles (scaled positions).

### Phase 4 — Initiative and turn engine
New `BattleTurnManager.gd`:
- `Unit` resource: `max_hp, hp, speed, dash_available, basic_attack_def, block, position, int_stat, cha_stat, mana, max_mana, mana_regen`.
- Speed-based initiative: each unit has an act counter that ticks per round; when it overflows by its speed it gets a turn. Higher speed = more turns per round.
- On unit's turn: emit `unit_turn_started`. On end: tick that unit's cooldowns.
- Player turn start: apply `mana = min(mana + mana_regen, max_mana)`.

### Phase 5 — Player turn UI/UX
- Grid input: highlight reachable tiles within `Speed`, click to move (path-preview).
- Action bar:
  - `[Attack]` / `[Defend]` — mutually exclusive per turn (`action_used` flag).
  - `[Ability]` — opens ability picker showing all non-basic deck cards with cooldown status. Pick one (or pass) per turn.
  - `[Spellbook]` — list of learned spells with mana costs. Cast any number while mana allows.
  - `[Dash]` — enabled if `dash_available`; consumes it for a bonus turn.
  - `[End Turn]`.

### Phase 6 — Cards → Abilities; Spells → Spellbook
New `AbilityPool.gd`:
- Built from the player's deck at combat start: filter out basic strikes/defends.
- Computes each ability's cooldown (formula or override).
- Casting flow: select ability → if targeted, enter targeting mode → resolve via shared card-effect runner → set cooldown.

New `Spellbook.gd`:
- Built from `gameState.spells` (port `SPELLS_DATA` to a Godot resource).
- Each spell has `cost` (mana), effects.
- Casting flow: select spell → check mana → spend mana → resolve effects.

Card resource gets optional `cooldown_override: int = -1`.

### Phase 7 — Enemy AI with hybrid intents
Refactor `EnemyAI.gd`:
- Each enemy archetype owns a small ability list (cooldown-gated) plus a basic-attack fallback.
- AI loop end-of-turn: pick highest-priority off-cooldown ability with a valid target; show telegraph for next turn.
- HUD shows the telegraphed icon above the enemy sprite.

### Phase 8 — Loot persistence
- Items on the battlefield are real entities.
- On combat end: surviving items map their tactical position back to the nearest valid room floor tile; become room items.
- Loot dropped by killed enemies lands on the battlefield tile they died on; same persistence rule.

### Phase 9 — Death / end-of-run
- On player death: `CombatSession` ends with `result = DEFEAT`; route to game-over screen; run is over (no retry).

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
