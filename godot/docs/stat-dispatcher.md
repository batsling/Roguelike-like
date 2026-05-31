# Phase 3a — Stat Dispatcher Design

## Goals

- Single source of truth for what each stat does.
- Per-mode behavior (deckbuilder / action / strategy).
- Data-driven: adding or tuning a stat is mostly a `.tres` edit + one
  query method on the autoload.
- Existing code reads stats via the dispatcher; no more
  `GameState.strength / 3` calls scattered across combat scenes.

---

## Architecture

| Piece | Role |
|---|---|
| `Stats` autoload | Runtime API. Loads StatDefinitions at startup and answers queries from combat scenes / event modal / HUD. |
| `StatDefinition` Resource (`.tres`) | One per stat. Carries display metadata, derived-status config, and a flexible `mode_data: Dictionary` of per-mode knobs. |
| `Stats.Mode { DECKBUILDER, ACTION, STRATEGY }` | Mode enum. Each combat scene declares its mode when calling combat-scoped queries. Event rolls + HUD are mode-agnostic. |

---

## Stats table

| Stat | Universal derived | Deckbuilder extra | Action extra | Strategy extra |
|---|---|---|---|---|
| Strength | every 3 → 1 Power | — | melee dmg buff (TBD per-point) | melee dmg buff (TBD per-point) |
| Dexterity | every 3 → 1 Defense | — | +5% attack speed per point | +1 ranged dmg per point |
| Intelligence | every 3 → 1 Arcane | — | — | — |
| Charisma | every 5 → 1 Persistence | — | — | — |
| Constitution | — | — | — | — |
| Luck | (10% advantage per point on rolls) | — | — | — |
| Speed | — | +1 turn-1 draw per 3 Speed | +10 px/s per point (base 200) | +1 extra tile per turn per point (base 1) |

**Event roll bonus** (overworld + map ? nodes): Strength / Dexterity /
Intelligence / Charisma / Constitution each contribute +1 per point to
their own roll. Luck applies advantage via the dispatcher.
Speed / Dash / FoV / Discovery don't contribute to event rolls.

**Derived combat statuses** (applied at combat start, all modes):

| Status | Source | Effect |
|---|---|---|
| Power | STR / 3 | +1 to all outgoing damage per stack |
| Defense | DEX / 3 | +1 to all block gained per stack |
| Arcane | INT / 3 | +1 to magic-type damage per stack (and +1 healing per stack) |
| Persistence | CHA / 5 | +1 status stacks when player inflicts/gains a non-Power status |

---

## Run-scope resources (separate from stats)

| Resource | Behavior |
|---|---|
| Dash | Overworld: choose any portal (1 spend). Deckbuilder: spend 1 → +1 Buffer stack. Strategy: spend 1 → extra turn. Action: max simultaneous charges (base 0, +1 per Dash stat, regen 1 charge / 4 s). |
| Reroll | Reroll portals / shop offers / combat dice. |
| FoV | +1 portal choice per point (base 3). |
| Discovery | +1 reward choice per point (cards / items). |

These live on GameState directly (`dash_charges`, `reroll_charges`, etc.) — not part of the StatDefinition flow.

---

## `StatDefinition` schema

```gdscript
class_name StatDefinition
extends Resource

@export var id: StringName              # &"strength" etc.
@export var display_name: String
@export_multiline var description: String

# True for stats that contribute +1/point to their own event roll.
# Speed / Dash / FoV / Discovery → false.
@export var grants_event_roll_bonus: bool = true

# Universal derived combat status (applied at combat start regardless
# of mode). Empty means none.
@export var derived_status: StringName = &""
@export var derived_per: int = 1

# Bag of mode-specific numeric knobs. Keys are stat-specific; the
# Stats autoload methods read them with safe defaults so adding a new
# mode behavior = add a key here + a method on Stats.
@export var mode_data: Dictionary = {}
```

### `mode_data` keys per stat

| Stat | Keys |
|---|---|
| `strength` | (empty for now — universal Power handles deckbuilder; action / strategy melee buffs land when those modes arrive) |
| `dexterity` | `action_attack_speed_per_point: 0.05`, `strategy_ranged_dmg_per_point: 1` |
| `intelligence` | (empty) |
| `charisma` | (empty) |
| `constitution` | (empty) |
| `luck` | `advantage_pct_per_point: 10` |
| `speed` | `deckbuilder_draws_per_3: 1`, `action_base_movespeed: 200`, `action_movespeed_per_point: 10`, `strategy_base_tiles: 1`, `strategy_tiles_per_point: 1` |

