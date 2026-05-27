# Card Authoring — Spreadsheet ↔ Code Reference

This is the canonical mapping between the `cardsnew` sheet in
`tools/Roguelikes.xlsx` and the `.tres` files under
`godot/data/cards/`. Use this when adding a new card so the
spreadsheet row and the resource file stay in sync.

## Sheet columns

| Column | Maps to (`CardData`) | Notes |
|---|---|---|
| Name | `display_name` | |
| Rarity | `rarity` | `Starter` / `Common` / `Uncommon` / `Rare` / `Legendary` |
| Type | `type` | `Attack` / `Skill` / `Power` |
| Cost | `cost` | `-1` for X-cost cards |
| Description | `description` | Player-facing text. Multi-hit `NxM` and `xN times` phrasing should be exact — see DSL below. |
| Effects | `effects` | DSL — see below. |
| Upgraded Description | `upgraded_description` | |
| Upgraded Effects | `upgraded_effects` | Same DSL. |
| Upgraded Cost | `upgraded_cost` | `-999` sentinel = same as base. |
| Range | `range_class` (+ `damage_type` for projectiles) | See Range column below. |
| Img | `image` | Texture file under `assets/cards/`. |
| Game | `source_game` | |
| Keywords | bool flags on the card | See Keywords column below. |
| Element | damage element | See Element column below. |
| Tags | `tags` | Free-form thematic / filter tags (`ironclad`, `offense`, `aoe`, …). |

## Range column

Drives both `range_class` and (for projectiles) the `damage_type` of
the card's dmg effects.

| Sheet value | `range_class` | Implies |
|---|---|---|
| `Self` | `&""` | No melee/ranged distinction. |
| `Short` | `&"short"` | Melee swing, short reach. |
| `Medium` | `&"medium"` | Melee swing, default reach. |
| `Large` | `&"large"` | Melee swing, long reach. |
| `Projectile, Short` | `&"short"` | Each `dmg:` becomes `damage_type: ranged`. Travels ≈ 320 px. |
| `Projectile, Medium` | `&"medium"` | Travels ≈ 620 px. |
| `Projectile, Large` | `&"large"` | Travels ≈ 950 px. |

If a card is `Projectile, *` you do **not** need to write `:ranged` on
every dmg in the Effects column — the Range column already says so.
(Authors today are writing it twice for clarity; either way is fine
as long as they agree.)

## Keywords column

Pipe-delimited list of behavior flags. Each becomes a bool on the card.

| Keyword | Field | Meaning |
|---|---|---|
| `Ethereal` | `ethereal = true` | Exhausts at end of turn if still in hand. |
| `Exhaust` | `exhaust = true` | Exhausts on play. |
| `Innate` | `innate = true` | Always in starting hand. |
| `Retain` | `retain = true` | Not discarded at end of turn. |
| `Unplayable` | `unplayable = true` | Cannot be played manually. |

## Element column

Single element word. Currently advisory (used by the dmg renderer and
tags); future status side-effects (Burn / Chill / Shock) hang off this.

| Element | Notes |
|---|---|
| `Electric` | Lightning visuals; future Shock interaction. |
| `Fire` | Future Burn application. |
| `Ice` | Future Chill / Frostbite. |
| `Poison` | Future Poison stacks. |
| `Physical` | Default, leave blank. |

## Effects DSL

Semicolon-delimited list of effect lines. Each line is
`verb:arg1:arg2[:argN]`. Whitespace around `;` is fine.

### Verbs

