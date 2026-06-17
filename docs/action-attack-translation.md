# Action-combat attack translation

How a card in the `cardsnew` spreadsheet becomes a real-time attack in the
Action arena. This is the design spec for the attack-delivery overhaul; it
replaces the old "guess the shape from `damage_type`" behaviour with an
explicit, named, data-driven **attack archetype** vocabulary.

> Status: **implemented**. `CardData.attack_shape` / `attack_params`, the
> `ActionAttackLibrary` (`data/action_attacks.tres`), the
> `ActionCombat._deliver_attack` dispatcher + white-smear renderer, and the
> `generate_card_tres.py` parser are all in. The attack cards are now
> **generated from the spreadsheet** (`cardsnew`) — run
> `python3 tools/generate_card_tres.py --attacks` to regenerate the
> ATTACK-type `data/cards/*.tres` after editing the sheet. The fallback path
> (below) still covers any un-annotated card.

---

## The problem this fixes

Today `ActionCombat` *infers* an attack's shape from three thin signals on the
`dmg` effect plus the card's reach:

| Inference | Result |
|---|---|
| `melee` + `enemy` | 110°/110px cone swing (one orange smear) |
| `melee` + `all_enemies` | 140px AOE disc around the player |
| `ranged` | single projectile (320 / 620 / 950px by reach) |
| `ranged` + `all_enemies` | 5-projectile fan |
| `dmg:VALUExHITS` | repeats on a 0.10s cadence |

That vocabulary can't express "short poke vs 360 swing vs piercing crescent
wave vs laser vs homing vs auto-target zap." So delivery is promoted to a
first-class, authored thing.

## The model: *what* vs *how*

Two separate axes, authored in two separate columns:

- **`Effects`** — *what happens on hit* (`dmg:8`, `inflict:blind:2`,
  `dmg:7:if_status=poison`, …). Unchanged. Multi-hit volleys stay here as the
  `VALUExHITS` form (`dmg:5x2` = two volleys of 5).
- **`Attack`** *(the repurposed `Range` column)* — *how the hit is delivered in
  the arena*: the archetype + a few params. **The archetype is the source of
  truth for delivery** — when set, it fully drives hit-detection and visual;
  `damage_type` / reach are consulted only as a fallback for un-annotated cards.

The archetype decides hit-detection + visual; the effects ride along and apply
to whatever the archetype hits. A new card is one row; a new shape is one
resolver arm + one smear variant.

### Why conditional/extra damage stays in Effects

`Bane` ("if the target has Poison, deal the damage again") and `Bag o' Glitter`
("swing that inflicts Blind") both prove the split: the *delivery* is a plain
swing, while "extra damage if poisoned" and "apply Blind" are **effects** that
ride along. Delivery never encodes conditional logic.

---

## The `Attack` cell format

The cell is comma-separated tokens (keeping the existing `"Projectile, Medium"`
style). The **first token is the archetype**; the rest are params in any order:

```
<archetype>[, <token>]*
```

| Token | Meaning | Applies to |
|---|---|---|
| `Short` `Medium` `Large` `Full` | the archetype's **primary dimension** (see below) | size-based shapes |
| `arc=<deg>` | swing arc in degrees (`arc=360` = full ring) | `swing` |
| `target=<nearest\|random\|all>` | who the auto-targeting picks | `smite` `homing` `auto_aoe` |
| `spread=<n>` | fan of N projectiles | `projectile` |
| `pierce` | projectile passes through enemies | `projectile` |
| `crescent` | crescent-shaped projectile body (vs default bolt) | `projectile` |

The bare size word maps to whichever dimension defines that archetype, so
authoring stays intuitive (`Smash, Large` = a big blast; `Projectile, Large` =
a far-travelling bolt):

| Bare size means… | Archetypes |
|---|---|
| **reach** (how far it extends / travels) | `poke` `swing` `projectile` `beam` `homing` |
| **radius** (AOE disc size) | `smash` `nova` `lob` `auto_aoe` |

