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
| Exhaust | `on_play: to_pile(exhaust)` ✅ | `uses_per_combat(1)` ❌ | `uses_per_combat(1)` ❌ |
| Ethereal | `eot_in_hand: to_pile(exhaust)` ✅ | `cooldown_mult(2)` ❌ | `deactivate_if_idle` ❌ |
| Innate | `on_combat_start: to_hand` ✅ | `on_combat_start: auto_play` ❌ | `on_combat_start: free_play(1)` ❌ |
| Unplayable | `not_playable` ✅ | `cooldown_mult(2)` ❌ | `requires_equipped(1)` ❌ |
| Eternal | `removable(false)` ✅ | `removable(false)` ✅ | `removable(false)` ✅ |

✅ = the verb maps to code that exists today; ❌ = behavior not implemented in
that mode yet. `cooldown_mult` rides the existing `AbilityCooldownConfig` /
`ActionTranslation` plumbing, so it's a knob on a system you already have rather
than a new one. Eternal is mode-agnostic (`Expr = removable(false)`), so it needs
no Verb cells.

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
| `uses_per_combat` (Exhaust) | Strategy | `GameState.max_card_uses` cap | ✅ wired |
| `free_play` (Innate) | Strategy | turn-1 `_free_ability_card` | ✅ wired |
| `deactivate_if_idle` (Ethereal) | Strategy | turn-end check + picker/pick gating | ✅ wired |
| `requires_equipped` (Unplayable) | Strategy | loadout-confirm validation (`_loadout_requirement_error`) | ✅ wired |

`requires_equipped` blocks "Start Battle" (with a loadout-screen message) until
the player slots the required number of Unplayable cards — only when they own
any. Unplayable cards pass through the loadout pool, so the rule is always
satisfiable.

Deckbuilder keeps its existing CardData-flag code for all of these — it already
worked — so `AddonSystem` powers Action/Strategy only.
