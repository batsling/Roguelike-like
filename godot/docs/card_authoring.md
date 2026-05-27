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

Pipe-delimited list. Splits into two destinations on the card:

1. **Bool flags** — known keywords with simple "is this card flagged?"
   behavior. Each maps to a bool field on `CardData`.
2. **Addons** — every other entry. Goes into `CardData.addons` (a
   PackedStringArray) and is dispatched at play time by
   `Stats.apply_addons_to_effect` (compute-style modifiers like
   Fishing Weight). See the Addons section below.

### Bool-flag keywords

| Keyword | Field | Meaning |
|---|---|---|
| `Ethereal` | `ethereal = true` | Exhausts at end of turn if still in hand. |
| `Exhaust` | `exhaust = true` | Exhausts on play. |
| `Innate` | `innate = true` | Always in starting hand. |
| `Retain` | `retain = true` | Not discarded at end of turn. |
| `Unplayable` | `unplayable = true` | Cannot be played manually. |

## Addons (Fishing Weight et al)

Anything in the Keywords column that isn't one of the bool-flag
keywords above lands in `CardData.addons: PackedStringArray` and is
treated as a compute addon — a named modifier with active behavior
at play time, dispatched by `Stats.apply_addons_to_effect`. Same
slot the existing `_apply_card_boosts` uses; runs before Vulnerable
/ Weak / Power so addon bonuses stack with everything else.

Documented per-mode in the `addonsnew` sheet. Engine wiring lives
in `Stats.gd`'s addon block — one switch arm per addon name.

| Addon | Behavior |
|---|---|
| `Fishing Weight` | `+1` dmg per `3 Common`, `2 Uncommon`, or `1 Rare` fish in the loot inventory. Stub returns 0 until fish loot lands (see `Stats._fishing_weight_bonus`); the rest of the pipeline is wired. |

