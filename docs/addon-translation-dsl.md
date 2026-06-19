# Addon translation DSL (design)

**Status:** design only. The four effect-modifier addons (Cleave, Indiscriminate,
Wealth, Fishing Weight) are already data-driven (see
`addon-sheet-authoring-handoff.md`). This doc specifies the *target* shape that
would make **every** `addonsnew` row work in all three combat sections
(Deckbuilder / Action / Strategy) without hand-authoring per-addon code.

## The idea (decided with the user)
The `addonsnew` sheet should tell the engine **what each addon translates into,
per mode**. This is the same model the card **Effects** DSL already uses — the
sheet writes verb tokens (`dmg 6`, `gain:block 5`) and `EffectSystem` has a
handler registry (`EffectSystem.gd` `register("exhaust", _h_exhaust)`) — widened
to (a) be per-mode and (b) cover the card-lifecycle axis, not just effects.

### Division of labor (the hard boundary)
- **Sheet (data):** per addon, per mode → a verb token with arguments. "Translate
  into THIS." Blank inherits the mode-agnostic default.
- **Engine (code):** a **closed registry of verb handlers**. Each verb is
  implemented once. The *only* thing that needs new code is a genuinely new verb.

So "no manual authoring" holds for any addon expressible in the existing verb
vocabulary. A new *kind* of behavior still costs one handler — but every addon
reusing it afterward is pure sheet authoring.

Magnitudes stay on the card, not in `addonsnew`: Infuse's `X` rides the card
effect (`infuse=N` → `eff["infuse"]`), Replay's `N` rides the addon token on the
card (`replay:N`). The `addonsnew` row supplies the **shape**; the card supplies
the **number**.

