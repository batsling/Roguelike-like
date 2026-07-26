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
     No item drops. Every stacked enemy **attacks after each game you play**,
     for its `attack`, until its goal is fulfilled — `block` (temp health) absorbs,
     remainder comes off `health`. So the more unbeaten enemies on the stack, the
     more damage you take per game, and pressure ramps until you die or clear them.
   - **Old goals can still be fulfilled later.** Fulfilling a stacked enemy's goal
     during any later game **defeats it** (removing it from the stack and stopping
     its per-game hits) and drops its item, exactly as if you'd beaten it on time.
   - **Enemies follow the player until beaten.** A following enemy **cannot be
     dashed/moved past** (moving to another game never drops it). It is removed by
     fulfilling its goal — or, for a **normal** enemy, by a **bomb** (bombs damage
     normal enemies; no drop when bombed). **Bosses take no bomb damage** and can
     only be removed by their goal. Pre-commit escapes (**scramble** the goal /
     **bash** the game) also exist before you play.
5. Repeat until the **Amulet** game is cleared (win) or **health = 0** (loss).

---

## 3. Health & block model

Kept deliberately tiny for HUD readability.

| Stat | Value | Notes |
|---|---|---|
| Health | character-set (5–10) | Current HP. Lose at 0. |
| Max Health | character-set | The cap Health heals up to; **items raise it** (`+N Max Health`). Distinct from Health — some items give one, some both, some only Max. |
| Block  | 0, **no cap** | **Carries over between games — it is temporary health**, absorbed before `health` on any hit. |
| Enemy damage | 1–3 (by tier) | Dealt by each stacked enemy after **every** game played, until its goal is fulfilled (Low 1 / Med 2 / High 3, per `enemies2.0`). |

**Starting loadout depends on the chosen character** (`characters2.0`). Character
select is where the run's starting Health and verb/consumable counts come from.
Current roster:

| Character | Game | Health | Bash | Dash | Transmute | Scramble | Bombs | Keys | Starting item |
|---|---|--:|--:|--:|--:|--:|--:|--:|---|
| Rodney | Rogue | 5 | 0 | 0 | 0 | 0 | 0 | 0 | — |
| Isaac | The Binding of Isaac | 6 | 0 | 0 | 0 | 0 | 1 | 0 | D6 |
| Zoe | Haste | 8 | 0 | 0 | 0 | 0 | 0 | 0 | — |
| Minä | Noita | 8 | 0 | 0 | 1 | 0 | 0 | 0 | — |
| Ironclad | Slay the Spire | 10 | 0 | 0 | 0 | 0 | 0 | 0 | Burning Blood |

Block sources: completing a goal, certain tag routes, a scroll, or an item (e.g.
**Anchor** — "after beating a game, gain +1 Block"). The central tension is *earn
block by beating goals → spend it surviving the goals you skip or fail.*

### 3.1 Characters, Level Up & the reward loop

Each character (`characters2.0`) carries a personal **Level Up** objective and a
**Reward** granted when it's met — a meta-progression hook layered on the run:

| Character | Level Up objective | Reward |
|---|---|---|
| Rodney | Beat a game without meta progression | +1 Max Health, +1 Health, +1 Scroll |
| Isaac | Unlock a new Item | +1 Small Chest |
| Zoe | Perfect a Game | +1 Dash |
| Minä | Craft or combine a spell or weapon | +1 Transmute |
| Ironclad | Unlock a new difficulty | +1 Small Chest |

- Level Up objectives are **real-game accomplishments** you report (honour /
  verification), themed to that character's origin game.
- **Level Up is repeatable** — the **Crown** item gives "when Levelling Up, 50%
  chance to Level Up an additional time," which only makes sense if levelling
  recurs. **[OPEN]** does the same objective re-trigger each time, or does it
  escalate/rotate?
- **Small Chest** is a reward container (grants item[s]). **[OPEN]** contents &
  count.
- Rewards draw from the same resource vocabulary as drops (Max Health, Dash,
  Transmute, Scroll, Small Chest).

---

## 4. The verbs & consumables (the "hand")

These replace card-play as the way you manipulate the board. All are small
integer counts on the HUD.