Empty `mode_data` is fine — the dispatcher uses safe defaults for unknown keys.

---

## `Stats` autoload API

```gdscript
extends Node

enum Mode { DECKBUILDER, ACTION, STRATEGY }

var _stat_defs: Dictionary = {}   # id -> StatDefinition

func _ready() -> void:
    _load_stat_defs()

# ---- Universal lookups ----

func get_value(stat_id: StringName) -> int:
    # Reads GameState.<stat_id> via property name; assumes the field
    # exists on the autoload.
    return int(GameState.get(String(stat_id)))

func event_roll_bonus(stat_id: StringName) -> int:
    var def: StatDefinition = _stat_defs.get(stat_id)
    if def == null or not def.grants_event_roll_bonus:
        return 0
    return get_value(stat_id)

# ---- Combat-start hook ----

func apply_derived_statuses(actor: CombatActor, _mode: Mode) -> void:
    for stat_id in _stat_defs:
        var def: StatDefinition = _stat_defs[stat_id]
        if def.derived_status == &"":
            continue
        var per := max(1, def.derived_per)
        @warning_ignore("integer_division")
        var stacks: int = get_value(stat_id) / per
        if stacks > 0:
            actor.add_status(def.derived_status, stacks)

# ---- Speed (mode-specific) ----

func deckbuilder_bonus_draws_turn_1() -> int:
    var per_3: int = _knob(&"speed", "deckbuilder_draws_per_3", 1)
    @warning_ignore("integer_division")
    return (get_value(&"speed") / 3) * per_3

func action_movement_speed() -> float:
    var base: float = _knob(&"speed", "action_base_movespeed", 200.0)
    var per: float = _knob(&"speed", "action_movespeed_per_point", 10.0)
    return base + get_value(&"speed") * per

func strategy_tiles_per_turn() -> int:
    var base: int = _knob(&"speed", "strategy_base_tiles", 1)
    var per: int = _knob(&"speed", "strategy_tiles_per_point", 1)
    return base + get_value(&"speed") * per

# ---- Action dash (max charges; base 0 + Dash stat) ----

const ACTION_DASH_REGEN_SECONDS := 4.0

func action_max_dash_charges() -> int:
    return GameState.dash_charges

# ---- Luck ----

func roll_d20_with_luck(rng: RandomNumberGenerator) -> int:
    return _luck_roll(rng, 20)

func roll_chance_with_luck(rng: RandomNumberGenerator, percent: int) -> bool:
    var r1: bool = rng.randi_range(0, 99) < percent
    var luck: int = get_value(&"luck")
    if luck == 0:
        return r1
    var adv_pct: int = clampi(absi(luck) * 10, 0, 100)
    if rng.randi_range(0, 99) >= adv_pct:
        return r1
    var r2: bool = rng.randi_range(0, 99) < percent
    return r1 or r2 if luck > 0 else r1 and r2

func _luck_roll(rng: RandomNumberGenerator, sides: int) -> int:
    var r1: int = rng.randi_range(1, sides)
    var luck: int = get_value(&"luck")
    if luck == 0:
        return r1
    var adv_pct: int = clampi(absi(luck) * 10, 0, 100)
    if rng.randi_range(0, 99) >= adv_pct:
        return r1
    var r2: int = rng.randi_range(1, sides)
    return maxi(r1, r2) if luck > 0 else mini(r1, r2)

# ---- Constitution auto-gain ----

func note_max_hp_change(new_max: int, old_max: int) -> void:
    var delta: int = new_max - old_max
    if delta <= 0:
        return
    @warning_ignore("integer_division")
    var gained: int = delta / 5
    if gained > 0:
        GameState.constitution += gained
        GameState.emit_signal("stats_changed")

# ---- Helpers ----

func _knob(stat_id: StringName, key: String, default):
    var def: StatDefinition = _stat_defs.get(stat_id)
    if def == null:
        return default
    return def.mode_data.get(key, default)

func _load_stat_defs() -> void:
    var dir := DirAccess.open("res://data/stats/")
    if dir == null:
        return
    dir.list_dir_begin()
    var fname: String = dir.get_next()
    while fname != "":
        if fname.ends_with(".tres") or fname.ends_with(".res"):
            var res: Resource = load("res://data/stats/" + fname)
            if res is StatDefinition and res.id != &"":
                _stat_defs[res.id] = res
        fname = dir.get_next()
```

---

## Damage type tagging

Add `damage_type: "melee" | "ranged" | "magic"` to every `dmg` effect.
Defaults to `"melee"` if missing.

