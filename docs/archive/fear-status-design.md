# Fear — Multi-Mode Status Design

Status: **gameplay implemented** (deckbuilder surcharge + Skill-play decay,
strategy turn-start flee, action enemy flee). The **spreadsheet rework in
[§4](#4-spreadsheet-rework--flag-the-exception-dont-reshape-every-row) is still
to be applied by hand** (sheet + importer + Collection). This doc specifies how
**Fear** behaves across the three combat modes and on both sides (player /
enemy), and the representation change so the sheet can describe per-mode +
per-side statuses like Fear without distorting the symmetric ones.

The hook points in [§5](#5-implementation-hook-points) document where each piece
landed.

---

## 1. The through-line

> **Fear = the unit is too scared to commit to offense; it wants to retreat /
> cower. It fades as the unit acts (defensively) or as time passes.**

That single idea makes every cell below consistent. The corollary the design
leans into: **Fear is a weak status in the deckbuilder but a strong one in
Action and Strategy**, where it can physically pull a unit out of the fight.
That's intentional — it gives Fear a clear "best used in the right mode"
identity instead of being a flat damage debuff everywhere.

---

## 2. Behavior matrix

| Mode | Player | Enemy |
|---|---|---|
| **Deckbuilder** | Non-Skill cards cost **+1 Energy**. Lose **1 Fear whenever a Skill card is played**. | **No effect** (Fear is inert against deckbuilder enemies). |
| **Strategy** | At the **start of its turn**, the unit automatically spends its movement to get **as far away from all opposing units as possible**. | Same as player — identical rule, applied to the enemy unit. |
| **Action** | **No effect for now.** | While Fear > 0, the enemy **flees from the player**. The flee lasts for a duration that **scales with Fear stacks**. |

Notes:

- **Deckbuilder enemy** and **Action player** are deliberately "no effect" for
  now (per design call). They are left as explicit no-ops, not omissions, so the
  matrix is complete and the importer/Collection can still describe them
  honestly ("No effect in this mode").
- **Strategy** is the one cell that is naturally symmetric, so player and enemy
  share one implementation that runs at any unit's turn start.

---

## 3. Per-mode rules in detail

### 3.1 Deckbuilder (player)

This is the legacy HTML behavior, ported verbatim:

- **Cost surcharge:** any card whose type is *not* Skill costs **+1 Energy**
  while the player has Fear > 0. (Skill cards are unaffected.)
- **Decay:** lose **1 Fear each time a Skill card is played** (event-driven, not
  turn-based). No turn decay — Fear persists across turns until skills burn it
  off.
- This rewards leaning on defensive/utility Skills to "calm down" before
  swinging again.

Legacy reference (for parity):
- Surcharge: `legacy-web/js/combat-engine.js:2346-2349`
- Skill-played decay: `legacy-web/js/combat-engine.js:5988-5992`

### 3.2 Deckbuilder (enemy)

- **No effect.** A feared enemy plays its pattern normally. (Considered cowering
  / weakened-attack / skip-turn variants; all judged too strong for the value
  Fear is meant to carry. Revisit if Fear ever needs an enemy-facing deckbuilder
  use.)

### 3.3 Strategy (both sides)

- **Trigger:** at the **start of the feared unit's turn** (the existing
  `unit_turn_started` hook), before normal player control or enemy AI planning.
- **Action:** compute the unit's reachable tiles within its movement budget,
  score each by the **sum of Manhattan distances to all living opposing units**,
  and move to the highest-scoring tile (ties → keep current/least movement).
  "Opposing units" = `u.is_alive() and u.is_player != unit.is_player`.
- **After fleeing:** the unit's turn then **ends** (it spent its action fleeing).
  Open sub-decision for implementation: whether a feared unit may still take a
  no-move action (e.g. attack if an enemy is adjacent after fleeing). Default:
  **no** — the whole turn is consumed by the flee, matching "too scared to act".
- **Decay:** **down by 1 at the end of the feared unit's turn**, so N stacks =
  N turns of forced retreat.

### 3.4 Action (enemy)

- **Trigger:** while the enemy actor has Fear > 0.
- **Action:** the enemy **moves away from the player** (override its normal
  walker/shooter movement with a retreat vector), and does **not** attack while
  fleeing.
- **Duration / decay:** Fear stacks convert to flee-time. Two equivalent framings
  — pick one at implementation time:
  1. **Stack = countdown:** treat each `FEAR_FLEE_SECONDS_PER_STACK` of real
     time as consuming 1 stack; the enemy flees until Fear hits 0.
  2. **Stack drives a flee window:** on gaining Fear, set a flee timer =
     `stacks * FEAR_FLEE_SECONDS_PER_STACK`; clear Fear when it elapses.
  Framing (1) is preferred — it reuses the per-stack model and surfaces a
  shrinking stack count on the enemy's status icons. Suggested constant:
  `FEAR_FLEE_SECONDS_PER_STACK ≈ 2.0` (tune against
  `ActionTranslation.turn_tick_secs`, default 10s).

### 3.5 Action (player)

- **No effect for now.** Fear sits on the player as a (currently inert) status.
  If we revisit, the cleanest mirror of the enemy is "cannot attack while
  feared" (keeps movement in the player's hands — forced auto-flee in real time
  feels bad). Left out by design call.