## Column schema for `addonsnew`
The importer (`tools/import-reference-godot.py`) reads columns **by header name**,
so column order/position does not matter — only the exact header text. Keep the
existing prose columns (the Collection screen's Reference tab renders them).

### Live today (the engine consumes these)
| Header | Meaning | Example |
| --- | --- | --- |
| `Key` | runtime slug the engine matches (form `generate_card_tres.slugify` bakes into `CardData.addons`); blank → `slugify(Name)` | `fishing_weight` |
| `Hook` | dispatch family / phase | `effect_dmg_bonus` |
| `Expr` | mode-agnostic default verb expression | `gold/10` |

### Target additions (forward — author now, engine consumes when verbs land)
| Header | Meaning |
| --- | --- |
| `DB Verb` | Deckbuilder verb override (blank → use `Expr`) |
| `Action Verb` | Action verb override (blank → use `Expr`) |
| `Strategy Verb` | Strategy verb override (blank → use `Expr`) |

Mode-agnostic addons fill only `Expr` and leave the three Verb cells blank.
Divergent addons fill only the modes that differ. The loader rule is **"use the
mode's Verb cell if present, else `Expr`."**

## Verb grammar
```
expression := clause ( ";" clause )*
clause     := [ trigger ":" ] [ condition ":" ] action
trigger    := on_play | eot_in_hand | on_combat_start | on_kill | …
condition  := chance(<pct>) | …
action     := verb | verb "(" args ")"
```
Arguments are a closed vocabulary (no general arithmetic), so each maps 1:1 to a
handler. `X` / `N` in an arg refer to the card-supplied magnitude.

## Verb registry (the bounded code surface)
| Phase / family (`Hook`) | Verbs | Per-mode contract | Status |
| --- | --- | --- | --- |
| `effect_dmg_bonus` | `add_value(gold/10\|fish)` | flat +value on the dmg effect (mode-agnostic) | ✅ built |
| `effect_retarget` | `retarget(from,to)` | rewrite effect target when it equals `from`; each mode's resolver fans `to` its own way | ✅ built |
| `effect_flag` | `set_flag(name)` | set `effect[name]=true` (e.g. indiscriminate) | ✅ built |
| `on_kill` | `gain_max_hp(X)`, `chance(pct)` | DB/ST: always; Action: gate on `chance(10)` | ⚠️ hooks exist, not generic |
| `card_replay` | `replay(N)` | re-resolve the card N extra times | ✅ built (per-scene loop) |
| `lifecycle` | `to_pile(p)`, `to_hand`, `auto_play`, `free_play(n)`, `uses_per_combat(n)`, `cooldown_mult(x)`, `deactivate_if_idle`, `not_playable`, `requires_equipped(n)`, `removable(bool)` | see per-addon table below | ❌ deckbuilder-only today |

### Lifecycle per-addon, per-mode (verbs the cells would carry)
| Addon | Deckbuilder | Action | Strategy |
| --- | --- | --- | --- |
| Exhaust | `on_play: to_pile(exhaust)` ✅ | `uses_per_combat(1)` ✅ | — (same as Deckbuilder) |
| Ethereal | `eot_in_hand: to_pile(exhaust)` ✅ | `cooldown_mult(2)` ✅ | — (same as Deckbuilder) |
| Innate | `on_combat_start: to_hand` ✅ | `on_combat_start: auto_play` ✅ | — (same as Deckbuilder) |
| Unplayable | `not_playable` ✅ | `cooldown_mult(2)` ✅ | — (same as Deckbuilder) |
| Eternal | `removable(false)` ✅ | `removable(false)` ✅ | `removable(false)` ✅ |

✅ = the verb maps to code that exists today. `cooldown_mult` rides the existing
`AbilityCooldownConfig` / `ActionTranslation` plumbing, so it's a knob on a
system you already have rather than a new one. Eternal is mode-agnostic
(`Expr = removable(false)`), so it needs no Verb cells.

> **Strategy is now a grid deckbuilder.** When the tactical mode was converted
> to play like the deckbuilder (real hand / draw / discard / exhaust piles),
> these lifecycle addons stopped needing bespoke Strategy verbs: Strategy reads
> the same `CardData` flags (`exhaust` / `ethereal` / `innate` / `unplayable` /
> `retain` / `sly` / `destroy`) the deckbuilder does, so they behave identically
> in both modes. The old Strategy verbs (`uses_per_combat`, `deactivate_if_idle`,
> `free_play`, `requires_equipped`) belonged to the retired loadout/per-run-uses
> model and have been removed from `AddonSystem.gd`; their `addonsnew` Strategy
> Verb cells are now blank and the Strategy prose column mirrors the Deckbuilder
> column. `AddonSystem` still drives **Action** behavior (`uses_per_combat`,
> `cooldown_mult`, `auto_play`).

## What stays in the TranslationResource (do NOT move to the sheet)
Global *feel* tunables — `haste_multiplier`, `turn_tick_secs`, base cooldown
derivation in `AbilityCooldownConfig` — stay in `ActionTranslation` /
`StrategyTranslation`. The sheet declares the per-addon override
(`cooldown_mult(2)`); the translator owns the global feel. Two different axes.

## Build-time validation (vocabulary lint)
Because verbs now live in the sheet, the generator must reject unknown verbs at
build time (a typo would otherwise silently no-op in-game). This is the same
safety role `tools/test_addon_dispatch.py` plays for the four live arms:
- The importer already fails if `Key`/`Hook`/`Expr` columns go missing.
- Extend it to parse each verb token and error on any verb not in the registry.

## Implementation status
The generic interpreter and the lifecycle verbs are now wired
(`scripts/runtime/AddonSystem.gd` + per-scene hooks). **Unverified in-engine**
(no Godot runtime in this environment) — verify in-game. Each hook is guarded to
no-op when a card carries none of these addons, so the 9 previously-working
addons and normal combat are unaffected.

| Verb | Mode | Where wired | Status |
| --- | --- | --- | --- |
| `cooldown_mult` (Ethereal, Unplayable) | Action | `ActionCombat._cooldown_for` | ✅ wired |
| `uses_per_combat` (Exhaust) | Action | auto-slot rotation (`_addon_uses`) | ✅ wired |
| `auto_play` (Innate) | Action | `_auto_play_innate_addons` at room start | ✅ wired |

The Strategy verbs that used to live here (`uses_per_combat`, `free_play`,
`deactivate_if_idle`, `requires_equipped`) were **removed** when Strategy became
a grid deckbuilder. Strategy now reads the deckbuilder `CardData` flags directly
(see the note under the lifecycle table above), so Exhaust / Ethereal / Innate /
Unplayable / Retain / Sly behave exactly as in the deckbuilder. `AddonSystem`
drives Action only.

Deckbuilder keeps its existing CardData-flag code for all of these — it already
worked — so `AddonSystem` powers Action/Strategy only.

## New addons (Sly / Lifesteal / Retain / Destroy / Vorpal)
Five addons added to `addonsnew`. The first four are pure data/flag plumbing
(no new verb vocabulary); Vorpal adds one declarative hook. All are wired across
all three modes where the mechanic exists. **Unverified in-engine.**

| Addon | Key / Hook / Expr | Wiring | Modes |
| --- | --- | --- | --- |
| **Lifesteal** | `lifesteal` / `effect_flag` / `lifesteal` | `apply_addons_to_effect` stamps `lifesteal` on the dmg effect; each scene's damage path heals the attacker for the unblocked HP dealt. | DB / Action / Strategy |
| **Retain** | `retain` / `structural` / — | Existing `CardData.retain` flag (kept in hand at end of turn). Catalog entry only; behavior already lived in deckbuilder. | DB (no end-of-turn discard in Action/Strategy) |
| **Destroy** | `destroy` / `structural` / — | New `CardData.destroy` flag. On play/use the physical card is removed from the run deck (`GameState.destroy_card_instance` / `destroy_first_card_with_id`) instead of going to discard/exhaust. | DB / Action (retires from rotation) / Strategy |
| **Sly** | `sly` / `structural` / — | New `CardData.sly` flag. The card is playable normally AND additionally resolves its effects when it would be discarded WITHOUT being played (end of turn, a discard effect) — auto-targeting a random live enemy. The post-play discard is suppressed (`discard_card(..., from_play=true)`) so a normal play doesn't double-resolve. | DB only — Action/Strategy have no hand-discard concept |
| **Vorpal** | `vorpal` / `effect_vorpal` / — | Per-`CardInstance` roll (combat type = one of the three modes + 1-5 weight), persisted in saves. `Stats.vorpal_damage_bonus` adds `Stats.VORPAL_BONUS` (10) when the swing's mode and the target's `weight` both match. | DB / Action / Strategy |

Enemy `weight` (the Vorpal match key, 1-5) lives on `EnemyData.weight`,
`ActionEnemyData.weight`, and `BattleUnit.weight`; it's copied onto the runtime
actor (`CombatActor.weight` / `BattleUnit.weight`) at spawn so `Stats` reads it
uniformly. Action mode flattens the deck to `CardData`, so Vorpal's per-instance
roll is recovered via `GameState.vorpal_for_card_data` (first deck copy wins).

These four flag/slug addons need no new verb vocabulary — Retain/Destroy/Sly
mirror Eternal as plain `structural` flags, Lifesteal reuses `effect_flag`. The
only importer change is the declarative `effect_vorpal` hook (empty Expr).