| Verb | Arguments | Meaning | `.tres` form |
|---|---|---|---|
| `dmg` | `VALUE[xN]:DAMAGE_TYPE[:cleave]` | Deal damage. `xN` = multi-hit (Twin Strike). `cleave` = `target: all_enemies`. | `{type: "dmg", value, target, damage_type, hits?}` |
| `gain` | `STAT:VALUE` | Player gains the stat (block, power, defense, dodge, …). | `{type: "block"/"status", value, stacks, status, target: "self"}` |
| `inflict` | `STATUS:STACKS[:cleave]` | Apply a debuff to the targeted enemy (or all enemies with `cleave`). | `{type: "status", status, stacks, target: "enemy"/"all_enemies"}` |
| `draw` | `N` | Draw N cards. In Action mode this instead chips a random ability cooldown by 25% per N. In Strategy, reduces a random ability CD by N. | `{type: "draw", value: N}` |
| `heal` | `VALUE[:self]` | Recover HP (defaults to self). | `{type: "heal", value, target: "self"}` |
| `gain_energy` | `N` | Refund N energy in the deckbuilder. | `{type: "gain_energy", value: N}` |
| `gain_gold` | `N` | Award N gold (rare on cards). | `{type: "gain_gold", value: N}` |
| `lose_hp` | `VALUE` | Pay HP as a cost. | `{type: "lose_hp", value}` |
| `exhaust_self` | (none) | Exhaust the played card. Redundant if Keywords has `Exhaust`. | `{type: "exhaust_self"}` |
| `conjure` | `CARD_ID:DESTINATION[:COUNT]` | Create COUNT copies of CARD_ID into the named pile. `CARD_ID` of `self` means "this card" and inherits its upgrade state; append `+` (e.g. `shiv+`) to force the upgraded form of a fixed card. `DESTINATION` is `hand` / `draw` / `discard`. COUNT defaults to 1. | `{type: "conjure", card_id, destination, count, upgraded?}` |
| `power_multiplier` | `N` | Multiplies the Power stat's contribution to this card's damage by N. Applies to the preceding `dmg:` lines on the same row. | Added as `power_multiplier: N` on each `dmg` effect. |

### Argument shorthand for `dmg`

`dmg:VALUE:DAMAGE_TYPE[:MODIFIER]`

- `dmg:6:melee` — Strike
- `dmg:5x2:melee` — Twin Strike (resolves twice)
- `dmg:4:ranged:cleave` — Thunderclap (ranged + `target: all_enemies`)
- `dmg:14:melee; power_multiplier:3` — Heavy Blade (Power counts triple)
- `dmg:8:melee:cleave` — Cleave (melee + all_enemies)

`cleave` in slot 4 is the modifier that flips `target` from `enemy`
to `all_enemies`. Anywhere else it's a tag.

### Status verbs: `gain` vs `inflict`

These exist to make Excel rows self-documenting. The engine still
stores them as the underlying `block`/`status` effect with
`target: self` or `target: enemy`, but at design time you should
write the verb that matches *what the card actually does*:

| Card text | DSL | Becomes |
|---|---|---|
| Gain 5 Block | `gain:block:5` | `block`, `target: self` |
| Gain 2 Power | `gain:power:2` | `status`, `status: power`, `target: self` |
| Inflict 2 Vulnerable | `inflict:vulnerable:2` | `status`, `status: vulnerable`, `target: enemy` |
| Inflict 1 Weak (Cleave) | `inflict:weak:1:cleave` | `status`, `status: weak`, `target: all_enemies` |

## Conjure

Spreadsheet uses one verb with positional args:

```
conjure:CARD_ID:DESTINATION[:COUNT]
```

Append `+` to `CARD_ID` to conjure the upgraded form.

Examples:

| Sheet | Meaning |
|---|---|
| `conjure:self:discard` | Anger — drop a copy of this card into discard. Inherits the played card's upgrade state automatically. |
| `conjure:self:hand` | Copy this card into hand (typically paired with `Keywords: Exhaust`). Inherits upgrade. |
| `conjure:dazed:discard:2` | Add 2 base-form Dazed cards to discard. |
| `conjure:wound:draw` | Shuffle 1 base-form Wound into the draw pile. |
| `conjure:shiv+:hand:3` | Add 3 **upgraded** Shivs to hand (e.g. Blade Dance+). |

In code the effect is a single type `conjure` with fields
`{card_id, destination, count, upgraded?}`:

