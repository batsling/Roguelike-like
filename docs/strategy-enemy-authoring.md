# Strategy Enemy Authoring (`enemiesS`)

Strategy-mode (tactical-grid) enemies are authored in the **`enemiesS`** sheet of
`tools/Roguelikes.xlsx` and compiled into `data/strategy_enemies/<id>.tres`
(`StrategyEnemyData`). They are the Strategy sibling of the deckbuilder
`enemiesD` ([enemy-plan.md](enemy-plan.md)) and action `enemiesA`
([action-enemy-authoring.md](action-enemy-authoring.md)) rosters.

Strategy enemies are the richest of the three: besides stats they own a
**move-set of intents** (the tactical AI's options), a **spawn-pool gate** and a
**loot table**. This one sheet is the single source of truth for all of it.
Previously these lived hardcoded across four files; those now read the generated
resources via `Data` and keep their old dictionaries only as fallbacks:

| Concern | Was hardcoded in | Now sourced from |
|---|---|---|
| stats (HP, speed, weight) | `Unit.gd ENEMY_PRESETS` | `StrategyEnemyData` |
| move-set / intents | `EnemyCatalog.gd _ARCHETYPES` | `StrategyEnemyData.intents` |
| spawn pool (floor gate + weight) | `Map.gd ENEMY_POOL` | `min_floor` / `spawn_weight` |
| loot drops | `BattleView.gd ENEMY_LOOT_TABLE` | `gold_*` / `item_chance` |

## Pipeline

```
enemiesS sheet ──build_enemiesS_sheet.py──▶ (sheet)
              ──generate_strategy_enemy_tres.py──▶ data/strategy_enemies/<id>.tres
```

1. `tools/build_enemiesS_sheet.py` (re)writes the `enemiesS` sheet from the
   `ENEMIES` list in that script — edit there, then run it.
2. `tools/generate_strategy_enemy_tres.py` reads the sheet and writes the
   `.tres`. Re-run safe; it drops/rewrites only the generated files.

Both are idempotent. `Data._ready()` loads `res://data/strategy_enemies/` at
startup and exposes `Data.get_strategy_enemy(id)` / `Data.all_strategy_enemies()`.

## Columns

| Column | Meaning |
|---|---|
| `Name` | display name |
| `Id` | slug / kind key (`rat`, `troll`); defaults to a slug of `Name` |
| `Difficulty` | `Low` / `Medium` / `High` / `Boss` |
| `Weight` | 1–5 weight **class** (Vorpal matching / heft) — *not* the spawn weight |
| `Game` | source game |
| `Tag` | freeform tag |
| `Min HP` / `Max HP` | HP rolled in this range at combat start (equal = fixed) |
| `Speed` | single initiative+movement stat (see below) |
| `Glyph` | ASCII fallback char drawn on the grid |
| `Color` | portrait tint, `r,g,b` (0–1) |
| `Min Floor` | floor gate before the enemy can spawn |
| `Spawn Weight` | weighted spawn frequency (0 = never rolled) |
| `Gold` | gold drop packed as `<pct>% <min>-<max>` (e.g. `70% 6-14`); blank = none |
| `Item %` | item-drop chance (`20%` or `0.2`) |
| `Intents` | the move-set (grammar below) |
| `Ability` | split / starting-status, same meaning as `enemiesA`/`enemiesD` (e.g. `Split 2 rat`) |

### Speed drives both cadence and movement

`Speed` is a **single** stat. It sets the turn cadence directly (the
`BattleTurnManager` act-counter weight) *and* the per-turn tile budget, which
`BattleUnit` derives as `BASE_MOVE + (Speed - 4) / 2`. So a faster enemy both
acts more often and walks further, with no separate move column. `Speed 4` is
the baseline (4 tiles); `Speed 6` → 5 tiles, `Speed 2` → 3 tiles.

## `Intents` grammar

One cell, intents `;;`-separated (like `enemiesD`'s packed `Moves`). Each intent:

```
<id> @ <prio> [cd N] [shape S] [k=v ...] [range N] [target T] [cond C]
      [icon=G] | <name> | <effects>
```

| Field | Meaning |
|---|---|
| `id` | intent id (first token) |
| `@ prio` | priority — higher wins ties; **off-cooldown always beats on-cooldown** |
| `cd N` | cooldown in turns (0 = always available) |
| `shape S` | archetype from the shared `StrategyAttackLibrary` (`poke/swing/smash/projectile/beam/nova/lob/disc/line`). Derives the grid **reach + footprint** — e.g. an Orc's `smash` Bash is a forward blast that can clip several targets. Omit it and use `range N` for a plain single-tile hit. |
| `k=v` | `attack_params` for the shape (e.g. `size=large`, `arc=360`) |
| `range N` | explicit tile reach when there's no `shape` (a `shape` overrides it) |
| `target T` | `enemy` (default) / `self` / `all_enemies` |
| `cond C` | gating predicate; only `self_low_hp` is wired up today (blank = always) |
| `icon=G` | single glyph shown above the sprite in the threat telegraph |

### Effects DSL

`;`-separated, in the shared structured EffectSystem form (the same vocabulary
as cards, spells and the deckbuilder patterns). Strategy default targets:

| Token | Effect |
|---|---|
| `dmg:N` / `dmg:N:ranged` | damage the intent's target (default `enemy`) |
| `heal:N[:self]` | self heal |
| `block:N[:self]` | self block |
| `gain:<status>:N` | self buff (→ `status` effect, `self`) |
| `inflict:<status>:N` | debuff the target (→ `status` effect, `enemy`) |

### Worked example — the Troll

```
smash @ 1 icon=x shape swing                         | Smash | dmg:10 ;;
crush @ 2 cd 4 icon=! shape smash size=large         | Crush | dmg:14 ;;
regen @ 3 cd 5 icon=+ target self cond self_low_hp   | Regen | heal:5:self
```

→ a turn-1 `Smash` swing, a `Crush` large blast every 4 turns, and a `Regen`
that only fires when the Troll is below half HP. Each compiles into an
`EnemyIntent` (via `EnemyCatalog._build`), and shaped intents take their grid
reach from `StrategyAttackLibrary` so range and footprint stay in lock-step.

## Fallbacks

Every consumer prefers the sheet data but falls back to its old hardcoded table
for any kind **not** on the sheet, so a missing/empty `data/strategy_enemies/`
never crashes combat — the four legacy archetypes still play from
`ENEMY_PRESETS` / `_ARCHETYPES` / `ENEMY_POOL` / `ENEMY_LOOT_TABLE`.