To ship a new addon: add a row to `addonsnew`, add a switch arm to
`Stats.addon_damage_bonus` (or a sibling function for non-damage
modifiers), and put the addon name in any card's Keywords column.

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
| `dmg` | `VALUE[xN]:DAMAGE_TYPE[:cleave\|if_status=STATUS]` | Deal damage. `xN` = multi-hit (Twin Strike). `cleave` = `target: all_enemies`. `if_status=X` skips the hit per target when that target lacks status X (Bane's second hit). | `{type: "dmg", value, target, damage_type, hits?, if_target_status?}` |
| `gain` | `STAT:VALUE` | Player gains the stat (block, power, defense, dodge, …). | `{type: "block"/"status", value, stacks, status, target: "self"}` |
| `inflict` | `STATUS:STACKS[:cleave]` | Apply a debuff to the targeted enemy (or all enemies with `cleave`). | `{type: "status", status, stacks, target: "enemy"/"all_enemies"}` |
| `draw` | `N` | Draw N cards. In Action mode this instead chips a random ability cooldown by 25% per N. In Strategy, reduces a random ability CD by N. | `{type: "draw", value: N}` |
| `discard` | `N[:random]` | Mirror of `draw`. Deckbuilder: pick N from hand via the CardPickerModal (default — player chooses, like Acrobatics). Append `:random` for the engine-picked random variant (All-Out Attack). Always excludes the played card. Action: +25% of max CD on the lowest-cooldown ability, per N. Strategy: +N on the lowest current CD. | `{type: "discard", value: N, random?: bool}` |
| `exhaust` | `N[:random]` | Deckbuilder mirror of `discard` but routes picks to the exhaust pile. Same player-choice default and `:random` flag. No-op in action/strategy. | `{type: "exhaust", value: N, random?: bool}` |
| `recall` | `<FILTER>[:from=PILE][:to=PILE]` | Deckbuilder: move (not copy) every card in the source pile matching `FILTER` into the destination pile. `FILTER` today is `cost=N`; defaults are `from=discard`, `to=hand` (All for One). No-op in action/strategy. | `{type: "recall", from: PILE, to: PILE, filter: {…}}` |
| `upgrade_hand` | `N\|all[:random]` | Deckbuilder: upgrade in-place. `upgrade_hand:1` opens the picker so the player chooses (Armaments); `upgrade_hand:all` upgrades every eligible card in hand silently (Armaments+). Append `:random` to skip the picker for the N form. Skips cards that are already upgraded or have `can_upgrade = false`. No-op in action/strategy. | `{type: "upgrade_hand", value: N\|"all", random?: bool}` |
| `boost_cards` | `<MATCH>:<STAT>:<VALUE>` | Persistent in-combat modifier. Every later card matching `MATCH` resolves with `STAT + VALUE`. `MATCH` is exactly one of `tag=X` / `type=X` / `id=X`. `STAT` is `dmg` or `block`. Deckbuilder only today. | `{type: "boost_cards", match_tag/match_type/match_id, stat, value}` |
| `on_<EVENT>` | `<INNER_VERB>:<INNER_ARGS>` | Register a persistent in-combat listener. When the named event fires, the inner effect runs (source = player, target = player unless overridden). `<EVENT>` is a TriggerBus signal name (see Triggers section). After Image: `on_card_played:gain:block:1`. Deckbuilder only today. | `{type: "trigger", on: "<event>", effect: {…inner…}}` |
| `gain_loot` | `<KIND>:<COUNT>` | Add COUNT loot of `KIND` (`potion` / `scroll` / `key`) to the run-scope counter on GameState. Concrete potion/scroll catalogs land later; the counter is the placeholder. Alchemize: `gain_loot:potion:1`. | `{type: "gain_loot", kind: "potion", value: 1}` |
| `heal` | `VALUE[:self]` | Recover HP (defaults to self). | `{type: "heal", value, target: "self"}` |
| `gain_energy` | `N` | Deckbuilder: refund N energy. Action: ~N-second Haste window (1.3× movement, basic attack rate, ability cooldown ticking). Strategy: opens a per-turn budget of N for extra ability casts beyond the one-per-turn cap, paid out at the card's cost. | `{type: "gain_energy", value: N}` |
| `lose_energy` | `N` | Mirror of `gain_energy`. Deckbuilder drops N from the pool (floored at 0). Action: ~N-second Slow window (0.7×). Strategy: eats the energy budget first, then locks the normal ability use for the turn if the budget would go negative. | `{type: "lose_energy", value: N}` |
| `gain_gold` | `N` | Award N gold (rare on cards). | `{type: "gain_gold", value: N}` |
| `lose_hp` | `VALUE` | Pay HP as a cost. | `{type: "lose_hp", value}` |
| `exhaust_self` | (none) | Exhaust the played card. Redundant if Keywords has `Exhaust`. | `{type: "exhaust_self"}` |
| `conjure` | `CARD_ID:DESTINATION[:COUNT]` | Create COUNT copies of CARD_ID into the named pile. `CARD_ID` of `self` means "this card" and inherits its upgrade state; append `+` (e.g. `shiv+`) to force the upgraded form of a fixed card. `DESTINATION` is `hand` / `draw` / `discard`. COUNT defaults to 1. | `{type: "conjure", card_id, destination, count, upgraded?}` |
| `power_multiplier` | `N` | Multiplies the Power stat's contribution to this card's damage by N. Applies to the preceding `dmg:` lines on the same row. | Added as `power_multiplier: N` on each `dmg` effect. |
| `chance` | `PCT:<INNER_VERB>:<INNER_ARGS>` | Roll PCT% on the shared luck-modified RNG (Stats.roll_chance_with_luck — every point of Luck adds a 10% advantage roll, mirroring how events roll). On success, dispatch the inner effect through the same EffectSystem with the same ctx. Inner can be any verb. Bag o' Glitter: `chance:10:exhaust_self`. | `{type: "chance", percent: N, effect: {…inner…}}` |

### Argument shorthand for `dmg`

`dmg:VALUE:DAMAGE_TYPE[:MODIFIER]`

- `dmg:6:melee` — Strike
- `dmg:5x2:melee` — Twin Strike (resolves twice)
- `dmg:4:ranged:cleave` — Thunderclap (ranged + `target: all_enemies`)
- `dmg:14:melee; power_multiplier:3` — Heavy Blade (Power counts triple)
- `dmg:8:melee:cleave` — Cleave (melee + all_enemies)

`cleave` in slot 4 is the modifier that flips `target` from `enemy`
to `all_enemies`. Anywhere else it's a tag.

`if_status=STATUS` in slot 4 gates the hit per target — only enemies
with at least 1 stack of STATUS take damage. Disambiguated from
`cleave` by the `=` sign. Bane: `dmg:7:melee:if_status=poison`. If a
future card needs both `cleave` AND `if_status` on the same line,
the slot will switch to a pipe-delimited list (e.g. `cleave|if_status=burn`).

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

## Picker modal (Discard / Exhaust / Upgrade / Recall)

`CardPickerModal` is the shared mid-cast modal that opens whenever a
card asks the player to choose from a pile. One reusable widget
backs every "choose N from a set" effect: Acrobatics' discard,
Armaments' upgrade, future Exhume / Headbutt / Wraith Form picks,
etc. Deckbuilder-only — action and strategy silently no-op because
there are no piles to pick from.

**Default is player-choice.** Any verb that picks cards opens the
picker by default. Append `:random` to the DSL line to skip the
modal and let the engine roll instead. The convention is "if the
sheet doesn't say random, the player picks":

| DSL | Behavior |
|---|---|
| `discard:1` | Player picks 1 from hand to discard (Acrobatics). |
| `discard:1:random` | Engine picks 1 from hand to discard (All-Out Attack). |
| `exhaust:2` | Player picks 2 from hand to exhaust. |
| `upgrade_hand:1` | Player picks 1 from hand to upgrade (Armaments). |
| `upgrade_hand:all` | Whole hand upgrades silently (Armaments+). No picker. |

`recall` doesn't use the picker — it moves every card in the source
pile that matches the filter, so there's nothing to choose.

The picker blocks card play from advancing — the rest of the played
card's effects have already resolved by the time the modal opens
(synchronous effect loop), so the player can pick at their own pace
without the combat freezing visually. Confirming applies the picks;
clicking outside does nothing (no skip — the modal must be resolved).

If a future card needs two pickers on the same play, the effect
system will need to switch to async `await` resolution — punted
until that card exists.

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

### Bane — `Common Attack` cost 1
```
Description:  Deal 7 Dmg Melee. If the target is Poisoned, deal 7 Dmg Melee again.
Effects:      dmg:7:melee; dmg:7:melee:if_status=poison
Range:        Medium
Tags:         silent, offense, poison
```

Two `dmg` lines: the first always lands, the second is gated by the
target's Poison stack count. Per-target gate, so a future cleave
variant (`dmg:7:melee:cleave; dmg:7:melee:cleave|if_status=poison`)
would hit every enemy with the first swing and only the Poisoned
ones with the second.

### All-Out Attack — `Uncommon Attack` cost 1
```
Description:  Deal 10 Dmg Melee Cleave. Discard 1 card at random.
Effects:      dmg:10:melee:cleave; discard:1:random
Range:        Medium
Tags:         ironclad, offense, aoe
```

`:random` on the discard skips the picker. Drop the `:random` and
the player would be prompted to pick a card to discard instead —
that's Acrobatics, not All-Out Attack.

### Armaments — `Common Skill` cost 1
```
Description:  Gain 5 Block. Upgrade a card in your hand for the rest of combat.
Effects:      gain:block:5; upgrade_hand:1
Upgraded Eff: gain:block:5; upgrade_hand:all
Range:        Self
Tags:         ironclad, defense
```

`upgrade_hand:1` opens the picker. `upgrade_hand:all` skips it and
upgrades every eligible card in hand — already-upgraded cards and
cards with `can_upgrade = false` (Dazed / Wound) are silently
skipped.

### All for One — `Rare Attack` cost 2
```
Description:  Deal 10 Dmg Melee. Put all 0-cost cards from your discard pile into your hand.
Effects:      dmg:10:melee; recall:cost=0
Range:        Medium
Tags:         ironclad, offense
```

`recall` defaults to `from=discard:to=hand`, so the short form
`recall:cost=0` is enough for the canonical "put 0-cost cards from
discard back into hand" shape. To move from a different pile or to a
different destination, spell them out: `recall:cost=0:from=draw:to=hand`.
No picker — recall always grabs every match.

### Bag o' Glitter — `Common Skill` cost 0
```
Description:  Inflict 2 Blind. 10% chance to Exhaust.
Effects:      inflict:blind:2; chance:10:exhaust_self
Range:        Medium
Keywords:
Tags:         debuff, blind, weapon
can_upgrade:  false
```

The Exhaust keyword is deliberately empty — `Exhaust` in the Keywords
column means "always exhausts," which would override the 10% roll.
The `chance:10:exhaust_self` line routes through
`Stats.roll_chance_with_luck`, so every point of Luck adds a 10%
advantage roll on the exhaust check, same as events. Outside the
deckbuilder the roll still fires but `exhaust_self` no-ops (no piles
in action / strategy), which is the right behaviour.

`can_upgrade = false` flags this card as a weapon — weapons get their
own upgrade path (TBD), separate from the standard `+` upgrade that
bumps a value. Until the weapon system lands, Bag o' Glitter simply
doesn't accept the in-combat / smith-fire upgrade.

### Barrel — `Uncommon Attack` cost 1
```
Description:  Deal 6 Dmg Ranged. Fishing Weight.
Effects:      dmg:6:ranged
Range:        Medium
Keywords:     Fishing Weight
Game:         Enter the Gungeon
Tags:         weapon
can_upgrade:  false
```

`Fishing Weight` isn't a bool keyword — it lands in `CardData.addons`
and the engine computes the dmg bonus at play time via
`Stats.addon_damage_bonus`. Fish loot doesn't exist yet so the
bonus is currently 0; once the fish counters land
(`GameState.loot.fish_common` / `_uncommon` / `_rare`), swap the
stub body in `Stats._fishing_weight_bonus` for the real
`common/3 + uncommon/2 + rare` formula and Barrel starts scaling
without further plumbing.

`can_upgrade = false` — Barrel is a weapon, same convention as Bag
o' Glitter; the standard `+` upgrade path doesn't apply.

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

## Card boosts (Accuracy and friends)

`boost_cards` registers a persistent combat-scoped modifier. Every
later card play matching the boost's filter resolves with the bonus
folded into the listed stat *before* normal damage math (Vulnerable,
Weak, Frail, Power, etc.) runs — so a boosted Shiv still gets
Vulnerable'd and Power'd on top.

```
boost_cards:<MATCH>:<STAT>:<VALUE>
```

`MATCH` uses an explicit prefix so tag/type/id are never ambiguous:

| Prefix | Meaning | Example |
|---|---|---|
| `tag=X` | Card has tag `X` in its `tags` array. | `tag=shiv` |
| `type=X` | Card's `type` is `X` (`attack` / `skill` / `power`). | `type=attack` |
| `id=X` | Card's `id` is exactly `X`. | `id=strike` |

`STAT` is `dmg` or `block`. Cost boosts route through a different
mechanism (`temp_cost_override`) and aren't supported here today.

Worked example — Accuracy:
```
Description:  Shivs deal 4 additional damage.
Effects:      boost_cards:tag=shiv:dmg:4
Upgraded Eff: boost_cards:tag=shiv:dmg:6
Range:        Self
Keywords:
Type:         Power
```

In `.tres` exactly one of `match_tag` / `match_type` / `match_id` must
be set; the other two stay empty strings. Boosts clear at combat end.

**Mode coverage:** today only the deckbuilder consumes boosts. Action
and Strategy ignore `boost_cards` effects (the scene method doesn't
exist there yet); see the Future Work section below.

## Triggers (After Image and friends)

The `on_<EVENT>` verb (effect type `trigger` in the `.tres`) registers
a listener that lives for the combat. When the event fires, the
inner effect is dispatched through the same EffectSystem with the
player as both source and target by default.

```
on_<EVENT>:<INNER_VERB>:<INNER_ARGS>
```

Available events (mirror of `TriggerBus` signals):

| Event | Fires when |
|---|---|
| `combat_started` | Combat begins (after derived statuses applied). |
| `turn_started` | Each player turn begins. |
| `turn_ended` | Each player turn ends (after Ethereal exhausts). |
| `card_played` | Any card resolves. Fires BEFORE the played card's own effects, so a Power doesn't self-trigger on the play that registers it. |
| `card_drawn` | A card moves from draw pile to hand. |
| `card_discarded` | A card moves from hand to discard pile. |
| `card_exhausted` | A card moves to the exhaust pile (play-time or Ethereal end-of-turn). |
| `damage_dealt` | The player deals damage that lands (post-block). |
| `damage_taken` | Any actor takes damage that lands. |
| `enemy_killed` | An enemy's HP hits 0. |
| `status_applied` | A status finishes applying (`actual_stacks` includes Persistence). |

Inner effect can be any verb the EffectSystem already understands —
`gain`, `inflict`, `dmg`, `draw`, `discard`, `conjure`, `gain_loot`,
even another `boost_cards`. Self-targeted defaults (no `target` field)
resolve onto the player.

Worked example — After Image:
```
Description:  Whenever you play a Card, Gain 1 Block.
Effects:      on_card_played:gain:block:1
Type:         Power
Range:        Self
Keywords:
```

`.tres`:
```gdscript
{
  "type": "trigger",
  "on": "card_played",
  "effect": { "type": "block", "value": 1, "target": "self" },
}
```

Worked example — Demon Form (sketched):
```
Description:  At the start of your turn, gain 2 Power.
Effects:      on_turn_started:gain:power:2
```

**Mode coverage:** today only the deckbuilder fires power triggers.
Action and Strategy don't register triggers (their handler no-ops via
`has_method`), so a Power card with `on_card_played:...` in an action
loadout is silently inert. See Future Work.

