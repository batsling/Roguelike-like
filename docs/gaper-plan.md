# Gaper Plan — directional enemy, death-transform & creep

Status: **agreed design, not yet implemented.** The Gaper is the enemy that
forces us to actually build directional rendering, a death-animation state, a
weighted on-death transform, the Pacer behavior, and a damaging-creep hazard.
Most of these are general systems other enemies will reuse.

Target behavior: the Gaper chases the player (Walker). On death it plays a death
animation and **transforms** — usually into a **Pacer** (paces, ignores the
player), occasionally into a **Gusher** (leaks damaging **creep**).

Decisions locked: facing = **3-direction + mirror** (down / up / side, side
mirrored for the opposite horizontal); Gusher = **full creep** now.

---

## 1. One unified `Ability` column (`enemiesA`)

Rather than a column per mechanic, action enemies get a **single packed
`Ability` column** — any special status / mechanic / trigger goes here. This
mirrors the deckbuilder `enemiesD` `Ability` column (which the importer already
parses into `starting_abilities` / split data) and keeps the schema flat as we
add mechanics. **It replaces the current `Split Into` / `Split Count` columns.**

### Grammar
Abilities separated by `/` (as in `enemiesD`); each is `Keyword(args)` or a bare
`Keyword`:
```
Ability:  OnDeath(pacer:80, gusher:20) / Creep(dmg=4, radius=36, interval=0.6, life=2.5, mode=trail)
```
Keywords for the Gaper family:
- **`OnDeath(id:weight, id:weight, …)`** — after the death animation, weighted
  roll one entry and spawn it at the corpse's position (HP rolled normally).
- **`Split(count, id)`** — N copies of `id` at ≤50% HP (the old `Split Into` /
  `Split Count`, now expressed here).
- **`Creep(dmg=.., radius=.., interval=.., life=.., mode=trail|on_death)`** —
  damaging floor hazard; `trail` drops it while moving, `on_death` leaves one
  puddle on death.
- Bare status keywords (`Shifting`, `Determined(lo,hi)`, `Ritual`, …) → starting
  statuses, same vocabulary as `enemiesD`.

Empty / `N/A` = no abilities.

### Parsing → `ActionEnemyData`
The importer parses the `Ability` string into the existing/added fields, so the
*resource* shape is unchanged from a runtime view — only authoring is unified:
- `Split(...)` → `split_into` / `split_count` (already exist).
- `OnDeath(...)` → `on_death_ids: PackedStringArray` / `on_death_weights:
  PackedInt32Array` (+ helper `roll_on_death(rng) -> StringName`).
- `Creep(...)` → `creep_*` fields.
- statuses → `starting_statuses` / `starting_abilities`.

### Columns that already suffice (engine work, not schema)
- `Directional = Yes` (Gaper, Pacer, Gusher).
- `Behavior` gains a new **enum value** `PACER` — not a column.
- `Animations` already names `walk` / `death`; no grammar change.

---

## 2. Engine systems to build

| System | Today | Needed |
|---|---|---|
| Walker chase | ✅ | Gaper reuses it |
| **Composite (layered) sprites** | ❌ one sprite per enemy | draw an ordered layer stack (body behind, head in front), each layer its own directional anim + offset |
| **Directional rendering** | ⚠️ `Directional` flag is inert | importer splits frames per direction; runtime picks facing from velocity, mirrors `side` |
| **Death animation / dying state** | ❌ enemies vanish at HP 0 | play `death` anim, *then* remove + fire on-death effects |
| **Weighted death-transform** | ❌ | parse `On Death`, weighted roll, spawn at death pos |
| **Pacer behavior** | ❌ | `BehaviorKind.PACER`: pace/bounce, ignore player, contact damage |
| **Creep hazard** | ❌ | persistent damaging floor zones (pos/radius/dmg/interval/life), trail or on-death |

### 2a. Composite (layered) sprites — head + body
Many Isaac enemies are a **body** with a **head** drawn on top as a separate
image; the Gaper is one. Model an enemy as an ordered list of **layers** drawn
back-to-front, each with its own animations (directional or not) and a draw
offset from the enemy origin.
- **Authoring:** animation names may be layer-prefixed — `body.walk`,
  `head.walk`. No prefix = a single default layer (the Horf is unchanged).
  Source art: `<id>_<layer>_<anim>_<dir>_*.png`
  (e.g. `gaper_body_walk_side_0.png`, `gaper_head_walk_side_0.png`).
- **Layer order + offset:** a small `Layers` spec (order = draw order, offset in
  source px, scaled by `Size`): `body @ 0,0 ; head @ 0,-10`. This is sprite
  layout, separate from the mechanic-only `Ability` column.
- **Runtime:** for each layer, resolve `<layer>.<base>_<facing>` (same facing +
  mirror logic as below) and draw at origin + scaled offset.

