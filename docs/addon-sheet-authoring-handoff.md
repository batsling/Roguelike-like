# Next session: data-drive addons

**Goal (decided with the user):** make addon *behavior* sheet-authored via a
small per-mode effect DSL, the way items/cards are now generated from
`tools/Roguelikes.xlsx`. Today the addon **catalog** is already generated from
the `addonsnew` sheet; only the **runtime behavior** is still hardcoded.

## ⚠️ Read first — the hard constraint
There is **no Godot runtime in this environment** and **no generated artifact to
diff** for addons (behavior is live GDScript, not a `.tres`). So unlike items,
this can't be parity-proven offline. Approach: keep behavior **bit-identical**,
parity-check the new generic dispatcher against the current `match`-arms in pure
Python/logic terms, and leave final in-game verification to the user. Move in
small, reversible steps and confirm the DSL design before ripping out code.

## Current state
- **Catalog (already sheet-driven):** `tools/import-reference-godot.py` reads the
  `addonsnew` sheet (cols: Name, Deckbuilder, Action, Strategy, Has Value, Can Be
  Attatched To, Forms) → `scripts/data/ReferenceCatalog.gd` (`const ADDONS`).
- **Behavior (hardcoded, to be data-driven):**
  - `scripts/autoload/Stats.gd` → `apply_addons_to_effect`, `addon_damage_bonus`,
    `_fishing_weight_bonus`, `_wealth_bonus` (handles `cleave`, `indiscriminate`,
    `fishing_weight`, `wealth`).
  - `scripts/runtime/CardMods.gd` + `scripts/autoload/TriggerBus.gd` and the three
    combat scenes (`scripts/deckbuilder/DeckbuilderCombat.gd`,
    `scripts/action/ActionCombat.gd`, `scripts/strategy/combat/BattleView.gd`)
    handle `replay` and `infuse`.
  - Card `.tres` bool flags (NOT addons): `exhaust`, `ethereal`, `innate`,
    `unplayable`, `eternal` — parsed by `tools/generate_card_tres.py`
    `parse_keywords` / `FLAG_KEYWORDS`. `melee`/`ranged` are damage types.

## The 13 addons (addonsnew) and where they live now
| Addon | Has Value | Current home |
| --- | --- | --- |
| Cleave | No | Stats.apply_addons_to_effect (target → all_enemies) |
| Indiscriminate | No | Stats.apply_addons_to_effect (random targets flag) |
| Wealth | No | Stats._wealth_bonus (+1 dmg / 10 gold) |
| Fishing Weight | No | Stats._fishing_weight_bonus (fish tally; returns 0 today) |
| Infuse | Yes | 3 combat scenes (kill → gain max HP) |
| Replay | Yes | CardMods + TriggerBus + 3 combat scenes (re-resolve N×) |
| Melee / Ranged | No | damage_type tokens (card effects) |
| Exhaust / Ethereal / Innate / Unplayable / Eternal | No | CardData bool flags |

So only **6** addons carry real runtime logic (cleave, indiscriminate, wealth,
fishing_weight, infuse, replay); the rest are flags/damage-types already handled
structurally.

## Suggested plan
1. **Survey** every code arm above; write down the exact behavior of each as a
   spec (inputs it reads, what it mutates). This is the source of truth the DSL
   must reproduce.
2. **Design DSL columns** in `addonsnew` — likely one structured cell per mode
   (Deckbuilder/Action/Strategy already exist as prose; add machine-readable
   siblings or repurpose). Cover: damage bonus expressions (`+gold/10`,
   `+fish_tally`), target rewrites (`target=all_enemies`), flags (`indiscriminate`,
   `infuse`, `replay:N`). Confirm the column layout with the user first.
3. **Generic dispatcher:** extend `ReferenceCatalog`/`import-reference-godot.py`
   to emit the effect spec, and add a small interpreter (e.g. `AddonSystem.gd` or
   inside Stats) that reads it, replacing the `match` arms one at a time.
4. **Parity-check** the dispatcher against the old arms for every addon (same
   inputs → same output), in logic terms. Keep the old code until the user has
   verified in-game.
5. Regenerate the catalog, restore any `tools/__pycache__` churn, commit, push.

## Open questions for the user
- Which addon behaviors are worth data-driving vs. leaving as flags? (The 5 bool
  flags + melee/ranged are arguably already "done.")
- DSL column shape: one combined cell, or per-mode cells? How to express
  value-bearing addons (Infuse X, Replay N) and gold/fish-scaled bonuses?
- `fishing_weight` returns 0 today (fish loot doesn't exist yet) — keep as a
  no-op the DSL just declares, or wait until fish tallies land?

## Kickoff prompt to paste next session
> Continue the sheet-authoring work on branch `claude/adoring-sagan-c0dfzd`.
> Items are done (sheet-authored via `tools/generate_item_tres.py`). Now do
> **addons**: read `docs/addon-sheet-authoring-handoff.md`, survey the addon code
> arms it lists, and propose a DSL-column design for `addonsnew` before changing
> code. Remember there's no Godot runtime here, so keep behavior bit-identical
> and parity-check the dispatcher; I'll verify in-game.