## Loot (Alchemize and friends)

`gain_loot` writes to `GameState.loot`, a Dictionary keyed by kind
(`potion` / `scroll` / `key`) with int counts. The counter is the
placeholder until the real potion/scroll/key catalogs and inventory
UI exist; once they do, `add_loot` will roll a concrete id from the
named kind and append to a real list.

```
gain_loot:<KIND>:<COUNT>
```

Worked example — Alchemize:
```
Description:  Gain 1 Potion Item. Exhaust.
Effects:      gain_loot:potion:1
Type:         Skill
Range:        Self
Keywords:     Exhaust
```

`.tres`:
```gdscript
{ "type": "gain_loot", "kind": "potion", "value": 1 }
```

The `Exhaust` keyword goes on the Keywords column (sets `exhaust =
true`), not into the Effects DSL.

## Status decay & per-status engine logic

Most statuses are stack-based ints on `CombatActor.statuses` keyed by
StringName. Effects that touch them go through `inflict:` (debuff) or
`gain:` (buff) — the engine never special-cases a status name there;
the row in `statusesnew` and the engine logic for that status live
side by side.

The decay set — statuses that step down by 1 each turn — is owned
once on `Stats.DECAY_STATUSES`:

```
vulnerable, weak, frail, burn, poison, regeneration, dodge, blind
```