### 2b. Directional rendering (3-dir + mirror)
- Stored directions: `down`, `up`, `side`. **`side` art faces RIGHT**; moving
  left draws it horizontally flipped.
- Source art: `<id>_<anim>_<dir>_<frame>.png`, e.g. `gaper_walk_down_0.png`,
  `gaper_walk_up_0.png`, `gaper_walk_side_0.png`. Anims with no direction (death)
  stay `<id>_<anim>*` (`gaper_death_0.png`).
- Importer: when `Directional=Yes`, expand a base anim (`walk`) into
  `walk_down` / `walk_up` / `walk_side` entries; non-directional anims stay as
  the base. Frame trim + shared-square normalisation is unchanged.
- Runtime: track `facing` from velocity — `|vy| ≥ |vx|` → `up` (vy<0) / `down`,
  else `side` with `flip_h = vx < 0`; keep last facing when ~stationary. Look up
  `<base>_<facing>`, falling back to `<base>` when an enemy isn't directional.
  Draw flipped (negative-width `Rect2`) when `flip_h`.

### 2c. Dying state + transform (the tricky interaction)
- On HP≤0, set `inst.dying = true`, play `death` anim, start a timer = death-anim
  length. When it elapses: run the `Ability` `OnDeath(...)` (spawn the transform
  as a live enemy), then mark the corpse fully dead.
- **The transform is "the head pops off."** The Gaper's `death` is really its
  *head* being destroyed; the **body** continues as a Pacer (headless, paces) or
  Gusher (headless, gushes creep). So Pacer/Gusher should **reuse the Gaper's
  body animation with the head layer dropped** — they likely need no new body
  art, just the headless body + their behavior/ability. (Confirm vs. authoring
  them as fully separate sprites.)
- **Room-clear guard:** a room must NOT count cleared while any enemy is `dying`
  or a transform is pending — otherwise doors open before the Pacer appears.
  Extend the `_pending_spawns` guard in `start_room` / `_check_combat_end` /
  `has_live_enemies` to also cover `dying` instances. The transform spawns a live
  enemy before the corpse clears, so the room stays active seamlessly.

### 2d. Creep hazard
- New `_creep: Array` of `{pos, radius, dmg, interval, life, t}` zones, ticked in
  `_process` (damage the player on overlap on the interval, respecting iframes),
  decayed by `life`, drawn as translucent red puddles **under** the actors.
- A `mode=trail` enemy drops a zone on a timer while moving; `mode=on_death`
  drops one in the dying step.

---

## 3. Proposed `enemiesA` rows (tune later)

| | Gaper | Pacer | Gusher |
|---|---|---|---|
| Behavior | Walker | **Pacer** | Walker |
| Directional | Yes | Yes | Yes |
| HP (min/max) | 25 | 25 | 25 |
| Weight | 3 | **0** | **0** |
| Contact Damage | 6 | 6 | 6 |
| Move Speed | ~90 | ~70 | ~60 |
| Size | 1 | 1 | 1 |
| Ability | `OnDeath(pacer:80, gusher:20)` | — | `Creep(dmg=4, radius=36, interval=0.6, life=2.5, mode=trail)` |
| Animations | `walk @ 8 loop ; death @ 10 once` | same | same |

- **Weight 0** on Pacer/Gusher = never randomly spawned; they only appear via the
  Gaper's transform. Give them weight > 0 if you also want them as standalone
  spawns.
- Balance note: a Gaper's budget cost (3) buys the Gaper *and* its eventual
  transform — a room of Gapers roughly doubles in body count over the fight.

---

## 4. Art to provide

Per enemy, under `images/enemies/action_enemies/<Name>/`, **per layer** for
composites (`body`, `head`):
- **Directional walk:** `<id>_<layer>_walk_<dir>*` for `dir ∈ {down, up, side}`
  (side faces RIGHT; left is mirrored at runtime). One grid sheet per direction
  is fine — declare it in `Animations` (e.g. `body.walk @ 8 loop grid 32x32`).
- **Death / head-pop:** `<id>_<layer>_death*` (non-directional) as needed.
- Single-layer enemies (Horf) keep the un-prefixed `<id>_<anim>*` form.

Since Pacer/Gusher are the headless Gaper body, they may reuse the Gaper's
`body` frames rather than shipping their own.

Frames are trimmed-to-content and normalised onto one shared square per enemy
(consistent scale across directions/anims), same as the Horf.

---

## 5. Build order

1. `Ability` column: migrate `Split Into`/`Split Count` into it, then add the
   `OnDeath(...)` parser + weighted death-spawn (small; reuses weighted roll).
2. Dying state + death animation (general win — Horf benefits too).
3. Directional rendering + composite (body/head) layers (importer expansion +
   facing/flip + layer draw). Heaviest piece.
4. `PACER` behavior.
5. Creep system (`Creep(...)` ability) for the Gusher.
6. Author Gaper/Pacer/Gusher rows + wire the art.
