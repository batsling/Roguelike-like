# Card Authoring — Spreadsheet ↔ Code Reference

This is the canonical mapping between the `cardsnew` sheet in
`tools/Roguelikes.xlsx` and the `.tres` files under
`data/cards/`. Use this when adding a new card so the
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
| `Lifesteal` | Stamps `lifesteal: true` on the card's dmg effects (effect_flag hook); every mode's `deal_damage` heals the attacker for the unblocked damage dealt. Reaper. |
| `Indiscriminate` | Re-rolls a random enemy per hit/application and skips the target picker. Pairs with dmg `xN` (Sword Boomerang) or `inflict ... times=N` (Bouncing Flask). |

To ship a new addon: add a row to `addonsnew`, add a switch arm to
`Stats.addon_damage_bonus` (or a sibling function for non-damage
modifiers), and put the addon name in any card's Keywords column.

## Element column

Single element word → `CardData.element` (lower-cased; `Physical`/blank/`N/A`
means none). Wired through the `Elements` registry (`scripts/runtime/Elements.gd`,
the code side of the `elements` sheet) for two things:

1. **Effect on Attack** — when a *damaging* elemental hit lands, the element
   applies a 1-stack on-hit status. Blood / Dark / Fire are UNCONDITIONAL —
   every connecting hit stacks another point; only Poison keeps its sheet
   condition. Fires in all three combat modes. The generator surfaces the
   always-on rider on the card text: a damaging Blood/Dark/Fire card's
   description (and upgraded description) ends with "Inflict 1 Bleed." /
   "Inflict 1 Blind." / "Inflict 1 Burn." automatically — don't write it into
   the sheet's Description cell yourself.
2. **Colour** — in action combat, the card's outward attack visual (smear /
   swing / projectile / beam / disc / smite / bounce) is tinted the element's
   colour.

| Element | On-hit effect | Colour |
|---|---|---|
| `Blood` | Inflict 1 Bleed (always) | Red |
| `Dark` | Inflict 1 Blind (always) | Purple |
| `Fire` | Inflict 1 Burn (always) | Orange |
| `Poison` | Inflict 1 Poison unless the attack already poisons / target already poisoned | Light Green |
| `Earth` | None (sheet: N/A) | Brown |
| `Electric` | Colour-only for now (rule needs the Wet status) | Yellow |
| `Water` | Colour-only for now (needs Wet) | Blue |
| `Physical` | Default, leave blank | — |

To add a new element: add a row to the `elements` sheet (Color + Effect on
Attack), then add its colour to `Elements.COLORS` and, if it has an on-hit
effect, a `match` arm in `Elements.on_hit_status`.

## Effects DSL

Semicolon-delimited list of effect lines. Each line is
`verb:arg1:arg2[:argN]`. Whitespace around `;` is fine.

### Verbs

