# Games-First Redesign — design spec

Status: **draft / brainstorm captured.** This is the canonical spec for the
"no-combat" rework. It supersedes the simulated-combat loop (deckbuilder,
action, strategy). Items marked **[OPEN]** are decisions still to make.

---

## 1. The pitch

A roguelike where the "dungeon" is your backlog of **real roguelike games** and
the app is the **Dungeon Master**. There is **no simulated combat.** You navigate
the existing influence-graph of real games; each game carries a single **enemy =
a goal** you must accomplish *while actually playing that game*. Beating the goal
defeats the enemy and drops an item; beating the game *without* the goal lets the
enemy hit your health. Reach and clear the **Amulet** game to win; hit 0 health
to lose.

Designed **stream-first**: the player-facing state (health, block, the enemy and
its goal, the verb/consumable counts) renders to a slim **OBS companion window**,
so every number must stay small and glanceable.

---

## 2. Core loop

1. **Choose a game** on the graph. Routing is the core decision (see §6).
2. The game presents **one enemy** = one goal, plus its attack value and its
   guaranteed item drop.
3. **Go play the real game. You must beat the game to advance to the next area.**
4. Resolve:
   - **Goal met → enemy defeated → item drops.**
   - **Game beaten but goal not met → the enemy is not defeated: it *stacks*.**
     No item drops. The undefeated enemy carries forward and deals its `attack`;
     `block` (temp health) absorbs, remainder comes off `health`. Each new area
     you clear without its goal adds another enemy to the stack, so unbeaten
     threats accumulate and pressure ramps until you die or clear them.
     **[OPEN]** cadence of stacked-enemy damage (once when it stacks, or each
     subsequent area) and whether/how a stacked enemy's goal can still be
     retired later.
5. Repeat until the **Amulet** game is cleared (win) or **health = 0** (loss).

---

## 3. Health & block model

Kept deliberately tiny for HUD readability.

| Stat | Range (starting → cap) | Notes |
|---|---|---|
| Health | ~10 (tune) | Lose at 0. |
| Block  | 0, small | **Carries over between games — it is temporary health**, absorbed before `health` on any hit. |
| Enemy attack | 1–3 | The hit dealt by an enemy that stacks (game cleared without its goal). |

Block sources: completing a goal, certain tag routes, spending a scroll, or item
drops of the `block` category. The central tension is *earn block by beating
goals → spend it surviving the goals you skip or fail.*

---

## 4. The verbs & consumables (the "hand")

These replace card-play as the way you manipulate the board. All are small
integer counts on the HUD.

### Verbs (map manipulation)
| Verb | Effect |
|---|---|
| **Bash** | Destroy a game node and replace it with a random new one. |
| **Dash** | Skip a game entirely (move past, no play, no drop). |
| **Scramble** | Reroll the current game's enemy/goal (and/or the offering). |

### Consumables
| Item | Effect |
|---|---|
| **Key** | Unlock a new game path (blocked edge / unconnected "wild" game). |
| **Bomb** | Directly defeat a goal-enemy *without* doing its goal (escape hatch for undoable goals). **No item drops** when an enemy is bombed. |
| **Scroll: Fog** | Kept from legacy — **obscures certain choices** on the graph, as it does today. |
| **Scroll: Teleportation** | Kept from legacy. Jump across the graph. |

Verbs and consumables are **earned from enemy drops** and spent to route around
goals you can't or won't complete.

---

## 5. Curses — shelved for now

**Curses are not part of the current design.** The enemy-with-a-goal *is* the
challenge mechanic, so curses are deliberately set aside to avoid duplicating that
role. The existing `CurseData` content and hooks stay in the repo (not deleted),
and curses may return later as an opt-in gambit layer, but nothing in the core
loop depends on them.

---

## 6. Types & tags — the connective tissue

Routing replaces combat as the decision space. Two axes carry it:

### 6.1 Game type (the enemy-pool axis)
The **type** determines which enemy/goal pool a game draws from (§7). Today the
map has two types (Action, Strategy) with `deckbuilder` / `traditional` as *tags*.
**Decided: `deckbuilder` and `traditional` are promoted back to first-class
types** (each was previously a tag). The type set becomes **Action / Deckbuilder /
Traditional**. Each type has its own goal pool ("beat a boss without healing"
suits Action; "win in one deck cycle" suits Deckbuilder; "descend N floors" suits
Traditional). **[OPEN, minor]** whether a separate **Strategy** type survives for
non-deckbuilder strategy games, or those fold into the three above.