Damage flow in `DeckbuilderCombat.deal_damage` (and future strategy /
action equivalents):

1. base = effect.value
2. amount += source.power
3. if damage_type == "magic": amount += source.arcane
4. if mode == Strategy and damage_type == "ranged":
   amount += dex × `strategy_ranged_dmg_per_point`
5. if source.weak: amount = floor(amount × 0.75)
6. if target.vulnerable: amount = ceil(amount × 1.5)
7. block absorption
8. hp

All existing card `.tres` files get a one-shot pass to add
`damage_type: "melee"` to their dmg effects. Strike / Bash / Heavy
Blade / etc. are all melee in their JS originals.

---

## Refactor checklist (when Phase 3a's code lands)

- [ ] `scripts/resources/StatDefinition.gd` (new)
- [ ] `scripts/autoload/Stats.gd` (new) + registered in `project.godot`
- [ ] 7 stat `.tres` files under `data/stats/`
- [ ] `DeckbuilderCombat._apply_derived_statuses` → `Stats.apply_derived_statuses(player, Stats.Mode.DECKBUILDER)`
- [ ] `EventModal._get_stat_value` → `Stats.event_roll_bonus(stat_id)`
- [ ] `EventModal._roll_d20_with_luck` → `Stats.roll_d20_with_luck(rng)`
- [ ] All card .tres: add `"damage_type": "melee"` to dmg effects
- [ ] `GameState` setter for `max_hp` calls `Stats.note_max_hp_change(...)`
- [ ] `DeckbuilderCombat._start_player_turn`: on turn 1, draw an extra `Stats.deckbuilder_bonus_draws_turn_1()` cards
- [ ] `OverworldHUD` top bar: include Speed + Constitution alongside other stats

---

## Deferred (intentionally)

- **Action / strategy specific damage bonuses** (Strength melee buff
  in action / strategy, Dexterity ranged buff in strategy) — the
  `mode_data` knobs are defined but only get plumbed when those
  combat scenes exist (Phases 3 / 4).
- **Buffer status** itself: needs combat-engine support to absorb one
  hit completely. Lands alongside the Dash-spend UI in deckbuilder.
- **Reroll for combat dice**: dice cards don't exist in our port yet;
  reroll resource UI lands when dice cards do.
- **Rarity rolls weighted by Luck**: current reward / shop rolls are
  uniform. Wire `roll_chance_with_luck` once we add a rarity ladder.

---

## Harvesting + Crit (Phase 3b)

Three new run stats live on `GameState` (`harvesting`, `crit_chance`,
`crit_damage`) with matching `.tres` under `data/stats/`. They flow
through `item_stat_bonus` like every other stat, so item passives
(Bowler Hat: `+3 luck, +18 harvesting, -3 crit_chance`) and per-item
`upgrade_level` scaling apply automatically — `crit_chance` /
`harvesting` are outside `HEALTH_BUCKET`, so an upgraded copy bumps them
by `upgrade_level` with no special-casing.

| Stat | Start | Behavior |
|---|---|---|
| Harvesting | 0 | On `TriggerBus.game_beaten` (emitted from `Overworld._handle_victory_for`), gain gold = Harvesting. Handled by `Stats._on_game_beaten`. |
| Crit Chance | 0 | Base crit %, may be negative. |
| Crit Damage | 100 | Bonus % a crit adds. 100 → crit deals double damage. |

**Crit roll** (`Stats.crit_chance_percent`, player-only):

```
crit% = clamp( max(0, 2 × Luck) + crit_chance , 0, 100 )
```

Luck only ever helps (negative Luck contributes 0); `crit_chance` is
added raw. Resolved in `Stats.resolve_damage`: a PLAIN rng roll (Luck is
already folded into the percent, so it does NOT route through
`roll_chance_with_luck`). On a crit, `amount` is multiplied by
`1 + crit_damage/100` **pre-block** (block soaks the boosted hit), and
only for direct attacks — DoTs go through `apply_dot` and never reach the
resolver; `damage_type == "true"` is excluded. `resolve_damage` returns
`crit: bool` for scenes that want to surface "CRIT!". Works in all three
modes since every mode shares the resolver.

**Crit Chance Up status**: display-only mirror of the player's POSITIVE
`crit_chance`, seeded in `apply_derived_statuses` (deckbuilder / action;
strategy doesn't seed combat-start statuses yet, but crits still roll).
The Luck portion of the roll stays hidden, and a negative `crit_chance`
lowers the roll without showing a status. Icon falls back to Unknown.png
until `images/statuses/CritChanceUp.png` is added.