---

## 4. Spreadsheet rework — flag the exception, don't reshape every row

The key fact that drives this design: **statuses normally need no per-mode
authoring at all.** Both translation resources state it outright —
"Block / Heal / **Status** apply unchanged" across modes
(`ActionTranslation.gd:34-35`, `StrategyTranslation.gd:5-6`). The translator +
the shared `Stats.gd` resolvers carry every status into all three modes from a
single `Description`. So 18 of the 19 statuses are one concept that "just works"
everywhere.

Fear is the **only** status (so far) whose *behavior* — not just its numbers or
decay timing — changes by mode and by side. The wrong fix is to give every row
per-mode × per-side columns (six new columns, almost all blank). The right fix
is to **flag the exception and document it in one cell**.

### 4.1 Schema (chosen)

Two new columns, and the old `Action Decay` column is dropped:

| Column | Notes |
|---|---|
| `Name` | unchanged |
| `Description` | The one canonical (deckbuilder-framed) behavior. For all `Translates = Yes` rows this *is* the behavior in every mode. |
| `Effect` | machine/DSL hint, unchanged (blank for bespoke statuses) |
| `Type`, `Stackable`, `Max Stack` | unchanged |
| `Decay` | **Single** decay column. The translator derives the real-time (action) form from it (turn → `turn_tick_secs`, default 10s), so the old `Action Decay` column is removed. |
| `Who` | All / Player / Enemy |
| `Preference` | unchanged |
| **`Translates`** *(new, Yes/No)* | **Yes** = one concept, the translator/shared resolver makes it work in every mode (the default — all rows but Fear). **No** = bespoke per-mode behavior; read `Per-Mode`. |
| **`Per-Mode`** *(new, structured text)* | **Only filled when `Translates = No`.** A single-line cell: `mode.side: text` entries joined by ` \| ` (see below). Blank for everyone else. |
| `Icon`, `Rarity` | unchanged |

Net change: **+2 columns, −1 column.** No player/enemy column explosion — the
side split lives *inside* the one `Per-Mode` cell, which is fine because the
sheet only feeds the Collection *display*; behavior is hand-coded in Godot
either way.

### 4.2 `Per-Mode` format

A single-line cell (so the sheet stays tidy): `key: value` entries separated by
` | `. Key is `<mode>.<side>`:

- **mode** ∈ `db` (deckbuilder) · `action` · `strategy`
- **side** ∈ `player` · `enemy` · `both`
- value is free text describing the behavior **and** any bespoke decay inline.
- a side with `none` means Fear is inert for that mode+side (renders as "No
  effect", not a fallback to `Description`).

Fear's row:

| Field | Value |
|---|---|
| `Translates` | `No` |
| `Decay` | `Down by 1 when you play a Skill card` (the canonical/deckbuilder rule; per-mode decay lives in `Per-Mode`) |
| `Per-Mode` | (below) |

```
db.player: non-Skill cards +1 Energy; lose 1 Fear per Skill | db.enemy: none | strategy.both: flee at turn start; -1 end of turn | action.enemy: flees, scales with stacks | action.player: none
```

The importer splits entries on ` | `, then each entry on the first `:`.

### 4.3 Importer / Collection impact

- `tools/import-reference-godot.py` — read `Translates` + `Per-Mode`, drop the
  `Action Decay` read, emit `Translates` (bool) and a parsed `per_mode`
  structure (e.g. `{ "db": {"player": "...", "enemy": "none"}, ... }`) into each
  `STATUSES` entry. `Translates = Yes` rows carry an empty `per_mode`.
- `scripts/data/ReferenceCatalog.gd` — regenerated output; no hand edits.
- Collection UI (`scripts/ui/Collection.gd`) — when `per_mode` is non-empty,
  render the per-mode/per-side breakdown (group by mode, show player/enemy/both,
  "No effect" for `none`); otherwise show the single `Description` exactly as
  today. Every `Translates = Yes` status looks unchanged.

This rework is **not** required to ship Fear's gameplay (behavior is hand-written
in `Stats.gd` + the combat scripts regardless) — it keeps the sheet an honest
source of truth once statuses start diverging per mode.

---

## 5. Implementation hook points

