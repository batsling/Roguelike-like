# Enemy System Plan — Deckbuilder (Phase 1)

Status: **planning / not yet implemented.** This is the agreed design for adding
enemies to deckbuilder combat. Action and Strategy modes reuse the same data
later; this pass is deckbuilder-only because its combat is the simplest.

Goal: deckbuilder combats spawn a **weighted group of up to 3 enemies**, drawn
only from deckbuilder enemies, using the budget/tier "weight" system from the
old HTML build.

---

## 1. Reference: how the old HTML weight system worked

`legacy-web/js/exploration.js → preGenerateEnemiesForGame()`:

- **Difficulty tiers** unlock by progress: `gamesBeaten ≥ 8 → High`, `≥ 4 → Medium`,
  else `Low`. Pool = enemies whose `difficulty` tier ≤ current tier.
- **Type gate**: game type → enemy `Type`
  (`Action→Strength, Deckbuilding→Charisma, Strategy→Intelligence, Traditional→Dexterity`).
  Deckbuilder enemies are the `Charisma` rows (today: 12, all Slay the Spire).
- **Budget spawning** (the "weight" system): budget = `2` on the very first combat,
  else `Low=4 / Med=6 / High=9`. Loop: take enemies with `weight ≤ remaining`,
  roll a target weight `1..max`, prefer candidates at that weight, subtract the
  chosen enemy's `weight`. Stop at budget `0` or the enemy cap. `weight` is a
  **cost** — Louse (1) lets you stack several, Transient (9) eats the whole budget.

## 2. Current Godot state

- `data/enemies/*.tres` (6) are **hand-stubbed** — `weight`/`difficulty` don't match
  the spreadsheet. There is **no enemy import script** yet.
- `scripts/deckbuilder/GameMap.gd:286 _pick_enemy_for_combat()` picks **one** enemy
  uniformly at random (`weight > 0`). No budget, tier, or grouping. `Main.gd:213`
  duplicates this.
- `DeckbuilderCombat.enemies_to_spawn` is already an `Array` and
  `_build_enemy_views()` already loops it — **multi-enemy needs no combat-scene change.**
- `RunDifficulty` already mirrors the HTML tier ladder
  (`current_tier()` from `GameState.games_played`, `Tier.LOW/MEDIUM/HIGH/INSANE`).
  Note: Godot advances on games *played* every 3 (4 tiers); HTML used games *beaten*
  thresholds (4/8/12, 3 tiers). Reconcile by reusing `RunDifficulty` and mapping
  Low/Med/High(/Insane) → budget.

## 3. Effect model (shared with cards)

The card Effects DSL (`generate_card_tres.py`) compiles into the **same effect-dict
shape** the enemy `pattern` already uses:

```
card  "dmg:10:melee"  → {"type":"dmg","value":10,"target":"enemy"}
enemy move            → {"type":"dmg","value":11,"target":"player"}
```

Enemy moves reuse the identical verbs, defaulting `target` to `player`. One effect
compiler can serve both.

## 4. Excel format — single sheet, packed `Moves` column (chosen)

Keep the one-row-per-enemy `enemies` sheet (chosen over a move-per-row sheet because
some enemies have 10+ moves). Replace the bespoke `Pattern` text with a structured
`Moves` column. Columns:

```
Name | Type | Difficulty | Weight | Min HP | Max HP | Ability | Game | Location | Moves | File | Variant | Tag
```

### `Moves` grammar

- Moves separated by `;;`
- Fields within a move separated by `|`:  `<gate> @ <weight> | <description> | <effects>`
- Multiple effects within the effects field separated by `;` (single `;`, never `;;`)

Fields:
- **gate**: `t1` = first-turn-only (the forced opener; pairs with weight `0`),
  `any` = normal weighted move. (Room to add `t<N>`/`from<N>` later.)
- **weight**: integer relative weight for `pattern_mode = "random"` (0 = scripted/forced).
- **description**: intent text shown to the player (e.g. `Bellow (+3 Power, +6 Block)`).
- **effects**: card DSL (player-default target).

A "60% A / 40% B" turn is just two `any` rows with weights 60/40. This reconstructs
the existing `pattern` array 1:1.

### Example — Jaw Worm

```
t1 @ 0 | Chomp (11) | dmg:11
;; any @ 45 | Bellow (+3 Power, +6 Block) | gain:power:3; block:6
;; any @ 30 | Thrash (7 dmg, 6 Block) | dmg:7; block:6
;; any @ 25 | Chomp (11) | dmg:11
```

### Enemy effect verbs (player-default target)

| DSL                     | Effect dict                                                            |
|-------------------------|------------------------------------------------------------------------|
| `dmg:N`                 | `{type:dmg, value:N, target:player}` (melee default)                   |
| `dmg:N:ranged`          | ranged variant                                                         |
| `dmg:NxH`               | multi-hit (H hits)                                                     |
| `block:N`               | `{type:block, value:N, target:self}`                                   |
| `gain:<status>:N`       | `{type:status, status:<status>, stacks:N, target:self}` (power, …)     |
| `inflict:<status>:N`    | `{type:status, status:<status>, stacks:N, target:player}` (weak, vuln, frail, confused) |
| `add_card:<id>:N:<dest>`| inject status cards (Slimed → discard)                                 |

Extend verbs as enemies need them; keep parity with the card compiler.

### Abilities column

`Ability` keeps its keyword string (`Fading 4/Shifting`, `Curl Up Determined(3-7)`,
`Split 2 Acid Slime (M)`). Split on `/`, drop `N/A`, write to
`starting_abilities: PackedStringArray`. EffectSystem already parses these at load.

## 5. Build steps (when implementing)

1. **`tools/generate_enemy_tres.py`** (mirror `generate_card_tres.py`):
   - Read `enemies`; filter to deckbuilder enemies (`Type == "Charisma"`).
   - Parse `Moves` → `pattern` array; map `Difficulty` Low/Med/High/Boss → `0/1/2/3`;
     carry `weight`, `hp_min/max`, abilities, `source_game`, `tag`,
     `image = res://assets/enemies/<File>.png`, `pattern_mode = "random"`.
   - Default `glyph` (first letter) and `portrait_color` (by type/hash) unless columns added.
   - Wipe + regenerate deckbuilder `data/enemies/*.tres`; warn on unparseable
     effects / missing images.
2. **Spawn logic** — port `preGenerateEnemiesForGame()` into
   `GameMap.gd._pick_enemy_for_combat()` (and dedupe `Main.gd:213`):
   - Tier from `RunDifficulty.current_tier()`.
   - Pool = deckbuilder enemies, `weight > 0`, difficulty tier ≤ current.
   - Budget by tier (first combat = 2, then Low=4 / Med=6 / High=9).
   - Weighted-pick loop, **cap at 3 enemies**.
   - Return the list to `enemies_to_spawn` (already an Array).

## 6. Open items

- Reconcile games-played-÷3 (Godot) vs games-beaten thresholds (HTML) for the budget.
- Confirm the "first combat = budget 2" trigger has a Godot counter
  (`GameState.total_combats_completed` or similar) or drop it.
- Decide whether `pattern_mode` should ever be `sequence`/`forgetful` per enemy
  (add a column) or stay `random`.
- `Split`/`Curl Up`/`Fading`/`Shifting` ability semantics must exist in EffectSystem
  before those enemies behave correctly.
