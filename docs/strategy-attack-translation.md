# Strategy-combat attack translation

How a card's Attack-column archetype becomes a **ranged, area-shaped attack on
the tactical grid**. This is the Strategy-mode sibling of
[`action-attack-translation.md`](action-attack-translation.md): the same
`attack_shape` / `attack_params` that drive the real-time smear in Action also
drive the grid range + footprint here, so a card authored once reads the same
way in both modes.

> Status: **implemented**. `StrategyAttackLibrary`
> (`data/strategy_attacks.tres`, exposed as `Data.strategy_attacks`), the
> `BattleGridView` AIM mode, and the spatial resolution in `BattleView`
> (`_shaped_targets_for` / `_resolve_effect_targets`) are all in. Enemies share
> the system via shapes authored on their `EnemyCatalog` intents. The legacy
> melee/ranged inference still covers any un-annotated card.

---

## The problem this fixes

Before this, tactical attacks were targeted by *clicking a unit*: melee meant
"click an adjacent enemy", everything else meant "click any enemy on the map",
and AOE just broadcast to **all** enemies regardless of where they stood. There
was no notion of an attack's *reach in tiles* or the *tiles it covers* — a
dagger and a greatsword and a fireball all played identically.

## The model: range + footprint

`Data.strategy_attacks.resolve(shape, params)` turns an archetype + params into
a numeric **spec**:

| Field | Meaning |
|---|---|
| `family` | how the footprint is built — `single` / `front_arc` / `blast` / `line` / `disc` / `auto` |
| `range_tiles` | how far (Chebyshev / king-move tiles) the attack can be aimed |
| `radius` | area size for the AOE families |
| `aim` | `tile` (player aims), `self` (centred on attacker), `auto` (engine picks) |
| `rotates` | whether the footprint orients toward the aimed tile |
| `pierce` / `spread` / `blocked_by_walls` | line modifiers |

`footprint(spec, origin, aim, map, stops)` then returns the exact tiles the
attack covers. Directional families anchor on the attacker and **rotate** so the
pattern always faces the aimed tile (Mewgenics-style).

### The archetypes

| Shape | Family | Range (tiles) | Footprint |
|---|---|---|---|
| `poke` | single | size reach (short 2 … large 5) | the one aimed tile |
| `swing` | front_arc | 1 (melee) | 3-tile arc in front; `arc=360` → all 8 neighbours |
| `smash` | blast | = size depth (1–3) | forward cluster, `size` tiles deep, that rotates |
| `projectile` | line | size reach (med 3 / large 5) | line outward; `spread`→3-wide; `pierce`→through bodies |
| `beam` | line | full board | line to the edge; **walls block line-of-sight** |
| `nova` | disc | self | Chebyshev disc of `radius` around the attacker |
| `lob` | disc | throw range (4) | disc of `radius` dropped on the aimed tile |
| `smite` / `homing` / `auto_aoe` / `bounce` | auto | any | engine auto-targets (resolved immediately, no aiming) |

Tunables (the size→tiles tables, lob throw range) live in
`data/strategy_attacks.tres` — edit there to retune without touching code.

## How it plays

1. Playing an attack card (or the Attack action with a weapon / bare strike)
   enters **AIM mode** on the grid.
2. The in-range band lights up (dim orange). The cursor is **hard-gated** to it:
   out-of-range tiles aren't clickable and don't spend the play.
3. The live footprint (bright red) previews the tiles that will be hit, and
   **rotates** as you move the cursor for directional shapes.
4. Clicking a valid tile resolves the attack against **every unit standing in
   the footprint** — including your own allies (**friendly fire**). Right-click
   cancels.

`self` / ally / heal effects on the same card still resolve against the caster /
allies as before; only damaging `enemy` / `all_enemies` effects become spatial.

### Line of sight

`beam` (and any line flagged `blocked_by_walls`) stops at the first `WALL`
tile, so you can't shoot through solid terrain. `COVER` is walkable and does not
block. Non-piercing `projectile`s also stop at the first body they hit.

## Enemies

The `enemies` sheet has no Attack column, so enemy shapes are authored directly
on their `EnemyCatalog` intents (a `shape` / `params` key). A shaped intent
takes its `range_max` from the library (so its telegraphed reach matches its
footprint) and hits everything in its footprint — e.g. an Orc's **Bash**
(`smash`) is a forward blast that can clip a second enemy, and a Troll's
**Crush** is a large blast. Hovering an enemy still shows the Mewgenics threat
overlay: **blue** = the tiles it can move to, **red** = the tiles it threatens.

## Caveats / follow-ups

- `cleave`-flagged attacks keep their existing "hit **all** enemies" contract
  (they resolve globally, not spatially), so AOE clears aren't silently nerfed
  into a small ring. Routing `cleave` through a spatial ring/spread is a
  possible follow-up.
- Range and area use **Chebyshev** (8-way) distance so directional footprints
  rotate cleanly, while unit **movement** stays **Manhattan** (4-way). This is a
  deliberate split; unifying movement to 8-way would be a separate change.
- Knockback / displacement was scoped out of this pass.