### Verbs (map manipulation)
| Verb | Effect |
|---|---|
| **Bash** | **Destroy a game outright — it is removed from the pool and can never show up again.** (Changed: no longer replaces with a new game.) |
| **Transmute** | **Turn a game into a random game of the *same game type* that is *not connected to the map*.** (New verb — this is the "replace with a fresh game" role bash used to have, now type-constrained and pulling from off-graph games.) |
| **Dash** | **As in the current project: a total select, not a skip** — pick *any* connected game and move to it (bypassing the normal limited offering). Costs 1 dash charge. See `Overworld._try_dash`. |
| **Scramble** | Reroll the current game's enemy/goal (and/or the offering). Granted by the **D6** item. |

### Consumables
| Item | Effect |
|---|---|
| **Key** | Unlock a new game path (blocked edge / unconnected "wild" game). *(No 2.0 content grants keys yet — see open questions.)* |
| **Bomb** | Deal 1 damage to a **normal** enemy. Normal enemies have **Health 1** (`enemies2.0`), so one bomb removes one (no item drops). **Bosses are immune to bombs** (§7.1). |
| **Scroll** | Consumables with an identity that starts **unidentified** and a **Preference** (Positive / Negative / Neutral). See §4.1. |

Verbs and consumables come from **enemy drops, item effects, and character
rewards**, and are spent to route around goals you can't or won't complete.

### 4.1 Scrolls (`scrolls2.0`)

Scrolls now form an **identification** minigame (roguelike-traditional): they
arrive unidentified and carry a Preference that colours whether reading a mystery
scroll is a gamble. **Note: the old "Fog" scroll is not in `scrolls2.0`** — the
current set is enemy/movement-facing instead:

| Scroll | Preference | Effect |
|---|---|---|
| Aggravate Monsters | Negative | Enemies deal +1 damage for one game. |
| Amnesia | Negative | Forget 1 random scroll. |
| Create Monster | Negative | Spawn a random enemy at the current difficulty. |
| Identify | Positive | Choose 1 scroll to identify. |
| Scare Monster | Positive | Choose 1 enemy to **Stun** (see below). |
| Teleportation | Neutral | Teleport to a random space ~the same distance from the Amulet game (±1). |