| Verb | Arguments | Meaning | `.tres` form |
|---|---|---|---|
| `dmg` | `VALUE[xN]:DAMAGE_TYPE[:cleave\|if_status=STATUS]` | Deal damage. `xN` = multi-hit (Twin Strike). `cleave` = `target: all_enemies`. `if_status=X` skips the hit per target when that target lacks status X (Bane's second hit). | `{type: "dmg", value, target, damage_type, hits?, if_target_status?}` |
| `gain` | `STAT:VALUE` | Player gains the stat (block, power, defense, dodge, …). `gain:block:5:per=exhausted` (Second Wind) makes the value per-card: total Block = value × how many cards the preceding `exhaust:all` swept away (`value_from: "exhausted"`, the block mirror of dmg's `hits=exhausted`). | `{type: "block"/"status", value, stacks, status, target: "self"}` |
| `inflict` | `STATUS:STACKS[:cleave][:if_intent=attack]` | Apply a debuff to the targeted enemy (or all enemies with `cleave`). `if_intent=attack` (Go for the Eyes) gates the inflict on the target telegraphing an attack — see the intent gate section. NEGATIVE stacks (Disarm: `inflict:power:-2`) DRAIN the status instead: the engine writes the status dict directly (Stats.drain_status) so the stored value can go below zero — the badge shows the negative count in red. No Persistence scaling, no status_applied reaction. STACKS may be an X form (Malaise: `inflict:power:-X`, `inflict:weak:X+1`) — the enemy-side mirror of `gain:<status>:X`: the count is the energy spent on the play, a leading `-` flips it into a drain (`stacks_mult: -1`) and a trailing ±N rides `stacks_bonus`. | `{type: "status", status, stacks, target: "enemy"/"all_enemies", if_target_intent?, stacks_from?, stacks_mult?, stacks_bonus?}` |
| `draw` | `N[:skill_block=B]` \| `to=N` \| `count=discarded` | Draw N cards (action: each draw opens a temporary auto-cast slot). `draw:count=discarded` (Calculated Gamble) draws one per card the preceding `discard:all` sent away. `draw:to=6` (Expertise) draws until the hand holds N cards — action's "hand" is every armed cooldown slot (auto slots + the two click cards). `skill_block=B` (Escape Plan) grants B Block per drawn card that is a Skill — `draw_cards` returns the drawn cards in every mode so the rider can inspect them. | `{type: "draw", value: N, skill_block?, to_hand?, value_from?: "discarded"}` |
| `discard` | `N[:random]` \| `all` | Mirror of `draw`. Deckbuilder/Strategy: pick N from hand via the CardPickerModal (default — player chooses, like Acrobatics). Append `:random` for the engine-picked random variant (All-Out Attack). Always excludes the played card. `discard:all` (Storm of Steel) discards the whole hand with no picker and records the count for `count=discarded`. `discard:all:non_attack` (Unload) narrows the sweep to non-Attack cards (action: only non-Attack temp slots collapse). Action: collapses temporary auto-slots (`all` collapses every one). | `{type: "discard", value: N, random?: bool}` / `{type: "discard", all: true}` |
| `exhaust` | `N[:random]` \| `all` | Deckbuilder/Strategy mirror of `discard` but routes picks to the exhaust pile. Same player-choice default and `:random` flag. `exhaust:all` (Fiend Fire) exhausts the whole hand minus the played card, no picker, and records the count for a following `dmg …:hits=exhausted`. `exhaust:all:non_attack` (Sever Soul) narrows the sweep to non-Attack cards (action: armed Attacks are spared; curse slots still clear). Action: `exhaust:N` no-ops; `exhaust:all` empties every other cooldown slot (see the dmg shorthand notes). | `{type: "exhaust", value: N, random?: bool}` / `{type: "exhaust", all: true}` |
| `topdeck` | `N[:random][:from=discard][:free=until_played]` | Put N cards from hand on TOP of the draw pile (Warcry). Deckbuilder/Strategy open the CardPickerModal by default; `:random` skips it. Action auto-picks: a temporary auto-slot's card goes back on top of the auto draw pile (or a random discard when no temp slots are up). `from=discard` (Headbutt) pools the pick from the DISCARD pile instead — the picker browses the discard; action always pulls a random discard back on top, never collapsing a slot. `free=until_played` (Setup): the placed card costs 0 until it is PLAYED — the override rides `CardInstance.free_until_played` across pile moves and turn ends, cleared the moment the play pays; action arms the card ONCE at the 0-cost cooldown when it's next drawn. | `{type: "topdeck", value: N, random?: bool, from?: "discard", free_until_played?: bool}` |
| `recall` | `<FILTER>[:from=PILE][:to=PILE]` | Deckbuilder: move (not copy) every card in the source pile matching `FILTER` into the destination pile. `FILTER` today is `cost=N`; defaults are `from=discard`, `to=hand` (All for One). No-op in action/strategy. | `{type: "recall", from: PILE, to: PILE, filter: {…}}` |
| `upgrade_hand` | `N\|all[:random]` | Deckbuilder: upgrade in-place. `upgrade_hand:1` opens the picker so the player chooses (Armaments); `upgrade_hand:all` upgrades every eligible card in hand silently (Armaments+). Append `:random` to skip the picker for the N form. Skips cards that are already upgraded or have `can_upgrade = false`. No-op in action/strategy. | `{type: "upgrade_hand", value: N\|"all", random?: bool}` |
| `boost_cards` | `<MATCH>:<STAT>:<VALUE>` | Persistent in-combat modifier. Every later card matching `MATCH` resolves with `STAT + VALUE`. `MATCH` is exactly one of `tag=X` / `type=X` / `id=X`. `STAT` is `dmg` or `block`. Deckbuilder only today. | `{type: "boost_cards", match_tag/match_type/match_id, stat, value}` |
| `on_<EVENT>` | `<INNER_VERB>:<INNER_ARGS>[:until=turn_end]` | Register a persistent in-combat listener. When the named event fires, the inner effect runs; its target resolves like a played card's (`all_enemies` fans out, `enemy` = the event's target, else the player). `<EVENT>` is a scene trigger event (see Triggers section). After Image: `on_card_played:gain:block:1`; Envenom: `on_unblocked_attack:inflict:poison:1`. New events: `attack_played` (Rage — fired alongside card_played when the played card is an Attack) and `hit_by_attack` (Flame Barrier — an enemy melee/ranged hit LANDS on the player, block included; the attacker is the event target). `until=turn_end` makes the listener turn-scoped: it expires at the start of the player's NEXT turn — after the enemy turn, so Flame Barrier retaliates all the way through it (action: one turn tick). See the Skill-type marker section. All three modes register; events with no analog in a mode simply never fire there. | `{type: "trigger", on: "<event>", effect: {…inner…}, until?}` |
| `keep_block` | (none) | Barricade: the player's Block is not removed at the turn boundary (action: no longer fades over time). Sticky for the combat. | `{type: "keep_block"}` |
| `retain` | `N` | Inner verb for `on_turn_ended` (Well-Laid Plans): at end of turn keep up to N hand cards. Resolved by the scenes' end-turn intercept BEFORE the discard; inert in the generic trigger pass. | `{type: "retain", value: N}` |
| `gain_loot` | `<KIND>:<COUNT>` | Add COUNT loot of `KIND` (`potion` / `scroll` / `key`) to the run-scope counter on GameState. Concrete potion/scroll catalogs land later; the counter is the placeholder. Alchemize: `gain_loot:potion:1`. | `{type: "gain_loot", kind: "potion", value: 1}` |
| `heal` | `VALUE[:self]` | Recover HP (defaults to self). | `{type: "heal", value, target: "self"}` |
| `gain_energy` | `N` | Deckbuilder: refund N energy. Action: ~N-second Haste window (1.3× movement, basic attack rate, ability cooldown ticking). Strategy: opens a per-turn budget of N for extra ability casts beyond the one-per-turn cap, paid out at the card's cost. | `{type: "gain_energy", value: N}` |
| `lose_energy` | `N` | Mirror of `gain_energy`. Deckbuilder drops N from the pool (floored at 0). Action: ~N-second Slow window (0.7×). Strategy: eats the energy budget first, then locks the normal ability use for the turn if the budget would go negative. | `{type: "lose_energy", value: N}` |
| `gain_gold` | `N` | Award N gold (rare on cards). | `{type: "gain_gold", value: N}` |
| `lose_hp` | `VALUE` | Pay HP as a cost. | `{type: "lose_hp", value}` |
| `exhaust_self` | (none) | Exhaust the played card. Redundant if Keywords has `Exhaust`. | `{type: "exhaust_self"}` |
| `conjure` | `CARD_ID:DESTINATION[:COUNT\|count=discarded]` | Create COUNT copies of CARD_ID into the named pile. `CARD_ID` of `self` means "this card" and inherits its upgrade state; append `+` (e.g. `shiv+`) to force the upgraded form of a fixed card. `DESTINATION` is `hand` / `draw` / `discard`. COUNT defaults to 1. `count=discarded` (Storm of Steel) conjures one per card the preceding `discard:all` sent away. | `{type: "conjure", card_id, destination, count, upgraded?, count_from?}` |
| `conjure_random` | `TYPE:DESTINATION[:COUNT][:free]` | Mint COUNT random cards of TYPE (`power` / `attack` / `skill`) into the named pile, rolled from the run's **conjure pool** — the reward pool scoped to the deck picked on the New Run screen (`Data.conjure_card_pool`). `free` makes a hand mint cost 0 for THIS turn. White Noise: `conjure_random:power:hand:free`. See the Random conjures section. | `{type: "conjure_random", card_type, destination, count, free?}` |
| `power_multiplier` | `N` | Multiplies the Power stat's contribution to this card's damage by N. Applies to the preceding `dmg:` lines on the same row. | Added as `power_multiplier: N` on each `dmg` effect. |
| `chance` | `PCT:<INNER_VERB>:<INNER_ARGS>` | Roll PCT% on the shared luck-modified RNG (Stats.roll_chance_with_luck — every point of Luck adds a 10% advantage roll, mirroring how events roll). On success, dispatch the inner effect through the same EffectSystem with the same ctx. Inner can be any verb. Bag o' Glitter: `chance:10:exhaust_self`. | `{type: "chance", percent: N, effect: {…inner…}}` |
| `if_target` | `STATUS:<INNER_VERB>:<INNER_ARGS>` | Resolve the inner effect only when the PICKED enemy target carries STATUS (Dropkick: `if_target:vulnerable:gain_energy:1`). A wrapper — not a kv on the inner verb — because the inner verbs are scene effects (gain_energy / draw) that would otherwise resolve against the player and lose the enemy from ctx. In action the payoff fires once when any hit enemy carries the status. | `{type: "if_target_status", status, target: "enemy", effect: {…inner…}}` |
| `cost_reduce` | `per=COUNTER` | Card-level dynamic discount: the card costs 1 less per point of the named live counter (see Scaling counters), floored at 0 and re-read every time the cost is shown or paid. Blood for Blood: `cost_reduce:per=hp_losses`; Eviscerate: `cost_reduce:per=discards_this_turn`. Cost IS cooldown in action, so a re-armed slot picks up the current discount. NOT an on-play effect — the generator pops it into `CardData.cost_reduce_from`. | `cost_reduce_from = &"COUNTER"` (field, not an effect) |
| `cost_increase` | `per=COUNTER` | The surcharge mirror of `cost_reduce`: the card costs 1 MORE per point of the counter, read just as live. Masterful Stab: `cost_increase:per=hp_losses` — every HP-loss instance raises the shown/paid cost (and lengthens the cooldown in action). Both fields may coexist on one card; the discount and surcharge net against each other before the 0 floor. | `cost_increase_from = &"COUNTER"` (field, not an effect) |
| `if_counter` | `COUNTER:<INNER_VERB>:<INNER_ARGS>` | Resolve the inner effect only when the named live counter (see Scaling counters) is > 0 — the counter sibling of `if_target`. Sneaky Strike: `if_counter:discards_this_turn:gain_energy:2`. All three modes; action translates the inner verb as usual (energy = Haste window). | `{type: "if_counter", counter, effect: {…inner…}}` |
| `double` | `block` \| `<STAT>` | Entrench (`double:block`) / Limit Break (`double:power`): double the player's current Block / the named status's stacks. Block doubles OUTRIGHT (no Frail cut — it isn't "gained" block; action doubles the decay pool and raises the soft cap via `double_block`). Statuses double SIGNED, so a Power drained negative (Disarm) doubles further down. | `{type: "double_stat", stat}` |
| `autoplay_top` | `[exhaust]` | Havoc: play the top card of the draw pile at no cost, then exhaust it. The autoplay counts as a played card (card_played / attack_played powers react, Sentinel's exhausted trigger fires); attacks land on a random living enemy; an X-cost card plays with X = 0; a Power registers and is consumed (never exhausted). Action plays the top of the AUTO draw pile — the card leaves the rotation for the combat (Exhume can re-arm it). | `{type: "autoplay_top", exhaust: bool}` |
| `copy_from_hand` | `N[:FILTER]` | Dual Wield: choose a hand card matching FILTER (`attack_or_power` today) and conjure N copies of it to hand, upgrade state preserved. Deckbuilder/strategy open the CardPickerModal; action auto-picks a random ARMED Attack/Power (auto slots + the two click cards) and opens N one-shot temp slots with it. | `{type: "copy_from_hand", count, filter}` |
| `exhume` | `N` | Exhume: move N cards from the exhaust pile back to hand (picker; never another Exhume). Action has no browsable exhaust pile — a random card removed by exhaust effects this combat (`action_exhausted`) re-arms as a one-shot temp slot. | `{type: "exhume", value: N}` |
| `retrieve` | `N:from=discard\|draw` | Hologram / Seek: move N cards from the named pile to hand. Deckbuilder/strategy open the picker over that pile (the pile-browsing sibling of `exhume`); action re-arms a random card from its auto analog of the pile as a one-shot temp slot. | `{type: "retrieve", value: N, from: PILE}` |
| `multiply` | `STATUS:N` | Catalyst (`multiply:poison:2`, upgraded `:3`): multiply the PICKED enemy target's stacks of the status by N. A direct signed write like `double` — no Persistence scaling, no status_applied reaction; zero stacks stay zero (logged as a fizzle). Action reads "the target" as the nearest living enemy. | `{type: "multiply_status", status, factor: N, target: "enemy"}` |
| `free_hand` | (none) | Bullet Time: every card currently in hand costs 0 for THIS turn (`temp_cost_override`, the Mummified Hand slot — cleared when a card leaves hand). Action: every running cooldown (auto slots + the two click cards) finishes NOW, one free use each. | `{type: "free_hand"}` |
| `nightmare` | `N` | Nightmare: choose a card in hand; at the start of the player's NEXT turn, N copies of it (upgrade state preserved) arrive in hand. Deckbuilder/strategy open the picker and bank the pick scene-side (`_nightmare_pending`); action auto-picks a random armed card and opens the copies as one-shot temp slots at the next turn tick. | `{type: "nightmare", count: N}` |
| `if_intent` | `attack:<INNER_VERB>:<INNER_ARGS>` | Spot Weakness: resolve the inner effect only when the PICKED enemy target is telegraphing an attack — the intent sibling of the `if_target` wrapper, sharing the same per-mode predicate as `inflict … if_intent=attack` (see the intent gate section). Action reads the NEAREST enemy (winding up / mid-attack). | `{type: "if_target_intent", intent, target: "enemy", effect: {…inner…}}` |
| `sequential_upgrade` | `N` | The card can be upgraded ANY number of times; each upgrade adds +N to every dmg value instead of flipping to a one-shot upgraded form (leave the ↑ columns N/A — the upgrade IS the step). Searing Blow: `sequential_upgrade:3`. Card-level: lands in `CardData.sequential_upgrade_step` and forces `can_upgrade`; the count lives per physical card on `CardInstance.upgrade_count` (persisted, shown as `+`, `+2`, `+3`, …). See the Sequential upgrades section. | `sequential_upgrade_step = N` (field, not an effect) |

### Argument shorthand for `dmg`

`dmg:VALUE:DAMAGE_TYPE[:MODIFIER]`

- `dmg:6:melee` — Strike
- `dmg:5x2:melee` — Twin Strike (resolves twice)
- `dmg:5xX:melee:cleave` — Whirlwind (X-cost repeat: resolves once per energy
  spent on the play; stored as `hits_from: "energy"`. See X-cost below.)
- `dmg:4:ranged:cleave` — Thunderclap (ranged + `target: all_enemies`)
- `dmg:14:melee; power_multiplier:3` — Heavy Blade (Power counts triple)
- `dmg:8:melee:cleave` — Cleave (melee + all_enemies)
- `dmg:block:melee` — Body Slam (a non-numeric value slot names a dynamic
  source; `block` = deal damage equal to the attacker's current Block. Stored
  as `value_from: "block"`, resolved at hit time in every mode so Power/Weak/
  Vulnerable still layer on top.)
- `dmg:6:melee:per=attacks_this_turn` — Finisher (`per=COUNTER` scales the hit
  by a live counter: the flat value becomes the per-unit amount and the counter
  is the multiplier, so this deals `6 × attacks played this turn`. Stored as
  `value_from: "attacks_this_turn"`, `value_mult: 6`. See Scaling counters.)
- `dmg:7:ranged:hits=exhausted` — Fiend Fire (one hit per card the preceding
  `exhaust:all` sent away this play; stored as `hits_from: "exhausted"`, read
  off the scene's `last_exhaust_count`. Zero exhausted = zero hits. Action:
  `exhaust:all` empties the auto rotation — temp auto-slots collapse, the base
  slot's card is dropped and re-arms, curse slots clear; the two click weapons
  are spared — and the dmg fires one volley per card removed; nothing to
  exhaust = the cast fizzles.)
- `dmg:14:melee:if_hand=all_attacks` — Clash (the hit whiffs unless every
  OTHER card in hand is an Attack — statuses and curses spoil it too. Action's
  "hand" is every card riding a cooldown slot: a non-Attack in the auto
  rotation, a curse slot, or a non-Attack click card makes it whiff when its
  cooldown completes.)
- `dmg:4:ranged:hits=skills_in_hand` — Flechettes (one hit per Skill card in
  hand at play time, the played card excluded — the hand-count sibling of
  `hits=exhausted`; stored as `hits_from: "skills_in_hand"`. Zero Skills =
  zero hits. Action counts Skill cards riding cooldown slots — the auto
  rotation plus the two click cards — and fizzles with none armed.)
- `dmg:50:ranged:cleave:if_draw=empty` — Grand Finale (the hit whiffs unless
  the DRAW pile is empty when the card is played; the kv gate coexists with
  the positional `cleave` on the same line. Action's draw pile is the auto
  draw pile, so the burst only lands once the rotation has chewed through its
  queue — note `_auto_draw_one` reshuffles the discard back in on the next
  draw, so the window is real but brief.)
- `dmg:6:melee:bonus=2:per_name=strike` — Perfected Strike (`bonus=N` +
  `per_name=STR`: the hit deals N additional damage per card in the player's
  combat deck whose name contains STR, case-insensitive — hand + draw +
  discard, the played card included, so a base deck's Strikes plus Perfected
  Strike itself count. Stored as `bonus_per_card: N`,
  `bonus_per_card_name: "str"`; resolved at play time in every mode. Action's
  "deck" is the combat rotation: auto slots + the two click cards + the auto
  draw/discard piles. Upgraded Strikes still match — `Strike+` contains
  `Strike`.)

### The intent gate (`if_intent=attack`) — Go for the Eyes

`inflict:STATUS:STACKS:if_intent=attack` lands the debuff only when the
target "intends to Attack". Stored as `if_target_intent: "attack"` on the
status effect and answered per mode:

- **Deckbuilder** — the enemy's pre-rolled `planned_move.intent_type` is
  `"attack"` (the same classification the intent icon uses), checked by
  `Stats.actor_intends_attack`.
- **Strategy** — the unit's telegraphed `EnemyAI.next_intent` carries a
  dmg-typed effect (the classification behind the telegraph badge colour).
- **Action** — the standard is the telegraphing shooters (the Isaac /
  Brotato ranged enemies): an enemy "intends" while it is PREPARING an
  attack — the pre-fire wind-up telegraph (`winding`) — or while it is IN an
  attack — the attack animation window every strike opens (contact hit,
  random spew, wind-up start) — `ActionCombat._enemy_intends_attack`. An
  enemy that is merely chasing with an attack ready does NOT count.

Only `attack` is recognised today; a future `if_intent=buff` etc. just needs
the parser kv and a match arm in the same predicate.

Worked example — Go for the Eyes — `Common Attack` cost 0:
```
Description:  Deal 3 Dmg Melee. If the target intends to Attack, Inflict 1 Weak.
Effects:      dmg:3:melee; inflict:weak:1:if_intent=attack
Upgraded Eff: dmg:4:melee; inflict:weak:2:if_intent=attack
Attack:       Swing, Small
Tags:         defect, offense, debuff
```

### The `drawn:` trigger prefix — Endless Agony

Like the curse trigger prefixes (`eot:` / `on_play_other:`), `drawn:` stores a
card-level trigger that fires when THIS card is drawn — Endless Agony's
`dmg:4:ranged; drawn: conjure:self:hand` conjures a copy of itself to hand on
every draw. Conjured copies arrive without being drawn, so the trigger never
cascades. Action has no draws for its rotation, so the trigger is inert there.

### The `exhausted:` trigger prefix — Sentinel

The exhaust sibling of `drawn:`: a card-level trigger that fires when THIS
card is exhausted — by an exhaust effect (True Grit, Second Wind, Fiend
Fire), its own Exhaust keyword, or Havoc's autoplay-exhaust. Sentinel:
`gain:block:5; exhausted: gain_energy:2`. The upgraded Effects cell may
author different trigger values (Sentinel+ refunds 3) — the generator emits
them as `CardData.upgraded_triggers`, read through `get_effective_triggers`.
Action fires it when an exhaust sweep removes the card from the rotation
(the energy refund arrives as its Haste-window translation).

### Skill-type marker statuses + turn-scoped triggers — Flame Barrier / Rage / Double Tap

Turn-scoped Skills keep their BEHAVIOR on the card row and use the status
sheet only for the icon:

1. The card's Effects DSL does the work — a turn-scoped trigger registration
   (`on_hit_by_attack:dmg:4:magic:until=turn_end`, `on_attack_played:gain:block:3:until=turn_end`)
   or an engine-consumed counter (`gain:double_tap:1` — the scenes replay the
   next Attack and burn a stack).
2. The same Effects cell also gains a marker status (`gain:flame_barrier:4`)
   whose ONLY job is showing an icon + stack count on the status strip.
3. The marker gets a `statusesnew` row with the Type **Skill** (vs
   Buff/Debuff/Ability): its Effect column is prose, never dispatched, and
   its icon/description feed the badge tooltip via ReferenceCatalog.

Skill-type stacks and `until=turn_end` triggers are wiped together at the
START of the player's next turn (`Stats.clear_skill_markers` +
`Stats.expire_turn_triggers`) — after the enemy turn, so Flame Barrier
retaliates against every enemy hit before it fades. Action wipes on the turn
tick. The wipe list is data-driven off the sheet's Type column, so a new
Skill-type row (Burst joined this way) needs no code change. NOTE: a status
that must SURVIVE into the next turn (Blur saves block AT the next turn
start; Next Turn Block pays there) is a Buff, not a Skill-type marker — the
marker wipe would eat it exactly when it should fire.

Worked example — Flame Barrier — `Uncommon Skill` cost 2, Element `Fire`:
```
Description:  Gain +12 Block. Until your next turn, enemies that hit you
              take 4 Magic Dmg Fire and gain 1 Burn per contact.
Effects:      gain:block:12; gain:flame_barrier:4;
              on_hit_by_attack:dmg:4:magic:until=turn_end
Upgraded Eff: gain:block:16; gain:flame_barrier:6;
              on_hit_by_attack:dmg:6:magic:until=turn_end
```
The card's Fire element is stamped onto the trigger's inner dmg, so each
retaliation contact applies the element's 1-Burn rider through the normal
on-hit path — the "1 Burn per contact" needs no extra authoring.

### The Ironclad Skills port batch — quick reference

| Card | Effects DSL | Notes |
|---|---|---|
| Disarm | `inflict:power:-2` | `Uncommon Skill` cost 1, Exhaust. Upgrade: -3. Negative inflict = signed drain. |
| Double Tap | `gain:double_tap:1` | `Rare Skill` cost 1. The scenes consume one stack per Attack played and resolve its effects twice. Upgrade: 2 stacks. |
| Dual Weild | `copy_from_hand:1:attack_or_power` | `Uncommon Skill` cost 1. Upgrade: 2 copies. (Sheet keeps the legacy spelling.) |
| Entrench | `double:block` | `Uncommon Skill` cost 2. Upgrade: cost 1. |
| Exhume | `exhume:1` | `Rare Skill` cost 1, Exhaust. Upgrade: cost 0. Never retrieves another Exhume. |
| Flame Barrier | see worked example above | `Uncommon Skill` cost 2, Element Fire. |
| Havoc | `autoplay_top:exhaust` | `Common Skill` cost 1. Upgrade: cost 0. |
| Impervious | `gain:block:30` | `Rare Skill` cost 2, Exhaust. Upgrade: 40. |
| Intimidate | `inflict:weak:1:cleave` | `Uncommon Skill` cost 0, Exhaust. Upgrade: 2. |
| Limit Break | `double:power; exhaust_self` | `Rare Skill` cost 1. Upgrade drops the `exhaust_self` — the Exhaust is authored as an effect, NOT the Keywords flag, precisely so the upgrade can shed it. |
| Offering | `lose_hp:6; gain_energy:2; draw:3` | `Rare Skill` cost 0, Exhaust. Upgrade: draw 5. |
| Power Through | `conjure:wound:hand:2; gain:block:15` | `Uncommon Skill` cost 1. Upgrade: 20. |
| Rage | `gain:rage:3; on_attack_played:gain:block:3:until=turn_end` | `Uncommon Skill` cost 0. Upgrade: 5. |
| Second Wind | `exhaust:all:non_attack; gain:block:5:per=exhausted` | `Uncommon Skill` cost 1. Upgrade: 7 per card. |
| Seeing Red | `gain_energy:2` | `Uncommon Skill` cost 1, Exhaust. Upgrade: cost 0. |
| Sentinel | `gain:block:5; exhausted: gain_energy:2` | `Uncommon Skill` cost 1. Upgrade: 8 Block / 3 Energy (via upgraded_triggers). |
| Shockwave | `inflict:weak:3:cleave; inflict:vulnerable:3:cleave` | `Uncommon Skill` cost 2, Exhaust. Upgrade: 5/5. |
| Spot Weakness | `if_intent:attack:gain:power:3` | `Uncommon Skill` cost 1. Upgrade: 4. |
| True Grit | `gain:block:7; exhaust:1:random` | `Common Skill` cost 1. Upgrade drops `:random` — the player picks. |

### The Silent + Defect Skills port batch — quick reference

The 20 remaining Silent/Defect Skill rows (Hologram and Seek are the Defect
pair). Five new `statusesnew` rows ride with them: **Burst** is the batch's
Skill-type marker (wiped at the start of your next turn, like Double Tap);
**Blur / Next Turn Block / Double Damage** are Buffs with engine behavior
(block persistence at the turn boundary via `Stats.block_persists`, a banked
turn-start `gain_block` payout beside Next Turn Energy/Draw, and a melee/
ranged ×2 in `Stats.resolve_damage`); **Corpse Explosion** is a Debuff — an
enemy that dies carrying it detonates for its Max HP against every other
enemy (`Stats.process_corpse_explosion`, called from each mode's death
sites; chains recurse naturally).

| Card | Effects DSL | Notes |
|---|---|---|
| Blur | `gain:block:5; gain:blur:1` | `Uncommon Skill` cost 1. Upgrade: 8 Block. Each Blur stack saves your Block through one turn boundary, then is spent. Action: the block pool stops fading while a stack is up; one stack per turn tick. |
| Bullet Time | `gain:no_draw:1; free_hand` | `Rare Skill` cost 3. Upgrade: cost 2. The whole hand costs 0 this turn; No Draw locks further draws. Action: every running cooldown finishes now. |
| Burst | `gain:burst:1` | `Rare Skill` cost 1. The scenes replay the next SKILL played this turn (snapshot taken pre-effects, so Burst never doubles itself — but a second Burst can double the first). Upgrade: 2 stacks. |
| Calculated Gamble | `discard:all; draw:count=discarded; exhaust_self` | `Uncommon Skill` cost 0. Upgrade drops the `exhaust_self` (Limit Break's rule — Keywords is card-level). |
| Catalyst | `multiply:poison:2` | `Uncommon Skill` cost 1, Exhaust. Upgrade: ×3. Fizzles on a poison-free target. |
| Corpse Explosion | `inflict:poison:6; inflict:corpse_explosion:1` | `Rare Skill` cost 2. Upgrade: 9 Poison. The marker detonates on death — see above. |
| Deadly Poison | `inflict:poison:5` | `Common Skill` cost 1. Upgrade: 7. |
| Deflect | `gain:block:4` | `Common Skill` cost 0. Upgrade: 7. |
| Dodge and Roll | `gain:block:4; gain:next_turn_block:4` | `Common Skill` cost 1. Upgrade: 6/6. The bank pays through `gain_block` at the next turn start (after the reset), so Frail/Defense apply at payout. |
| Escape Plan | `draw:1:skill_block=3` | `Uncommon Skill` cost 0. Upgrade: +5. Action pays the rider when the opened temp slot's card is a Skill. |
| Expertise | `draw:to=6` | `Uncommon Skill` cost 1. Upgrade: to 7. Action's "hand" is the armed cooldown slots. |
| Hologram | `gain:block:3; retrieve:1:from=discard; exhaust_self` | `Common Skill` cost 1, defect. Upgrade: 5 Block, no Exhaust (authored as `exhaust_self` so the upgrade can shed it). |
| Leg Sweep | `inflict:weak:2; gain:block:11` | `Uncommon Skill` cost 2. Upgrade: 3/14. |
| Malaise | `inflict:power:-X; inflict:weak:X` | `Rare Skill` cost X, Exhaust. Upgrade: `-X-1` / `X+1` via `stacks_bonus`. The first X-value inflict — see the inflict row. |
| Nightmare | `nightmare:3` | `Rare Skill` cost 3. Upgrade: cost 2. Pick a hand card; 3 copies arrive with the next turn-start hand. |
| Outmaneuver | `gain:next_turn_energy:2` | `Common Skill` cost 1. Upgrade: 3. Rides the existing Next Turn Energy machinery. |
| Phantasmal Killer | `gain:double_damage:1` | `Rare Skill` cost 1. Upgrade: cost 0. Your melee/ranged attacks deal double while a stack is up; decays at end of turn. |
| Piercing Wail | `inflict:power:-6:cleave; inflict:shackled:6:cleave` | `Common Skill` cost 1, Exhaust. Upgrade: -8/8. The Shackled return (already engine-side for Shifting) hands the Power back at each enemy's turn end — a one-turn room-wide weaken. |
| Seek | `retrieve:1:from=draw` | `Rare Skill` cost 0, Exhaust, defect. Upgrade: 2 cards. |
| Setup | `topdeck:1:free=until_played` | `Uncommon Skill` cost 1. Upgrade: cost 0. See the topdeck row for the "free until played" override. |

### The Flechettes / Go for the Eyes / … port batch — quick reference

| Card | Effects DSL | Notes |
|---|---|---|
| Flechettes | `dmg:4:ranged:hits=skills_in_hand` | `Uncommon Attack` cost 1, `Projectile, Medium`. Upgrade: 6 per hit. |
| Go for the Eyes | `dmg:3:melee; inflict:weak:1:if_intent=attack` | `Common Attack` cost 0, `Swing, Small`. Upgrade: 4 Dmg / 2 Weak. |
| Grand Finale | `dmg:50:ranged:cleave:if_draw=empty` | `Rare Attack` cost 0, `Nova, Large`. Upgrade: 60. |
| Headbutt | `dmg:9:melee; topdeck:1:from=discard` | `Common Attack` cost 1, `Poke, Small`. Upgrade: 12. |
| Heel Hook | `dmg:5:melee; if_target:weak:gain_energy:1; if_target:weak:draw:1` | `Uncommon Attack` cost 1, `Poke, Small` — Dropkick's wrapper keyed on Weak. Upgrade: 8. |
| Hemokinesis | `lose_hp:2; dmg:15:ranged` | `Uncommon Attack` cost 1, `Projectile, Medium`, Element `Blood`. Upgrade: 20. The lose_hp cost lands in every mode (action routes it through apply_dot) and counts one `hp_losses` instance, so it feeds Blood for Blood's discount. |

### The Immolate / Masterful Stab / … port batch — quick reference

| Card | Effects DSL | Notes |
|---|---|---|
| Immolate | `dmg:21:magic:cleave; conjure:burn:discard` | `Rare Attack` cost 2, `Auto_aoe, target=nearest, Large`, Element `Fire`. Upgrade: 28. A big fire disc dropped on the nearest enemy in action; plain "hit everyone" elsewhere. The conjured Burn is the Status card from the Burn batch. |
| Masterful Stab | `dmg:12:melee; cost_increase:per=hp_losses` | `Uncommon Attack` cost 0, `Poke, Medium`. Upgrade: 16. Costs 1 more per time you've lost Health this combat — the surcharge mirror of Blood for Blood, riding the same `hp_losses` counter. |
| Perfected Strike | `dmg:6:melee:bonus=2:per_name=strike` | `Common Attack` cost 2, `Swing, Medium`. Upgrade: bonus 3. +2 damage per card in the combat deck whose name contains "Strike" (itself included). |
| Poisoned Stab | `dmg:6:melee; inflict:poison:3` | `Common Attack` cost 1, `Poke, Small`, Element `Poison`. Upgrade: 8 Dmg / 4 Poison. The element rule skips its on-hit Poison because the attack already poisons. |
| Pummel | `dmg:2x4:melee` + `Keywords: Exhaust` | `Uncommon Attack` cost 1, `Poke, Small`. Upgrade adds a hit (`2x5`), not damage. |
| Quick Slash | `dmg:8:melee; draw:1` | `Common Attack` cost 1, `Swing, Small`. Upgrade: 12. |
| Rampage | `dmg:8:melee; boost_cards:id=rampage:dmg:5` | `Uncommon Attack` cost 1, `Swing, Small`. Glass Knife's self-boost with the sign flipped: each play registers +5 (upgraded +8) Dmg on every copy of Rampage for the combat. The base 8 never changes on upgrade — only the ramp. |

### Sequential upgrades (Searing Blow)

`sequential_upgrade:N` marks a card **infinitely upgradable**: instead of the
binary base/`+` flip, every upgrade banks another +N onto each of the card's
dmg values. The ↑ columns stay `N/A` — the step IS the upgrade.

- **Per physical card.** The count lives on `CardInstance.upgrade_count`
  (persisted with the deck save) and folds into `get_effects()` exactly like a
  per-instance bonus, so deckbuilder and strategy read it for free. The name
  wears the count: `Searing Blow+`, `+2`, `+3`, …; the description trails the
  banked total (`[+6 Dmg]`).
- **Every upgrade path stacks it.** All upgrade sites route through
  `CardInstance.apply_upgrade()` / filter on `can_take_upgrade()`: the rest
  site smith, Armaments' `upgrade_hand` (deckbuilder AND strategy), Whetstone /
  War Paint's `upgrade_random_deck_cards`, the Egg auto-upgrade on acquire,
  and an upgraded card reward (`from_data(d, true)` = one banked upgrade). A
  sequential card never saturates — it stays a legal pick forever; binary
  cards keep the old one-and-done rule.
- **Action mode.** The rotation resolves cards through
  `GameState._effective_action_card`, which returns a per-`(id, count)` cached
  CardData with the bonus folded in (the sequential sibling of the binary
  upgrade cache), so two `Searing Blow+3` copies share one resource and the
  cooldown formula sees the unchanged cost.

Worked example — Searing Blow — `Uncommon Attack` cost 2:
```
Description:  Deal 12 Dmg Fire Melee. Sequential Upgrade Dmg +3.
Effects:      dmg:12:melee; sequential_upgrade:3
↑ columns:    N/A
Attack:       Swing, Medium
Element:      Fire
Tags:         ironclad, offense, scaling
```

### The Slice / Sneaky Strike / Unload / Searing Blow … port batch — quick reference

| Card | Effects DSL | Notes |
|---|---|---|
| Slice | `dmg:6:melee` | `Common Attack` cost 0, `Swing, Small`. Upgrade: 9. |
| Reckless Charge | `dmg:7:melee; conjure:dazed:draw` | `Uncommon Attack` cost 0, `Smash, Small`. Upgrade: 10. Shuffles a Dazed into the draw pile. |
| Wild Strike | `dmg:12:melee; conjure:wound:draw` | `Common Attack` cost 1, `Smash, Small`. Upgrade: 17. Its name feeds Perfected Strike's count. |
| Sneaky Strike | `dmg:12:melee; if_counter:discards_this_turn:gain_energy:2` | `Common Attack` cost 2, `Poke, Small`. Upgrade: 16. The +2 Energy lands only when you've discarded this turn. |
| Unload | `dmg:14:ranged; discard:all:non_attack` | `Rare Attack` cost 1, `Projectile, Medium, spread=4` — a 4-bolt fan in action. Upgrade: 18. |
| Sever Soul | `exhaust:all:non_attack; dmg:16:melee` | `Uncommon Attack` cost 2, `Swing, Small`. Upgrade: 22. The sweep resolves BEFORE the hit. |
| Searing Blow | `dmg:12:melee; sequential_upgrade:3` | `Uncommon Attack` cost 2, `Swing, Medium`, Element `Fire`. Infinitely upgradable — see the Sequential upgrades section. |

### X-cost cards (Whirlwind / Skewer)

Put a literal `X` in the Cost column (`cost = -1` in the `.tres`) and write the
repeat as `dmg:NxX`. Playing the card spends **all remaining energy**, and each
`hits_from: "energy"` dmg line resolves once per point spent:

- **Deckbuilder** — X = the energy pool at play time; the pool drops to 0.
  Playing at 0 energy is legal and swings zero times.
- **Strategy** — same rule against the tactical energy pool.
- **Action** — energy is Haste time there, so X = 1 + the remaining Haste
  seconds, and the cast consumes the Haste window. Without Haste up the card
  still swings once; chain it after a `gain_energy` card for the big X.

The upgrade form just bumps the per-hit value (`dmg:8xX`). Cooldown-wise the
action/strategy formula already treats X-cost as cost 1
(see `AbilityCooldownConfig`).

### Scaling counters (`per=COUNTER`) — Finisher

`dmg:VALUE:TYPE:per=COUNTER` deals `VALUE ×` a live combat counter. The flat
value becomes the per-unit amount (`value_mult`) and the counter names the
dynamic source (`value_from`); `EffectSystem._dynamic_count` resolves it in
deckbuilder/strategy and `ActionCombat._resolve_dmg_value` in action. It's one
hit whose *size* scales — Power / Weak / Vulnerable still layer on the total,
same as any dmg.

Counters available today (maintained by `GameState.incremental_*`, bumped by
`ItemTriggers.fire` and reset on the turn boundary in every mode):

| Counter | Meaning |
|---|---|
| `attacks_this_turn` | Attack cards played in the current turn (deckbuilder/strategy) or turn-tick window (action). |
| `attacks_total` | Attacks played this run. |
| `turns` | Turn-tick pulses this combat. |
| `hp_losses` | Times the player lost HP this combat — each HP-loss instance (enemy hit, DoT tick, self-damage card), whatever the size. Blood for Blood's `cost_reduce` counter. |
| `discards_this_turn` | Cards discarded by effects in the current turn window (the end-of-turn hand sweep doesn't count). In action each translated discard counts — a collapsed temp slot, a base-cooldown penalty, or a discard_hand sweep. Eviscerate's `cost_reduce` counter. |

`attacks_this_turn` is bumped on each attack's `card_played`, which fires
**before** the played card's own effects. A scaling attack does **not** count
its own play: the resolver strips one attack's worth back off when the card
carrying the dmg is itself an Attack (only Attacks bump the counter). So
Finisher scales off the attacks played *before* it — a solo Finisher with no
prior attacks this turn deals **0**.

Worked example — Finisher — `Uncommon Attack` cost 1:
```
Description:  Deal 6 Dmg Melee for each Attack played this turn.
Effects:      dmg:6:melee:per=attacks_this_turn
Upgraded Eff: dmg:8:melee:per=attacks_this_turn
Attack:       Poke, Medium
Tags:         silent, offense, scaling
```

In action the counter is the per-turn-tick attack window (default 10s, see
`ActionTranslation.turn_tick_secs`), so Finisher rewards a fast flurry of casts
inside one window rather than a discrete turn.

### Repeating an inflict (`times=N`) + random targeting

`inflict:STATUS:STACKS:times=N` applies the whole inflict N times (stored as
`hits: N`, mirroring dmg's `xN`). Pair it with the **`Indiscriminate` keyword**
(Keywords column) to re-roll a random enemy for each application —
`inflict:poison:3:times=3` + `Keywords: Indiscriminate` is Bouncing Flask: 3
Poison to a random foe, three times. The keyword (not an inline token) is what
makes the play UI skip the target picker, matching Blood Magic. In action combat
pair it with `Attack: Bounce` for the hopping-orb delivery.

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
| Gain 2 Power (temporary) | `gain:power:2:temp` | `status_temp`, `status: power`, `target: self` |
| Gain X Next Turn Draw | `gain:next_turn_draw:X` | `status`, `stacks_from: "energy"`, `target: self` |
| Inflict 2 Vulnerable | `inflict:vulnerable:2` | `status`, `status: vulnerable`, `target: enemy` |
| Inflict 1 Weak (Cleave) | `inflict:weak:1:cleave` | `status`, `status: weak`, `target: all_enemies` |

### X-value gains (`gain:<status>:X[+N]`) — Doppelganger

A literal `X` in a self `gain:`'s value slot makes the stack count the energy
spent on the play — the status mirror of dmg's `NxX`. Pair it with Cost `X`
(`cost = -1`): playing the card spends all remaining energy and banks that
many stacks. `X+1` (Doppelganger's upgrade) adds a flat bonus on top, stored
as `stacks_bonus`, so Doppelganger+ on an empty pool still banks 1.

Resolution mirrors the X-cost dmg path: deckbuilder/strategy thread the spent
energy through ctx as `x_value` (EffectSystem `_h_status`); action resolves
X = 1 + the remaining Haste seconds ONCE per cast (consuming the window), so
two X gains on the same card read the same X.

### Temporary buffs (`gain:...:temp`) — Flex

Append `temp` (or `temporary`) to a self `gain:` and the buff becomes
**temporary**: applied now, then shed at the next turn boundary. It's stored
as the `status_temp` effect type, whose handler
(`EffectSystem._h_status_temp`) applies the stacks like a normal status *and*
records the exact amount in `GameState.temp_status_stacks`. `ItemTriggers`
strips precisely that many stacks at `turn_started` (deckbuilder) / `turn_tick`
(action, strategy) — so any *permanent* stacks of the same status the player
already had are left untouched (the same machinery Prayer Beads' "+Brace until
end of turn" rides). All three modes: deckbuilder and strategy route the effect
through `EffectSystem.apply` for free; action's card-resolution loops handle
`status_temp` alongside `status` and call `_record_temp_status`.

Worked example — Flex — `Common Skill` cost 0:
```
Description:  Gain 2 Power. At the end of your turn, lose 2 Power.
Effects:      gain:power:2:temp
Upgraded Eff: gain:power:4:temp
Range/Attack: N/A
Tags:         ironclad, offense, scaling
```

Only self-targeted `gain:` produces `status_temp`; `temp` on an enemy inflict is
ignored (an enemy debuff decays on its own timer already).

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
  upgrade state) or any id from `data/cards/`. A trailing `+`
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

### Random conjures (White Noise / Infernal Blade / Distraction)

`conjure_random:TYPE:DESTINATION[:COUNT][:free]` mints cards the deck
doesn't contain — a random Power / Attack / Skill rolled at play time.

- **The pool is the chosen deck's pool.** Picks come from
  `Data.conjure_card_pool(TYPE)`: the reward pool scoped by
  `GameState.deck_reward_tag()` (the deck picked on the New Run screen),
  narrowed to TYPE. Ironclad deck → Ironclad + hero cards only; the
  Random deck → the whole catalog. Starters, weapons, and
  Status/Curse/Training junk are never minted.
- **`free` = costs 0 this turn.** Deckbuilder/strategy set
  `temp_cost_override = 0` on the minted CardInstance (the Mummified
  Hand slot); the override clears when the card leaves hand (played,
  discarded, exhausted, or end of turn), so an unplayed free card is
  full price if it ever comes back.
- **Action opens a new slot.** A `hand` mint appends a NEW one-shot
  auto-slot armed with the rolled card (`_conjure_into_hand`); `free`
  arms that slot at the 0-cost cooldown (rarity modifier only), the
  action translation of "play it for free this turn". The slot fires
  once and disappears.
- Each scene rolls on its own RNG via `conjure_random_card(...)`;
  the EffectSystem handler only routes.

Worked example — White Noise — `Uncommon Skill` cost 1 (0 upgraded):
```
Description:  Conjure 1 Random Power in Hand. You can play it for free this turn. Exhaust.
Effects:      conjure_random:power:hand:free
↑ Cost:       0
Keywords:     Exhaust
Tags:         defect, draw, random
```

Infernal Blade (`conjure_random:attack:hand:free`, ironclad) and
Distraction (`conjure_random:skill:hand:free`, silent) are the same
card aimed at the other two types.

### Status cards (Wound / Dazed / Slimed)

The cards a conjure *targets* are ordinary `Type: Status` rows in
`cardsnew` — junk shuffled into the deck, not `statusesnew` entries.
Author them like any other card:

| Card | Cost | Keywords | Effects | Notes |
|---|---|---|---|---|
| Wound | `No` | — | `none` | `Cost: No` sets `unplayable`. Pure dead weight. |
| Dazed | `No` | `Ethereal` | `none` | Unplayable **and** Ethereal (exhausts if still in hand at end of turn). |
| Slimed | `1` | `Exhaust` | `draw:1` | The playable one — pay 1 to cycle it out. |

`Cost: No` is the shorthand that flags a card `unplayable` without an
explicit keyword (curses use it too). Status cards are `can_upgrade =
false` automatically (no `↑` columns), so a conjured `+` suffix on them is
silently dropped.

## Picker modal (Discard / Exhaust / Upgrade / Topdeck / Recall)

`CardPickerModal` is the shared mid-cast modal that opens whenever a
card asks the player to choose from a pile. One reusable widget
backs every "choose N from a set" effect: Acrobatics' discard,
Armaments' upgrade, Warcry's topdeck, future Exhume / Headbutt /
Wraith Form picks, etc. Deckbuilder **and Strategy** — the tactical
grid runs the same pile model and opens the same modal. Action
auto-picks instead (its "hand" is the live auto-slot bar, so there's
nothing for the player to browse mid-fight).

**Default is player-choice.** Any verb that picks cards opens the
picker by default. Append `:random` to the DSL line to skip the
modal and let the engine roll instead. The convention is "if the
sheet doesn't say random, the player picks":

| DSL | Behavior |
|---|---|
| `discard:1` | Player picks 1 from hand to discard (Acrobatics). |
| `discard:1:random` | Engine picks 1 from hand to discard (All-Out Attack). |
| `discard:all` | Whole hand discards silently (Storm of Steel). No picker. |
| `exhaust:2` | Player picks 2 from hand to exhaust. |
| `topdeck:1` | Player picks 1 from hand to put on top of the draw pile (Warcry). |
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

### Warcry — `Common Skill` cost 0
```
Description:  Draw 1 Card. Put a Card from your Hand on the top of the Draw Pile. Exhaust.
Effects:      draw:1; topdeck:1
Upgraded Eff: draw:2; topdeck:1
Range/Attack: N/A
Keywords:     Exhaust
Tags:         ironclad, draw
```

`topdeck:1` opens the picker in deckbuilder/strategy; action auto-picks a
temp auto-slot's card back onto the top of the auto deck. The draw resolves
first, so the just-drawn card is a legal pick.

### Whirlwind — `Uncommon Attack` cost X
```
Description:  Deal 5xX Dmg Melee Cleave.
Effects:      dmg:5xX:melee:cleave
Upgraded Eff: dmg:8xX:melee:cleave
Attack:       Swing, Large
Tags:         ironclad, offense, aoe
```

`Swing, Large` is the full all-around ring (the spelling that replaced
`Swing, arc=360`). `5xX` + Cost `X` is the X-cost pattern — see the X-cost
section above. Skewer is the single-target sibling (`dmg:7xX:melee`,
`Poke, Large`).

### Storm of Steel — `Rare Skill` cost 1
```
Description:  Discard your Hand, then Conjure X Shivs where X was the amount of cards that were Discarded.
Effects:      discard:all; conjure:shiv:hand:count=discarded
Upgraded Eff: discard:all; conjure:shiv+:hand:count=discarded
Tags:         silent, discard, offense
```

Order matters: `discard:all` records `last_discard_count` on the scene, then
the conjure's `count=discarded` reads it back. The upgrade mints upgraded
Shivs via the `+` suffix.

### Sword Boomerang — `Common Attack` cost 1
```
Description:  Deal 3 Dmg Ranged to a Random target. Repeat 2 times.
Effects:      dmg:3x3:ranged
Upgraded Eff: dmg:3x4:ranged
Attack:       Boomerang
Keywords:     Indiscriminate
Tags:         ironclad, offense
```

The `boomerang` archetype: in action a spinning sword flies to 3 (4 upgraded)
random enemies in sequence — the next target is picked on arrival at the
current one — then returns to the player. The blade's hitbox is live for the
whole flight, so enemies it merely passes through get clipped too and it can
land more than its listed hits. In strategy/deckbuilder the Indiscriminate
keyword re-rolls a random enemy per hit instead.

### Reaper — `Rare Attack` cost 2
```
Description:  Deal 4 Dmg Melee Cleave Lifesteal. Exhaust.
Effects:      dmg:4:melee:cleave
Attack:       Swing, Large
Keywords:     Exhaust, Lifesteal
Tags:         ironclad, offense, health, exhaust
```

Lifesteal lives in the Keywords column, not the DSL — the addon pipeline
stamps `lifesteal: true` onto the dmg effect and every mode's damage path
heals the attacker for the unblocked damage dealt.

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

**Negative boosts (Glass Knife).** `VALUE` may be negative — a card that
boosts its own id downward decays itself for the combat. The boosted
value floors at 0 (`Stats.apply_card_boosts`), so a decayed-out card
hits for 0 base rather than eating into the Power bonus. The in-hand
display folds live combat boosts into the shown Dmg/Block number
(`CardScaling` reads the scene's `card_boosts`), so the number visibly
steps down (in red) each play.

Worked example — Glass Knife — `Rare Attack` cost 1:
```
Description:  Deal 8x2 Dmg Ranged. Decrease the Dmg of this Card by 2 this combat.
Effects:      dmg:8x2:ranged; boost_cards:id=glass_knife:dmg:-2
Upgraded Eff: dmg:12x2:ranged; boost_cards:id=glass_knife:dmg:-2
Attack:       Projectile, Medium
Tags:         silent, offense
```

Order matters: the dmg resolves BEFORE the self-boost registers, so the
first play lands at full value and each later play is 2 lower (per hit).
The boost matches by id, so every copy of Glass Knife shares the decay,
and it resets when combat ends.

**Mode coverage:** all three modes consume boosts now — the deckbuilder
folds them per effect in `_apply_card_boosts`, action in
`_resolve_addon_effect`, strategy in `_apply_card_or_spell_effects`
(all through `Stats.apply_card_boosts`).

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
| `unblocked_attack` | The player's melee/ranged hit deals post-block HP loss. The victim is the trigger's target, so an inner `inflict` lands on it (Envenom). Fires in all three modes; reactions (`no_reaction`) never re-fire it. |
| `status_drawn` | A Status-type card lands in hand (Evolve). Deckbuilder + strategy. |
| `status_or_curse_drawn` | A Status- or Curse-type card lands in hand (Fire Breathing). Deckbuilder + strategy. |

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

**Mode coverage:** all three modes register triggers (deckbuilder and
strategy through EffectSystem's `trigger` handler, action through
`_apply_utility_effects`). Each mode fires the events it has an analog
for — action has no card draws or exhausts, so `status_drawn` /
`card_exhausted` triggers sit dormant there while `unblocked_attack`,
`turn_started` (fired at each in-combat turn tick — Wraith Form's
Defense erosion), and `turn_ended`-retain still work.

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
vulnerable, weak, frail, burn, poison, regeneration, dodge, blind,
confused, stun, no_draw, intangible, double_damage
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
  fires every `ActionTranslation.turn_tick_secs` (10s, edit
  `data/action_translation.tres`) and decays every living actor. The
  tick is independent of Haste / Slow on purpose — debuff duration
  shouldn't accelerate with tempo. That resource also centralises the
  other turn-based → Action mappings (energy → Haste, draw → auto-cast
  slots, turns → rooms).

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

### Intangible (Wraith Form)

`Intangible` clamps **each instance** of damage / HP loss on the carrier
to 1. The clamp lives in `Stats.resolve_damage` — after every outgoing
and incoming modifier (Power / Weak / Vulnerable / crit), BEFORE block
soaks it (the legacy rule: a blocked clamped hit still costs 1 Block) —
and in each scene's `apply_dot` via `Stats.intangible_clamp`, so attack
hits, Burn/Poison ticks, and curse HP drains all land as 1 in all three
modes. Amounts of 0 stay 0 — Intangible never raises a miss to 1. Decays
1 per turn (turn tick in action) like the other timed statuses.

The deckbuilder's enemy **intent preview** clamps too
(`_predict_intent_damage`): while the player is Intangible an attack
intent telegraphs `1` (or `1xN` for multi-hit) — the StS behaviour —
and since `_refresh_ui` re-predicts, the number drops the moment Wraith
Form is played and recovers as the stacks decay.

Worked example — Wraith Form — `Rare Power` cost 3:
```
Description:  Gain 2 Intangible. At the start of your turn, lose 1 Defense.
Effects:      gain:intangible:2; on_turn_started:gain:defense:-1
Upgraded Eff: gain:intangible:3; on_turn_started:gain:defense:-1
Range/Attack: N/A
Tags:         silent, defense
```

Two pieces of note:

- **Negative `gain:`** — `gain:defense:-1` parses to a `status` effect
  with `stacks: -1`; `add_status` clamps at 0 and erases, so the erosion
  eats an existing Defense buff and then no-ops (matching the legacy
  build — Defense never goes negative).
- **`on_turn_started` in action** — the action turn tick now fires
  `turn_started` power triggers while enemies are up, so the erosion
  paces one per tick there (the same translation the banked next-turn
  statuses use).

### Banked-turn statuses (Next Turn Energy / Next Turn Draw) + No Draw

The "next turn" family banks value now and pays it out at the start of your
next turn, consuming every stack ("Lose all when triggered" — deliberately
NOT in `DECAY_STATUSES`). The payout primitive is `Stats.consume_status`
(read + clear in one step), called once per turn boundary by each mode:

- **Deckbuilder** — `_start_player_turn` pours `next_turn_energy` onto the
  refreshed pool (after Ice Cream's carry-over) and adds `next_turn_draw` to
  the turn-start hand count.
- **Strategy** — same two payouts at the player unit's turn start
  (`_on_unit_turn_started`).
- **Action** — the stacks pay out at the next turn tick while enemies are up
  (`_pay_next_turn_statuses`), translated like the instant verbs: energy
  becomes a Haste window, draws open temporary auto-cast slots. Banked stacks
  hold in an empty room.

`no_draw` (Battle Trance) suppresses EVERY further `draw_cards` call this
turn — card-effect draws, Evolve triggers, all of it — and steps down at the
turn boundary like any decay status, so the next turn-start hand is
unaffected. Effect order on the card matters: `draw:3; gain:no_draw:1` draws
first, then locks the door.

Worked examples:

| Card | Effects DSL | Notes |
|---|---|---|
| Battle Trance | `draw:3; gain:no_draw:1` | `Uncommon Skill` cost 0. Upgrade: `draw:4; gain:no_draw:1`. |
| Flying Knee | `dmg:8:melee; gain:next_turn_energy:1` | `Common Attack` cost 1, `Poke, Medium`. |
| Predator | `dmg:15:melee; gain:next_turn_draw:2` | `Common Attack` cost 2, `Poke, Medium`. |
| Doppelganger | `gain:next_turn_draw:X; gain:next_turn_energy:X` | `Rare Skill` cost X, Exhaust. Upgrade: `X+1` forms. |

### Powers (Barricade / Envenom / Evolve / Feel No Pain / Fire Breathing / Well-Laid Plans)

Powers are authored as ordinary parsable Effects DSL — no opaque
`gain:<power_name>` indirection. Each one is either an
`on_<EVENT>:<inner>` trigger (see the Triggers section) or a bare
structural verb:

| Power | Effects DSL | Meaning |
|---|---|---|
| Barricade | `keep_block` | Sets `actor.keep_block`; every turn-boundary `block = 0` site checks `Stats.keeps_block(actor)` (action instead stops the block pool's real-time fade — hits still soak). |
| Envenom | `on_unblocked_attack:inflict:poison:1` | Fired from each mode's damage path when the player's melee/ranged hit deals post-block HP loss; the victim is the trigger's target. Reactions (`no_reaction`) never re-fire it. |
| Evolve | `on_status_drawn:draw:1` | Fired from `draw_cards` when the drawn card is a Status card. |
| Feel No Pain | `on_card_exhausted:gain:block:3` | The pre-existing exhaust event — no bespoke code at all. |
| Fire Breathing | `on_status_or_curse_drawn:dmg:6:magic:cleave` | The inner cleave fans out over `living_enemies()` at fire time. |
| Well-Laid Plans | `on_turn_ended:retain:1` | `retain` is resolved by the scenes' end-turn intercept BEFORE the hand discards (`Stats.retain_total(power_triggers)` → the `CardPickerModal` in `up_to` mode; picks get `CardInstance.retain_this_turn`). Action: each turn tick, a random auto-slot card still in cooldown finishes its cooldown, once per retain point. The generic `turn_ended` pass deliberately no-ops retain (`EffectSystem._h_retain`). |

**Playing a Power is not an exhaust.** The card is simply used — it
leaves hand into no pile and fires no `card_exhausted` (so Feel No
Pain stays quiet). Cards with an explicit `Exhaust` keyword still
exhaust normally.

**Badges.** A resolving Power records itself on the actor
(`Stats.register_power` → `actor.powers`, count rises when the same
power is played again), and every mode's badge strip renders those
entries next to the statuses: icon from
`images/powericons/<Img>Power.png` (same `Img` as the card art,
resolved by `Stats.power_badge_icon`), hover text = the card's own
description (`Stats.power_tooltip`). Powers have no `statusesnew`
row and no ReferenceCatalog entry — the card is the single source
of truth.

**Card text says what the power does**, not "Gain Barricade." — the
wording came from the legacy `statuses` sheet and lives in the
`cardsnew` Description, so the card and the badge tooltip read the
same.

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
  `void`, `burn` — match the file name in `data/cards/`.

## Future work

Tracked here so the design intent doesn't get lost between commits.

### Power icons in combat HUDs

**Landed** — see "Power statuses" above. The open questions resolved
the simple way: a Power's whole effect is `gain:<status>:N`, so the
existing status badge strip *is* the power strip in all three modes
(one icon + stack count, hover tooltip from the `statusesnew`
description). Icon art goes to `images/powericons/<ImgName>Power.png`
and `Stats.status_icon` finds it by fallback; no `power_icon` field
on `CardData` was needed. Powers with bespoke trigger logic that
DON'T sit on a status (After Image's `on_card_played`, Accuracy's
`boost_cards`) still have no badge — converting them to power
statuses is the remaining follow-up.

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

Shipped. All three modes register boosts (`add_card_boost`) and fold
them through the shared `Stats.apply_card_boosts` — deckbuilder in
`_apply_card_boosts`, action in `_resolve_addon_effect`, strategy in
`_apply_card_or_spell_effects`. Negative self-boosts (Glass Knife)
ride the same path; see the Card boosts section.

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
