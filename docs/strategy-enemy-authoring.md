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
| `File` | sprite folder under `images/enemies/strategy_enemies/<File>/`; the importer copies `<id>_idle.png` into `assets/` and draws it as the grid token. Blank = a plain colour circle |
| `Min Floor` | floor gate before the enemy can spawn |
| `Spawn Weight` | weighted spawn frequency (0 = never rolled) |
| `Gold` | gold drop packed as `<pct>% <min>-<max>` (e.g. `70% 6-14`); blank = none. Enemies never drop items, so there is no item column |
| `Intents` | the move-set (grammar below) |
| `Ability` | split + starting-statuses, `/`-separated (e.g. `Split 2 rat`, `Regeneration 5 Permanent`) — see below |

### Speed drives both cadence and movement

`Speed` is a **single signed** stat centred on **0** (the baseline). It sets the
turn cadence directly (the `BattleTurnManager` act-counter weight) *and* the
per-turn tile budget, which `BattleUnit` derives as `maxi(1, BASE_MOVE + Speed /
4)` — so **4 tiles is the baseline (Speed 0)** and every ±4 Speed is ±1 tile:
`Speed 4` → 5 tiles, `Speed -4` → 3 tiles (the Troll), `Speed 8` → 6 tiles. The
initiative weight uses the same curve, so a `Speed 0` enemy keeps pace with the
`Speed 4` player while negative Speed slows it — but it's **clamped to ≥ 1**, so
`Speed ≤ -16` can't freeze a unit out of its turns entirely. A faster enemy both
acts more often and walks further; a slower one does both less.

### Starting statuses & `Permanent` (the `Ability` column)

Besides `Split N kind`, the `Ability` column lists **starting statuses** the
enemy opens combat with, `/`-separated. Each is `<Status> <N> [Permanent]`:

| Ability cell | Effect |
|---|---|
| `Regeneration 5 Permanent` | starts with 5 Regeneration that heals 5/turn and **never decays** |
| `Weak 2` | starts with 2 Weak (decays normally) |
| `Split 2 snake / Regeneration 3 Permanent` | both — split *and* a permanent regen |

`Permanent` is the `permanent` addon (authored on the `addonsnew` sheet, Uses =
`Statuses`): the status still **ticks** every turn (Regeneration heals, Poison
bites) but `Stats.decay_actor_statuses` skips its step-down, so the stack count
holds for the whole fight. Permanent statuses draw a small **lock** at the
top-right of their icon in the grid view.

The Permanent mechanism is **shared across all three combat engines**. The
strategy `BattleUnit` reads it from this `Ability` column; the deckbuilder and
action engines build a `CombatActor` and read it from a `permanent_statuses`
list on `EnemyData` / `ActionEnemyData` (the status ids in `starting_statuses`
that never decay). `Stats.decay_actor_statuses` consults `is_status_permanent`
on whichever actor type it's handed, so a flagged status behaves identically
whether the enemy is fought in deckbuilder, action, or strategy mode.

## `Intents` grammar

