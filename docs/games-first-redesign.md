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

1. **Choose a game** on the graph. Routing is the core decision (see §6 Tags).
2. The game presents **one enemy** = one goal, plus its attack value and its
   guaranteed item drop.
3. Optionally take a **curse** (opt-in gambit, §5) for a better drop.
4. **Go play the real game.**
5. Resolve:
   - **Goal met → enemy defeated → item drops.** (+ curse honored, if taken.)
   - **Game beaten but goal not met → enemy attacks:** `block` absorbs, remainder
     comes off `health`. **[OPEN]** does a no-goal clear still drop anything, or
     nothing? (Leaning: nothing, or a downgraded drop.)
   - **Curse broken → curse's damage** applies (this is what makes curses bite).
6. Repeat until the **Amulet** game is cleared (win) or **health = 0** (loss).

---

## 3. Health & block model

Kept deliberately tiny for HUD readability.

| Stat | Range (starting → cap) | Notes |
|---|---|---|
| Health | ~10 (tune) | Lose at 0. |
| Block  | 0, small | Resets? persists? **[OPEN]** — leaning **persists** between games, since there are no turns. |
| Enemy attack | 1–3 | The hit taken when you clear a game without its goal. |

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
| **Bomb** | Directly defeat a goal-enemy *without* doing its goal (escape hatch for undoable goals). **[OPEN]** does a bombed enemy still drop? Leaning **no**. |
| **Scroll: Fog** | Kept from legacy. **[OPEN]** exact effect (obscure vs. reveal graph info). |
| **Scroll: Teleportation** | Kept from legacy. Jump across the graph. |

Verbs and consumables are **earned from enemy drops** and spent to route around
goals you can't or won't complete.

---

## 5. Curses — opt-in gambit (not load-bearing)

Curses become **optional harder self-imposed goals** you take *on a specific game*
for a better drop. They reuse the existing `CurseData` RESTRICTION content.

- Taking a curse improves the game's drop (rarer/upgraded item). **[OPEN]** exact
  reward bump.
- **Breaking a curse is what deals damage** (honour system + existing
  `last_game_curses_held` / `last_game_curses_triggered` verification hooks).
- Curses are never forced by the core loop — they're the "press your luck" layer.
- AFFLICTION-kind curses (auto-effects on the app economy) can stay as a rarer
  imposed variant if desired, but are secondary.

---

## 6. Tags — the connective tissue

Routing replaces combat as the decision space, and **tags** are what make routing
a puzzle instead of a walk. This is the biggest content lift.

- **Widen the tag vocabulary** on `GameData` (today it's basically genre + a few
  tags like `deckbuilder` / `traditional`). Make tags first-class.
- Enemy **goals key off tags** ("beat a boss in any *Metroidvania*-tagged game").
- **Path/edge requirements** can demand tags ("this edge needs a *deckbuilder*
  clear").
- **Items & scrolls** can trigger on tags.
- Routing becomes a tag-collection puzzle → replayability for a no-combat map.

---

## 7. Enemies = goals (schema)

One enemy per game. The enemy is authored content; the *binding* of enemy→game
may be fixed or rolled at runtime by tag. **[OPEN]** fixed vs. rolled.

Proposed `EnemyData` (repurposed / new `GoalData`) fields:

| Field | Meaning |
|---|---|
| `id` | slug |
| `display_name` | enemy name shown on HUD |
| `goal` | the challenge text ("Beat a boss without healing") |
| `goal_tags` | which game tags this goal is eligible for (§6) |
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
| `curse_removal` | Shed a held curse. **[OPEN]** keep as its own category? |

This directly informs the **items sheet redo** (§10).

---

## 9. OBS companion window

- The player-facing HUD is a **separate slim companion window** captured in OBS,
  **not** the main app window you drive from.
- Renders: health, block, current enemy + its goal, verb counts (bash/dash/
  scramble), consumable counts (keys/bombs/scrolls), current curse (if any).
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
- **enemies (goals)** — the §7 schema: `id | name | goal | goal_tags | attack |
  drop | art`.
- **games** — extend with a **richer tag column** (§6). Regenerate via
  `import-games-godot.py`.
- **scrolls** — trim to the kept set (fog, teleportation) and fill in real
  effects (currently inert stubs).
- **curses** — reuse existing RESTRICTION content; add a `drop_bonus` notion
  (§5). **[OPEN]**.
- **bingo** — **[OPEN]** whether bingo survives as a parallel goal layer or is
  fully replaced by the one-enemy-per-game model. (Leaning: enemies replace it;
  bingo could return later as a run-long meta.)

---

## 11. Codebase impact

**Keep & repoint:** overworld graph, `GameData` (+ richer tags), `CurseData`,
encounters (shops/deals/teleporters), `EffectSystem` + `TriggerBus` (repoint
triggers: `on_goal_met`, `on_game_beaten`, `on_curse_broken`, `on_enemy_defeated`),
scrolls, `GameStats`/verification, Collection.

**Add:** the tiny health/block model; the bash/dash/scramble + keys/bombs
resource layer; the OBS companion HUD scene; the play-session resolver
(accept game → report result → resolve drop/damage/curse).

**Cut (behind an archive git tag, like `strategy-grid-combat-archive`):**
`scenes/deckbuilder/`, `scenes/action/`, `scripts/deckbuilder/`, `scripts/action/`,
`scripts/strategy*`, enemies-as-combatants (`data/enemies`, `data/action_enemies`),
`EnemySpawner`, combat cards/statuses, potions-as-combat-items (repurpose or cut).

---

## 12. Open decisions (rolled up)

1. No-goal clear: drop nothing, or a downgraded drop?
2. Block: persist between games (leaning yes) or reset?
3. Bombed enemy: still drops? (leaning no)
4. Fog scroll: obscure vs. reveal?
5. Curse reward bump: exact mechanism.
6. Enemy→game binding: fixed authored vs. rolled by tag at runtime.
7. `curse_removal`: own drop category or a status?
8. OBS HUD: second Godot `Window` vs. separate always-on-top scene.
9. Bingo: retired, or kept as a run-long meta layer above the per-game enemies?
10. Starting values: health, block cap, verb/consumable starting counts.