Add a status to that list and every combat mode picks up the
decay. Statuses **not** on the list (Power, Strength-like permanent
buffs, Persistence, …) stick for the combat.

**Per-mode timing:**

- **Deckbuilder** — decay runs at end of the player's turn (player
  decays before enemies act) and after each enemy's planned move.
- **Strategy** — once the status system lands there, decay will run
  in `BattleTurnManager.end_current_turn` so each unit decays at the
  close of its own turn. Statuses don't apply in strategy today
  because `BattleUnit` has no `statuses` dict — adding one is the
  unlock for Bag o' Glitter and any other inflict-driven card in
  tactical combat.
- **Action** — there's no discrete turn, so a real-time "turn tick"
  fires every `Stats.ACTION_TURN_TICK_SECONDS` (15s) and decays
  every living actor. The tick is independent of Haste / Slow on
  purpose — debuff duration shouldn't accelerate with tempo.

### Tick vs decay ordering (canonical)

A status with both a per-turn tick (Burn deals 3, Poison deals X =
stacks, Regen heals X = stacks) and a decay rule must resolve the
tick **before** the decay. Otherwise Poison-5 at start of turn would
deal 4 damage (decayed first), which is wrong.

```
turn_start:
  1. fire every `on_turn_start` status effect with CURRENT stacks
  2. decay every "start of turn" status by 1

turn_end:
  1. fire every `on_turn_end` status effect
  2. decay every "end of turn" status by 1
```