One cell, intents `;;`-separated (like `enemiesD`'s packed `Moves`). Each intent:

```
<id> @ <prio> [cd N] [shape S] [<size>] [<flag>] [k=v ...] [range N]
      [target T] [cond C] [icon=G] | <name> | <effects>
```

| Field | Meaning |
|---|---|
| `id` | intent id (first token) |
| `@ prio` | priority — higher wins ties; **off-cooldown always beats on-cooldown** |
| `cd N` | cooldown in turns (0 = always available) |
| `shape S` | archetype from the shared `StrategyAttackLibrary` (`poke/swing/smash/projectile/beam/nova/lob/disc/line`). Derives the grid **reach + footprint** — e.g. an Orc's `smash` Bash is a forward blast that can clip several targets. Omit it and use `range N` for a plain single-tile hit. |
| `<size>` | a **bare size word** (`short`/`medium`/`large`/`full`/`small`) sizing the shape's reach/radius — the **same keyword the player writes in the `Attack` column**, so `shape smash large` reads exactly like a card's `Smash, Large`. (`size=large` still works.) |
| `<flag>` | a bare shape flag (`pierce`/`crescent`/`explosive`/`sweep`), mirroring the player's Attack cell |
| `k=v` | other `attack_params` for the shape (e.g. `arc=360`, `spread=3`) |
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
| `dmg:<C>d<S>` | per-hit dice: roll `C` d`S` **fresh on every hit** (e.g. `dmg:1d3` → 1-3, NetHack-style). Unlike Determined, it is *not* fixed for the combat. The telegraph shows the die spec (`1D3`) while nothing modifies the roll, and switches to the predicted `lo-hi` range once something does; the AI uses the max (`C×S`) when weighing damage |
| `heal:N[:self]` | self heal |
| `block:N[:self]` | self block |
| `gain:<status>:N` | self buff (→ `status` effect, `self`) |
| `inflict:<status>:N` | debuff the target (→ `status` effect, `enemy`) |

### Worked example — the Troll

```
Speed: -4   HP: 60-66   Weight: 5   Glyph: T   Ability: Regeneration 5 Permanent
Intents: maul @ 1 icon=x shape poke small | Maul | dmg:1d8 ; dmg:1d8 ; dmg:2d6
```

→ a huge, slow (Speed -4 = 3-tile movement, low cadence) bruiser whose whole turn
is one three-hit `Maul` — claw `1d8`, claw `1d8`, bite `2d6`, all landing on the
one tile in front (`poke small` = 1 reach, single-tile footprint). It opens with
**5 Permanent Regeneration**: it heals 5 every turn and the stack never decays
(lock icon on the badge), so you have to out-damage 5 HP/turn to kill it. Each
intent compiles into an `EnemyIntent` (via `EnemyCatalog._build`), and shaped
intents take their grid reach from `StrategyAttackLibrary` so range and footprint
stay in lock-step.

### Worked example — the Sewer Rat (a custom enemy)

```
Name: Sewer Rat   Id: sewer_rat   Weight: 1   Speed: 8   File: Sewer Rat
Gold: 40% 1-4     Min HP/Max HP: 5
Intents: bite @ 1 icon=x shape poke small | Bite | dmg:1d3
```

→ a fast (Speed 8 = 6-tile budget), fragile weight-1 biter that rolls 1d3 fresh
each hit and shows its sprite from
`images/enemies/strategy_enemies/Sewer Rat/sewer_rat_idle.png`.

## How the AI picks an intent

On each turn the enemy chooses among its **available** intents (off-cooldown,
`cond` satisfied, with a live target):

1. **Attacks** (any intent that deals damage) are ranked by, in order:
   **can it reach the target this turn** → **higher damage potential** →
   priority. So an enemy with both a melee and a ranged attack that *can't* close
   to melee range will pick the **ranged** hit instead of stalling, and when it
   can do either it picks the harder-hitting one.
2. **Support** intents (heals / buffs / debuffs — no damage) are ranked by
   priority; their `cond` already gates them.
3. Priority then arbitrates between the best attack and the best support, so a
   high-priority heal (the Troll's `Regen`, priority 3) still overrides
   attacking when its condition holds.

Reachability is approximated as `range + move` in tiles at telegraph time (the
grid map isn't consulted until the unit actually moves), which is enough to
prefer a reachable ranged attack over an out-of-reach melee one.

### Telegraphs are true predictions

The number on the telegraph badge (and the initiative panel's `next:` line)
is re-computed at RENDER time by `EnemyAI.telegraph_label` through the same
shared fold the deckbuilder's intent panel uses (`Stats.predict_hit`): the
attacker's Power/Weak, the planned target's Vulnerable/Bruise, then the
Intangible clamp to 1 — so the shown value is what the hit will actually
open with, and it tracks status changes the moment they land (play Wraith
Form and every attack telegraph drops to 1).

- Flat hits show the predicted number (a base-3 hit reads `6` once the
  enemy carries 3 Power, `9` if the target is also Vulnerable).
- Dice hits keep the die spec (`1D8`) while nothing modifies the roll and
  switch to the predicted `lo-hi` range once something does (`3-10` under
  +2 Power), collapsing to one number when the bounds meet (`1` under
  Intangible).

## Fallbacks

Every consumer prefers the sheet data but falls back to its old hardcoded table
for any kind **not** on the sheet, so a missing/empty `data/strategy_enemies/`
never crashes combat — the roster archetypes still play from
`ENEMY_PRESETS` / `_ARCHETYPES` / `ENEMY_POOL` / `ENEMY_LOOT_TABLE` (kept in sync
with the sheet: Snake / Rattlesnake / Hobgoblin / Troll).