- `card_id` accepts `"self"` (copy the played card and its current
  upgrade state) or any id from `godot/data/cards/`. A trailing `+`
  on the id (e.g. `"shiv+"`) is stripped and sets the upgrade flag —
  this is the recommended form so it round-trips with the sheet DSL.
- `destination` is `"hand"` / `"draw"` / `"discard"`. Adds to the draw
  pile are reshuffled so the conjured card isn't deterministically on
  top.
- `count` defaults to 1.
- `upgraded` (optional bool) is an alternative to the `+` suffix;
  both routes set the same flag.

If the resolved card can't upgrade (`can_upgrade = false`, e.g. status
cards like Dazed/Wound), the upgrade flag is silently dropped so
authoring mistakes don't crash anything.

Self-conjures ignore the upgrade flag and always inherit the played
card's state, so playing an upgraded Anger conjures an upgraded Anger
without any extra work.

Outside the deckbuilder (action / strategy) the effect no-ops because
there are no piles to add to.

## Worked examples

### Anger — `Common Attack` cost 0
```
Description:  Deal 6 Dmg Melee. Conjure 1 copy of this card to Discard.
Effects:      dmg:6:melee; conjure:self:discard
Range:        Short
Keywords:
Element:
Tags:         ironclad, offense
```

### Heavy Blade — `Common Attack` cost 2
```
Description:  Deal 14 Dmg Melee. Power affects this card x3 times.
Effects:      dmg:14:melee; power_multiplier:3
Range:        Medium
Keywords:
Element:
Tags:         ironclad, offense, scaling
```

`power_multiplier:N` applies to every `dmg:` line on the same row.
On upgrade, just bump the multiplier (`power_multiplier:5`).

### Twin Strike — `Common Attack` cost 1
```
Description:  Deal 5x2 Dmg Melee.
Effects:      dmg:5x2:melee
Range:        Short
```

The `5x2` shorthand is the canonical way to write multi-hit. The
engine resolves N independent damage events; in Action mode they
stagger ~100 ms apart, in Deckbuilder/Strategy they fire on the same
frame.

### Thunderclap — `Common Attack` cost 1
```
Description:  Deal 4 Dmg Ranged Electric Cleave. Inflict 1 Vulnerable Cleave.
Effects:      dmg:4:ranged:cleave; inflict:vulnerable:1:cleave
Range:        Projectile, Short
Keywords:
Element:      Electric
Tags:         ironclad, offense, aoe
```

A ranged `cleave` card fans 5 projectiles in Action mode (50° spread,
short travel ≈ 320 px). In Deckbuilder/Strategy the `all_enemies`
target just means "hit everyone".

### Carnage — `Uncommon Attack` cost 2
```
Description:  Ethereal. Deal 20 Dmg Melee.
Effects:      dmg:20:melee
Range:        Medium
Keywords:     Ethereal
Tags:         ironclad, offense
```

`Ethereal` lives in the Keywords column, not in the Effects DSL. If
Carnage is still in hand at end of turn it exhausts; if played, it
goes to discard like any normal card.

## Quick gotchas

- **Don't double-encode damage type.** If the Range column says
  `Projectile, *`, the Effects DSL doesn't need `:ranged` on every
  line — but if you write it anyway, make sure both agree.
- **`cleave` is a target modifier.** It flips a dmg or inflict effect
  from `enemy` to `all_enemies`. It is not a damage type.
- **Multi-hit only on `dmg`.** `inflict:vulnerable:1x2` does not mean
  "stacks twice" — write `inflict:vulnerable:2` instead.
- **`power_multiplier` is per-row.** It implicitly attaches to every
  `dmg:` on the same effects row. If a card needs to scale only one
  of two dmg lines, that's a future change to the DSL.
- **Conjure card ids use snake_case.** `dazed`, `slimed`, `wound`,
  `void`, `burn` — match the file name in `godot/data/cards/`.