Volleys (firing the whole attack N times) come from the **Effects** `VALUExHITS`
form, not the Attack cell, so `Twin Strike` (`dmg:5x2:melee`, `Attack: Swing,
Medium`) swings twice.

### Element colour

A card's **Element** column tints its outward attack visual in the arena (smear,
swing blade, projectile, beam, disc, smite zap, bounce orb). The colour comes
from the `elements` sheet's Color column via the `Elements` registry
(`scripts/runtime/Elements.gd`) — e.g. a Fire swing is orange, a Poison flask is
light green. A card with no element keeps the default white smear. The same
registry also applies the element's "Effect on Attack" (Fire → 1 Burn, Blood →
1 Bleed, Poison → 1 Poison) when a *damaging* elemental hit lands.

### Swing is animated

The `swing` archetype isn't a static AOE wedge: it renders a blade that sweeps
across its arc with a motion-blur trail, and each enemy is struck the instant
the blade crosses its angle (a timed per-enemy hit) rather than all at once.
`poke` stays a thrust and `swing, arc=360` stays a full ring. Tunables live on
`ActionAttackLibrary` (`swing_duration`, `swing_trail_segments`).

A bare legacy value (`Medium`, `Projectile, Short`, `Self`) with no recognised
archetype falls through to the old inference, so nothing breaks mid-migration.

---

## Archetype registry

Each archetype maps to one hit-detector and one visual. Melee archetypes
(`poke` / `swing` / `smash` / `nova`) render as a **white smear** shaped to the
hitbox, so no per-card art is needed.

| Archetype | Hit detection | Visual | Default params |
|---|---|---|---|
| `poke` | narrow short thrust (slim cone / short line ahead) | white thrust smear | reach=Short |
| `swing` | arc cone at melee reach | white arc smear | arc=100, reach=Medium |
| `smash` | filled disc AOE at a point **in front** | white impact burst | radius=medium, reach=Medium |
| `nova` | filled disc AOE centred **on the player** | white expanding ring | radius=medium |
| `projectile` | moving body; stops on first hit unless `pierce` | bolt or `crescent` body | reach=Medium, spread=1 |
| `lob` | thrown body that lands at a point and bursts (AOE on land) | arcing body + impact burst | radius=medium |
| `beam` | instant full-length line from the player | beam line | reach=Full |
| `homing` | projectile that tracks a target | bolt body | target=nearest |
| `smite` | instant **direct** hit on a target set (no travel, no disc) | white zap/flash on each struck enemy | target=nearest |
| `auto_aoe` | auto-pick a target, disc AOE at **their** location | impact marker at location | target=random, radius=small |
| `bounce` | a thrown orb that hops between **random** enemies, applying the card's effects on each landing | travelling orb + burst, element-tinted | target=random |

Notes:
- `bounce` is **Bouncing Flask**: the hop count is the effect repeat
  (`times=N` on an inflict, or `dmg:VxN`), so `inflict:poison:3:times=3` poisons
  three random foes in sequence. Each hop applies the effect once; the
  `Indiscriminate` keyword (which drives random targeting in the other two
  modes) is what flags the card so the deckbuilder/strategy play UI skips the
  manual picker.
- `smite:target=all` is **Thunderclap**: auto-target like Blood Magic, but it
  hits every enemy directly with no AOE disc — just a zap on each.
- `auto_aoe:target=random` is **Blood Magic** (Megabonk-style): pick a random
  enemy, drop a small AOE on their spot.
- Archetypes are **aim-source-agnostic**: a click slot aims at the cursor, an
  auto slot aims at the nearest enemy, and `smite`/`homing`/`auto_aoe` pick
  their own target — the shape code is identical either way.

---

## Card mapping (current `cardsnew` attack cards)