All status state already exists: actors hold `statuses: {id -> stacks}` with
`add_status` / `get_status` (`CombatActor.gd:98-118`, `Unit.gd:70-78`), and the
`Fear.png` icon is already in `images/statuses/`. Remaining work per area:

### 5.1 `scripts/autoload/Stats.gd`

- Register the icon: add `&"fear": "Fear.png"` to `STATUS_ICONS`
  (`Stats.gd:57`). (One line — makes Fear render everywhere.)
- **Do NOT** add `&"fear"` to the global `DECAY_STATUSES`
  (`Stats.gd:25`). Fear's decay is mode-specific (skill-played / turn-end /
  time-based), so each mode decays it in its own lifecycle instead of the shared
  per-turn step.
- Optional: add a small shared helper for the strategy "flee to farthest tile"
  scoring so it isn't duplicated (it's the only cross-mode-reusable piece; the
  deckbuilder surcharge and action flee are mode-local).

### 5.2 Deckbuilder — `scripts/deckbuilder/DeckbuilderCombat.gd`

- **Cost surcharge:** card cost is read via `CardInstance.get_cost()`
  (`CardInstance.gd:41`), which has no combat context. Add a scene-level helper
  `_card_cost(card)` that returns `card.get_cost() + (1 if player.get_status(&"fear") > 0 and not card.is_skill() else 0)` and route the
  affordability/deduction sites through it (`DeckbuilderCombat.gd:688, 789, 834,
  877`). Also reflect the surcharge in the hand's cost display.
- **Skill-played decay:** in the play path, after a Skill resolves, if
  `player.get_status(&"fear") > 0` then `player.add_status(&"fear", -1)` and log
  it. Natural spot is alongside the existing post-play hooks near
  `DeckbuilderCombat.gd:904-909`.
- **Enemy:** nothing (no-op by design).

### 5.3 Strategy — `scripts/strategy/combat/BattleView.gd`

- In `_on_unit_turn_started(unit)` (`BattleView.gd:1045-1079`), before the
  player/enemy branch: if `unit.get_status(&"fear") > 0`, run the flee routine,
  then end the unit's turn.
- Flee routine: reuse `BattleGridView._reachable_from(unit, unit.move_range)`
  (`BattleGridView.gd:231-254`) for candidate tiles and
  `EnemyAI._distance(a, b)` (`EnemyAI.gd:198-199`) for Manhattan distance; pick
  the tile maximizing summed distance to all `u.is_alive() and u.is_player !=
  unit.is_player`. Set `unit.position`, refresh the grid, then
  `add_status(&"fear", -1)` (end-of-turn decay).
- Same path covers both sides (the hook fires for player and enemy turns alike).

### 5.4 Action — `scripts/action/ActionCombat.gd`

- **Enemy flee:** in the enemy movement step (`_process_walker`
  `:803-812` and `_process_shooter` `:814-832`, dispatched from
  `_process_enemies` `:784-802`), early-out when `inst.actor.get_status(&"fear")
  > 0`: set the move vector to retreat (`inst.pos -= to_player.normalized() *
  speed * delta`) and skip the attack/fire branch. Shooters already have a
  retreat vector to reuse.
- **Decay:** fold Fear into the action turn-tick (`_process_turn_tick` /
  `_tick_actor_turn`, `:586-627`) or a dedicated per-frame flee countdown using
  `FEAR_FLEE_SECONDS_PER_STACK` — see [§3.4](#34-action-enemy). Either way it's
  action-local, not via `decay_actor_statuses`.
- **Player:** nothing (no-op by design).

---

## 6. Application sources (out of scope here)

How Fear gets *applied* (cards, scrolls, events) is unchanged by this design —
the plumbing already exists: `GameState.pending_combat_statuses` is drained into
the actor at combat start (`Stats.apply_derived_statuses`,
`Stats.gd:220-222`), and card/curse effects can `add_status(&"fear", n)`
directly. The legacy `fear` scroll
(`legacy-web/js/scrolls-potions.js:684`) is the parity reference for a
fear-applying consumable when we port loot.

---

## 7. Open decisions to confirm before coding

1. **Strategy** — may a feared unit still attack after fleeing if an enemy ends
   up adjacent, or is the whole turn consumed? (Default in this doc: whole turn
   consumed.)
2. **Action enemy** — flee framing (1) stack-countdown vs (2) flee-window, and
   the value of `FEAR_FLEE_SECONDS_PER_STACK`.
3. **Sheet rework** — the schema is decided ([§4](#4-spreadsheet-rework--flag-the-exception-dont-reshape-every-row):
   `Translates` + `Per-Mode`, merged `Decay`). Remaining call is *timing*: apply
   the column changes to `Roguelikes.xlsx` + importer + Collection now, or defer
   until Fear's gameplay is actually implemented.