### 6.2 Tags (the routing / synergy axis)
- **Widen the tag vocabulary** on `GameData` and make tags first-class.
- **Path/edge requirements** can demand tags/types ("this edge needs a
  *Deckbuilder* clear").
- **Items & scrolls** can trigger on tags/types.
- Routing becomes a type/tag-collection puzzle → replayability for a no-combat map.

---

## 7. Enemies = goals (schema)

One enemy per game. The enemy is **rolled at runtime from a pool filtered by the
run's difficulty tier and the game's type** (not authored per-game) — this reuses
the existing `EnemySpawner` weight/tier budget logic: difficulty sets which pool
is eligible, game type narrows it. Harder tier / later game → nastier goal, bigger
attack, better drop.

Proposed `EnemyData` (repurposed / new `GoalData`) fields:

| Field | Meaning |
|---|---|
| `id` | slug |
| `display_name` | enemy name shown on HUD |
| `goal` | the challenge text ("Beat a boss without healing") |
| `type` | which game **type(s)** this enemy is eligible for (§6.1) |
| `min_tier` / `weight` | difficulty gate + spawn weight (mirrors `EnemySpawner`) |
| `attack` | 1–3 damage dealt if you clear the game without the goal |
| `drop` | the guaranteed item id (or drop-pool ref) — see §8 |
| art | enemy sprite for the HUD |

---

## 8. Item drops — the whole reward economy

**Every enemy drops exactly one item.** The drop table *is* the reward economy.
Each item belongs to one **category**, and the categories are exactly the
resource vocabulary above:

| Category | What it grants |
|---|---|
| `status` | A **run-scoped modifier** (statuses are no longer combat buffs — e.g. "+1 block per goal cleared", "next enemy attack −1", "gain an extra scroll on tag X"). |
| `health` | Restore / raise health. |
| `block` | Grant block. |
| `scroll` | A fog / teleportation scroll. |
| `verb` | A bash / dash / scramble charge. |
| `key` | A path key. |
| `bomb` | A bomb. |

This directly informs the **items sheet redo** (§10).

---

## 9. OBS companion window

- The player-facing HUD is a **separate slim companion window** captured in OBS,
  **not** the main app window you drive from.
- **Designed to help the viewer follow the run** — at a glance the audience should
  see the current game, the enemy and **what its goal is** (so they know what
  they're rooting for), health, block, the stack of undefeated enemies, and the
  verb/consumable counts.
- Renders: health, block, current enemy + its goal, the **stacked-enemy count**,
  verb counts (bash/dash/scramble), consumable counts (keys/bombs/scrolls).
- Architecture: a dedicated HUD scene reading the same `GameState`/autoloads the
  main window mutates. **[OPEN]** second Godot `Window` vs. a separate always-on-top
  borderless scene the user positions over OBS.
- Everything must read at a glance → keep all numbers single-digit where possible.

---

## 10. Sheet / content redo blueprint

The new `tools/Roguelikes.xlsx` sheets to (re)build. Regenerate `.tres` via the
existing `tools/generate_*` pattern.

- **items** — rebuild around the §8 categories. Columns (proposed):
  `id | display_name | category | value | tags | rarity | art | description`
  where `category` is one of the §8 set and `value`/`tags` parameterize it.
- **enemies (goals)** — the §7 schema, pooled by **type + difficulty tier**:
  `id | name | goal | type | min_tier | weight | attack | drop | art`. The
  `type` / `min_tier` / `weight` columns feed the `EnemySpawner` roll.
- **games** — extend with a **richer tag column** and (likely) the promoted
  **type** (§6.1). Regenerate via `import-games-godot.py`.
- **scrolls** — trim to the kept set (fog, teleportation) and fill in real
  effects (currently inert stubs).
- **curses** — **shelved** (§5). Existing content stays but no sheet work now.
- **bingo** — **retired.** The one-enemy-per-game model fully replaces it; the
  legacy `bingo-data.js` / `bingo.js` are not ported.

---

## 11. Codebase impact

**Keep & repoint:** overworld graph, `GameData` (+ richer tags/types),
`CurseData`, encounters (shops/deals/teleporters), `EffectSystem` + `TriggerBus`
(repoint triggers: `on_goal_met`, `on_game_beaten`, `on_curse_broken`,
`on_enemy_defeated`), `EnemySpawner` (repoint to roll goal-enemies by type +
tier, §7), scrolls, `GameStats`/verification, Collection.

**Add:** the tiny health/block model; the bash/dash/scramble + keys/bombs
resource layer; the OBS companion HUD scene; the play-session resolver
(accept game → report result → resolve drop/damage/curse).

**Cut (behind an archive git tag, like `strategy-grid-combat-archive`):**
`scenes/deckbuilder/`, `scenes/action/`, `scripts/deckbuilder/`, `scripts/action/`,
`scripts/strategy*`, enemies-as-combatants (`data/enemies`, `data/action_enemies`
— the combat stat blocks; the *goal* enemies are new content), combat
cards/statuses, potions-as-combat-items (repurpose or cut).

---

## 12. Open decisions (rolled up)

1. **Stacked-enemy damage cadence** — does a stacked enemy hit once when it
   stacks, or again each subsequent area? Can its goal still be retired later to
   remove it? (§2)
2. **OBS HUD architecture** — second Godot `Window` vs. separate always-on-top
   scene positioned over OBS. (§9)
3. **Starting values** — health, block cap, verb/consumable starting counts. (§3)
4. **Strategy type** *(minor)* — does a Strategy type survive for non-deckbuilder
   strategy games, or do they fold into Action/Deckbuilder/Traditional? (§6.1)

**Resolved:**
- Bingo is retired (§10).
- Enemies roll by type + difficulty tier, not fixed per game (§7).
- You must beat the real game to advance; undefeated enemies **stack** (§2).
- Block **carries over** as temporary health (§3).
- Bombed enemies **drop nothing** (§4).
- Fog **obscures** certain choices (§4).
- **Curses shelved** — enemies-with-goals are the challenge mechanic (§5).
- `deckbuilder` + `traditional` **promoted to first-class types** (§6.1).
- No-goal clear **drops nothing** (the enemy stacks instead) (§2).