| Card | `Attack` cell | Effects stay as |
|---|---|---|
| Anger | `Poke, Short` | `dmg:6:...` |
| Bash | `Smash, Medium` | `dmg:8; inflict:vulnerable:2` |
| Carnage | `Smash, Medium` | `dmg:20` |
| Cleave | `Swing, arc=360` | `dmg:8` |
| Heavy Blade | `Smash, Medium` | `dmg:14; power_multiplier:3` |
| Iron Wave | `Projectile, Medium, crescent, pierce` | `gain:block:5; dmg:5` |
| Pommel Strike | `Swing, Medium` | `dmg:9; draw:1` |
| Strike (Ironclad) | `Swing, Medium` | `dmg:6` |
| Thunderclap | `Smite, target=all` | `dmg:4; inflict:vulnerable:1` |
| Twin Strike | `Swing, Medium` | `dmg:5x2` (two swings) |
| Shiv | `Projectile, Medium` | `dmg:4` |
| Backstab | `Poke, Medium` | `dmg:11` |
| Beam Cell | `Beam` | `dmg:3; inflict:vulnerable:1` |
| Bludgeon | `Smash, Large` | `dmg:32` |
| Dagger Spray | `Projectile, Medium, spread=4` | `dmg:4x2` (two volleys of 4) |
| All for One | `Poke, Medium` | `dmg:10; recall:cost=0` |
| All-Out Attack | `Nova` | `dmg:10; discard:1:random` |
| Bane | `Swing, Medium` | `dmg:7; dmg:7:if_status=poison` |
| Bag o' Glitter | `Swing, Medium` | `inflict:blind:2; ...` |
| Barrel | `Projectile, Medium` | `dmg:6` |
| Blasma Pistol | `Projectile, Medium` | `dmg:3` |
| Blood Magic | `Auto_aoe, target=random, Small` | `dmg:2x3` |

---

## Implementation plan (Godot)

1. **`CardData`** — add `attack_shape: StringName` and
   `attack_params: Dictionary`. Keep `range_class` for the fallback path.
2. **Central archetype library** — `data/action_attacks.tres` (an
   `ActionAttackLibrary` resource, same philosophy as `ActionTranslation`)
   holding each archetype's default tunables: reach→px, default arc, radius px,
   projectile speed, smear colour/duration. Per-card `attack_params` override
   the library defaults, so the feel retunes in one place and cards stay terse.
3. **One dispatcher** — `_deliver_attack(card, effect, origin, aim_dir,
   is_auto)` replaces the scattered `damage_type` branches in
   `_resolve_card_effects` / `_resolve_card_effects_auto`. It reads the resolved
   archetype and calls the matching hit-detector:
   - `_enemies_in_cone` (poke/swing) — already exists
   - `_enemies_in_disc(centre, radius)` (smash/nova/lob/auto_aoe) — new
   - `_spawn_projectile(... shape, pierce, spread)` — generalise the current one
   - `_beam_hits(origin, dir)` (beam) — new
   - `_smite(target_set)` (smite) — new
   - `_pick_auto_target(mode)` (nearest/random/all) — new helper
4. **Smear renderer** — generalise `_draw_ability_swing_cone()` (one orange
   cone today) into a white-smear renderer with thrust / arc / disc / ring
   variants, fed by the archetype + its geometry.
5. **Fallback** — empty `attack_shape` → today's `damage_type`/reach inference,
   so the migration is incremental.

## Generator changes (`tools/generate_card_tres.py`)

- Read the `Attack` column (alias the legacy `Range` header).
- Parse the first token to `attack_shape`; parse the rest into
  `attack_params` (`arc`, `radius`, `spread`, `target`, `pierce`, `crescent`,
  and a bare size → `reach`).
- Emit both into the `.tres`; still set `range_class` from a bare size token so
  the fallback path has a reach when a card is only partially annotated.

## Extending the vocabulary later

Adding a shape (e.g. "shotgun blast", "chain lightning", "boomerang") is:
one row of defaults in the archetype library + one resolver arm in the
dispatcher + one smear/visual variant. Throws (`lob`), homing (`homing`), and
auto-area (`auto_aoe`) are already in the registry above as the first examples
beyond swings/pokes/projectiles.