This introduces two new enemy-state mechanics: **Stun** (Scare Monster) and
**spawning** enemies (Create Monster). **[OPEN]** what Stun does to a following
enemy (skip its next per-game attack? can't hit for one game?).

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
Traditional / Strategy**, where **Strategy is the residual** — a strategy game
that carries *neither* the `traditional` nor the `deckbuilder` tag. Each type has
its own goal pool ("beat a boss without healing" suits Action; "win in one deck
cycle" suits Deckbuilder; "descend N floors" suits Traditional).

### 6.2 Tags (the routing / synergy axis)
- **Widen the tag vocabulary** on `GameData` and make tags first-class.
- **Path/edge requirements** can demand tags/types ("this edge needs a
  *Deckbuilder* clear").
- **Items & scrolls** can trigger on tags/types.
- Routing becomes a type/tag-collection puzzle → replayability for a no-combat map.

---

## 7. Enemies = goals (schema)

One enemy per game, **rolled from a pool filtered by the game's `Type` and the
run's `Difficulty` tier** (reusing `EnemySpawner`'s tier logic). Harder tier →
more damage and (naturally) a better drop.

`enemies2.0` schema (actual columns):

| Column | Meaning |
|---|---|
| `Name` | enemy name shown on HUD |
| `Type` | game type this enemy spawns on — **Deckbuilder / Action / …** (§6.1) |
| `Difficulty` | tier gate — **Low / Medium / High** |
| `Game` | the real game the enemy references (Slay the Spire, Brotato) |
| `Health` | enemy HP — **1** across the current roster (so one bomb kills a normal enemy, §4) |
| `Damage` | per-game hit while stacked — **1 / 2 / 3** tracking the tier |
| `Goal Type` | **Bounty / Restriction / Discovery** (see below) |
| `Goal` | the challenge text |
| `Ability` | optional special (all `N/A` today) |
| `File` / `Tag` | art id / synergy tag (e.g. `slime`, `alien`) |

**Goal Types** — three flavours of challenge:
- **Bounty** — defeat a specific in-game enemy ("Defeat an enemy that splits,"
  "Defeat an enemy that is an alien").
- **Restriction** — a self-imposed rule on your play ("You must randomly select
  your starting character").
- **Discovery** — witness/experience something ("Witness an enemy kill itself").

**Tag synergy:** an enemy's `Tag` links to items sharing it — e.g. the `alien`
Baby Alien enemy, the `alien` **Alien Baby** item, and the bounty "defeat an
alien" all interlock. Current roster: Spike Slime (L), Snecko, Transient (all
Deckbuilder/Slay the Spire), Baby Alien (Action/Brotato).

### 7.1 Bosses

**Bosses appear when the run's difficulty tier changes** (the existing
`RunDifficulty` transitions). A boss is a heavier enemy that:

- carries a **more specific goal** (tighter than a normal enemy's — e.g. "beat the
  *true* ending," "clear it deathless" rather than just "beat a boss"),
- **deals more damage** than a normal stacked enemy (above the 1–3 band),
- and (naturally) drops a better item.

Otherwise a boss follows the same rules: fulfill its goal to defeat it, or it
stacks and hits you after every game until you do. A boss **cannot be dashed
past**, and unlike a normal enemy **takes no damage from bombs** — a boss can
*only* be removed by fulfilling its goal. **[OPEN]** exact boss attack value, and
whether the pre-commit escapes (**scramble** the goal / **bash** the game) are
allowed on a boss node or whether difficulty-gate bosses are fully unskippable.

---

## 8. Items (`items2.0`)

Every defeated enemy drops an item, so the item table *is* the reward economy.
Items are authored in `items2.0` with these columns: `Name | Rating | Type |
Description | Effect | Reference | tags | File | Sorting`.

**Rating** = rarity: Starter / Common / Uncommon / Rare / Legendary.

**Type** = *behavior class* (how the item works, not what it grants):

| Type | Behavior |
|---|---|
| `Pickup` | One-time instant effect on acquire (e.g. Hollow Heart: +4 Max Health). |
| `Triggered` | Fires on a game event — almost always **"after beating a game"** (Anchor +1 Block, Burning Blood +1 Health, Meat on the Bone conditional heal). |
| `Charged, N` | Usable, recharges over N beats (D6 → +1 Scramble; Wand of Wishing → any item, 6). |
| `Usable` | Active, player-triggered (Ride the Bus → teleport to a random Deckbuilder game). |
| `Passive` | Always-on modifier (Vajra: +1 Bash). |

**"After beating a game" is the dominant trigger** — the core `TriggerBus` event
the item layer hangs on (§11). Others seen: "when Levelling Up" (Crown), "when
your Health ≤ 50% Max after beating a game" (Meat on the Bone), "when you would
gain +1 Transmute" (Snowball).

**Effect vocabulary** items grant, all small: `+Health`, `+Max Health`, `+Block`,
`+Bash / +Dash / +Transmute / +Scramble`, `+Scroll`, Small Chest, Level Up (extra),
teleport (by type), obtain-item. **Sorting** buckets them for UI: Health / Defense
/ Economy / Stats / Movement. **tags** (alien, dice, food, sea…) drive synergy
with enemy tags (§7) and goals.

Sample synergies already in the sheet: **Crown** doubles Level Ups; **Snowball**
doubles Transmute gains; **Alien Baby** (+6 Max Health but all enemies +1 Health)
plays against the `alien` bounty; **Unstable Genome** self-destructs for a
3-item choice.

---

## 9. OBS companion window

- The player-facing HUD is a **separate slim companion window** captured in OBS,
  **not** the main app window you drive from.
- **Designed to help the viewer follow the run** — at a glance the audience should
  see the current game, the enemy and **what its goal is** (so they know what
  they're rooting for), health, block, the stack of undefeated enemies, and the
  verb/consumable counts.
- Renders: health, block, current enemy + its goal, the **stacked-enemy count**,
  verb counts (bash/dash/transmute/scramble), consumable counts (keys/bombs/scrolls).
- Architecture: a dedicated HUD scene reading the same `GameState`/autoloads the
  main window mutates. Godot `Window` vs. always-on-top scene, and the exact
  layout, are **deferred** — revisit once the rest of the mechanics are locked.
- Everything must read at a glance → keep all numbers single-digit where possible.

---

## 10. Sheet / content redo blueprint

The **`*2.0` sheets in `tools/Roguelikes.xlsx` are the new source of truth** for
the redesign content. Each needs a `tools/generate_*` pass to emit `.tres` and a
Resource schema in `scripts/resources/`.

- **characters2.0** — `Name | Game | Health | Bash | Dash | Transmute | Scramble |
  Bombs | Keys | Level Up | Reward | Description | Starting items`. Drives the
  starting loadout (§3) and the Level Up loop (§3.1). 5 characters.
- **items2.0** — `Name | Rating | Type | Description | Effect | Reference | tags |
  File | Sorting` (§8). 14 items. `Effect` column currently empty → the structured
  effect DSL still needs authoring from the `Description`.
- **enemies2.0** — `Name | Type | Difficulty | Game | Health | Damage | Goal Type |
  Goal | Ability | File | Tag` (§7). 4 enemies.
- **scrolls2.0** — `Scrolls | Game | Preference | Description | File` (§4.1). 6
  scrolls, identification + Preference. **Fog dropped** vs. the old set.
- **games** — extend with richer tags and the promoted **type** (§6.1). Regenerate
  via `import-games-godot.py`.
- **curses** — **shelved** (§5). **bingo** — **retired**; legacy not ported.

---

## 11. Codebase impact

**Keep & repoint:** overworld graph, `GameData` (+ richer tags/types),
`CurseData`, encounters (shops/deals/teleporters), `EffectSystem` + `TriggerBus`
(repoint triggers: `on_goal_met`, `on_game_beaten`, `on_curse_broken`,
`on_enemy_defeated`), `EnemySpawner` (repoint to roll goal-enemies by type +
tier, §7), scrolls, `GameStats`/verification, Collection.

**Add:** the tiny health/**max-health**/block model; the **bash / dash /
transmute / scramble** + keys/bombs resource layer; the **Level Up** loop (§3.1);
scroll **identification** + **Stun** (§4.1); item **behavior-class** dispatch
(Pickup / Triggered / Charged / Usable / Passive, §8); generators + Resource
schemas for the four `*2.0` sheets; the OBS companion HUD scene; the play-session
resolver (accept game → report result → resolve drop/damage/level-up).

**Cut (behind an archive git tag, like `strategy-grid-combat-archive`):**
`scenes/deckbuilder/`, `scenes/action/`, `scripts/deckbuilder/`, `scripts/action/`,
`scripts/strategy*`, enemies-as-combatants (`data/enemies`, `data/action_enemies`
— the combat stat blocks; the *goal* enemies are new content), combat
cards/statuses, potions-as-combat-items (repurpose or cut).

---

## 12. Open decisions (rolled up)

New, raised by the `*2.0` sheets:
1. **Level Up** — is it repeatable with the *same* objective (Crown implies
   recurrence), or does it escalate/rotate? What does levelling do besides the
   Reward — scale difficulty, unlock, both? (§3.1)
2. **Small Chest** — contents and item count. (§3.1)
3. **Stun** (Scare Monster) — effect on a following enemy (skip one per-game
   attack? can't hit for one game?). (§4.1)
4. **Fog dropped** — confirm Fog is gone for good (not in `scrolls2.0`), or should
   it be re-added? (§4.1)
5. **Keys unused** — no `*2.0` character or item grants keys and no path-locks
   exist yet. Author key sources + locked edges, or cut keys? (§4)
6. **Item `Effect` DSL** — `items2.0.Effect` is blank; the structured effects need
   authoring from each `Description`. What's the token grammar? (§8)
7. **Scroll identification stakes** — do unidentified scrolls read blind (Preference
   is the gamble), and what does Amnesia forgetting an *identified* scroll cost? (§4.1)
8. **Enemy `Ability`** — the column exists but is all `N/A`; reserved for later
   enemy specials? (§7)

Still open from before:
9. **Boss escapes** — are scramble/bash allowed on a boss node, or fully
   unskippable? Plus boss damage value. (§7.1)
10. **OBS HUD** — deferred: architecture + layout once mechanics lock. (§9)

**Resolved (incl. by the 2.0 sheets):**
- **Bash** now **destroys a game out of the pool** (no replacement); **Transmute**
  is the new verb that turns a game into an unconnected same-type game (§4).
- **Normal enemies have Health 1** → one bomb removes one; bosses are bomb-immune
  (§4/§7.1). *(closes the old bomb-HP question.)*
- **Starting values are authored per character** in `characters2.0` (Health 5–10)
  (§3). **Max Health** is now a stat items can raise (§3).
- **Goal Types = Bounty / Restriction / Discovery** (§7).
- **Item Types = Pickup / Triggered / Charged / Usable / Passive**; main trigger is
  "after beating a game" (§8).
- **Scrolls carry a Preference and are identified**; Fog is not in the new set (§4.1).
- Dash is a total select (§4). Enemies follow until beaten; can't be dashed past
  (§2). Bosses appear on difficulty change (§7.1). Enemies roll by type + tier (§7).
  Must beat the game to advance; unbeaten enemies stack and hit each game (§2).
  Block carries over, no cap (§3). Curses shelved (§5). Bingo retired (§10).
  Types = Action / Deckbuilder / Traditional / Strategy (§6.1).