The Decay column on the status sheet tells the engine **which
boundary** the decay runs at; the tick verb's `on_turn_start` /
`on_turn_end` says when the tick fires. They're expected to match
(no card today has a tick on one boundary and decay on the other),
but the boundaries are separate fields so an exotic future status
can split them if needed.

The rule lives in code at `Stats.decay_actor_statuses` — see the
comment block there before wiring any tick / decay logic.

### Blind

`Blind` is the canonical attacker-side debuff. Each Attack-typed
damage hit (`damage_type: melee` or `ranged`) rolls
`Stats.roll_blind_miss`; on a miss the damage is suppressed entirely
(no block consumption, no trigger fire). Spell / heal / status
effects aren't gated.

Luck biases the outcome in the player's favor either direction:

- Player attacks with Blind → roll on the inverse hit chance so
  Luck advantage = more hits land.
- Enemy attacks the player with Blind → roll on the miss chance
  directly so Luck advantage = more enemy whiffs.

Miss chance is currently `Stats.BLIND_MISS_PCT = 30` regardless of
stack count (matches the sheet's "30% Miss Chance" language; stacks
extend duration, not magnitude). Bag o' Glitter applies 2 stacks
(2 turns / 30s of action play before it wears off).

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

## Future work

Tracked here so the design intent doesn't get lost between commits.

### Power icons in combat HUDs

Some Power cards need an icon that persists in the combat HUD so the
player can see which non-status passives are active and hover them
for a description. Cards whose entire effect is `gain:<status>:<n>`
(Inflame, Demon Form, …) do **not** need a power icon because the
status badge already represents them — icons are only for Powers
with bespoke trigger logic.

Authoring path (proposed when this lands):

- Drop the icon at `images/powericons/<ImgName>Power.png` matching the
  same `Img` column used for the card art (so Anger uses `AngerPower.png`).
- Add a `power_icon: Texture2D` field on `CardData`. Either auto-link by
  convention (image name + `Power` suffix) or set the field explicitly
  in the `.tres`.
- Combat scenes each grow a small "Active Powers" strip that shows
  every Power with `power_icon != null` resolved this combat. Hover
  uses Godot's built-in `tooltip_text` to show `display_name` + a
  short description.

Open questions to settle when implementing:

- Strip placement (top-left near HP, beside the hand, above the
  ability bar in action?).
- Whether stacked copies of the same power show one icon with a count
  badge or one icon per stack.
- Whether action/strategy duplicate the deckbuilder's strip layout or
  each gets a mode-specific placement.

### Action / Strategy trigger coverage

`trigger` / `on_<event>` is deckbuilder-only today. Action and
Strategy don't have an exact analog of `card_played` (action uses
ability slot activations, strategy uses ability picks per turn), so
the mapping needs design:

- Action could fire `card_played` when an ability slot is activated,
  and `turn_started` doesn't really apply — likely needs a fresh
  event like `enemy_engaged` instead.
- Strategy fires `turn_started` naturally per player turn; mapping
  ability casts to `card_played` is reasonable.

When this lands, both scenes need `register_trigger(on, effect)` plus
the `_fire_power_triggers` calls wired into their respective signal
points.

### Action / Strategy `boost_cards` coverage

`boost_cards` is deckbuilder-only today. Equivalent semantics for the
other modes need:

- Action: a boost should bump the listed stat on matching ability
  cards when they fire. Match logic is identical (tag/type/id on the
  ability's `CardData`).
- Strategy: same idea on the AbilityPool. Boosts wouldn't apply to
  the basic Attack/Defend buttons unless they have matching tags.

Both modes should reuse `card_boosts: Array` and the matcher helpers
already in `DeckbuilderCombat` — pull them onto a small shared script
or autoload when the second consumer lands.

### Real potion / scroll / key catalogs

`GameState.loot` is currently `{potion: int, scroll: int, key: int}`
counters that `gain_loot` increments. Once concrete potion / scroll
ids exist:

- Replace the int values with `Array[StringName]` (or whatever id
  type the catalog uses).
- `add_loot` should roll a random id of the requested kind and
  append to the list. Take care to keep the same method signature so
  existing callers (Alchemize, future cards) don't break.
- Build an inventory UI that lets the player consume loot during
  combat / between rooms.
- Plumb `gain_loot` into a more specific form for cards that grant a
  *specific* potion: `{type: "gain_loot", id: "fire_potion"}` should
  bypass the random roll.

### Discard polish

Today `discard` picks a random card from hand (deckbuilder) and the
lowest-cooldown ability (action/strategy). A future "choose what to
discard" variant would be useful for cards like Reckless Charge where
the discard is part of the cost and the player should pick — this
needs a small modal in deckbuilder and is a no-op in action/strategy.

### Energy gain / loss in Action and Strategy

Shipped. `gain_energy:N` / `lose_energy:N` now resolve in all three
modes via `scene.gain_energy(n)` / `scene.lose_energy(n)`:

- **Deckbuilder** — `gain_energy` bumps the per-turn energy pool;
  `lose_energy` drains it (floored at 0).
- **Action** — `gain_energy:N` extends a Haste window by N seconds
  (1.3× movement / basic attack / ability cooldown tick); `lose_energy:N`
  extends a Slow window by N seconds (0.7×). Reapplying stacks
  duration, not magnitude. If both Haste and Slow are live they
  multiply, so a stray `lose_energy` while Haste is up nets to ~0.91×
  rather than cancelling the buff.
- **Strategy** — `gain_energy:N` adds N to a per-turn energy budget
  that unlocks extra ability casts beyond the one-per-turn cap; each
  extra cast pays the card's `cost` out of the budget. Budget resets
  to 0 at turn start. `lose_energy:N` eats the budget first; if it
  would go negative the remainder locks the normal ability use for
  the turn.

Adrenaline (`gain_energy:1; draw:2`, Exhaust) is the canonical test
card — it exercises the bare `gain_energy` path in all three modes.
