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

Designed **stream-first**: the player-facing state (health, shields, the enemy and
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
     No item drops. A stacked enemy has a **one-game grace** (§7.2) — its first
     hit lands only after the *next* game is beaten — then it **attacks after each
     game you play**, for its `Damage`, until its goal is fulfilled. Unspent
     `shields` (§3.2) absorb, remainder comes off `health`. The more unbeaten enemies on
     the stack, the more damage per game, ramping until you die or clear them.
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

## 3. Health & shield model

Kept deliberately tiny for HUD readability.

| Stat | Value | Notes |
|---|---|---|
| Health | character-set (5–10) | Current HP. Lose at 0. |
| Max Health | character-set | The cap Health heals up to; **items raise it** (`+N Max Health`). Distinct from Health — some items give one, some both, some only Max. |
| Shields | granted per game, **no cap** | **The TRIES at the game you selected** (see §3.2). Absorbed before `health` on any hit, and **expire with the game that granted them**. |
| Enemy damage | 1–3 (by tier) | Dealt by each stacked enemy after **every** game played, until its goal is fulfilled (Low 1 / Med 2 / High 3, per `enemies2.0`). |

**Starting loadout depends on the chosen character** (`characters2.0`). Character
select is where the run's starting Health and verb/consumable counts come from.
Current roster:

| Character | Game | Health | Bash | Dash | Push | Transmute | Scramble | Bombs | Keys | Starting item |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|---|
| Rodney | Rogue | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | — |
| Isaac | The Binding of Isaac | 6 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | D6 |
| Zoe | Haste | 8 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | — |
| Minä | Noita | 8 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | — |
| Ironclad | Slay the Spire | 10 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | Burning Blood |
| Manager | Raccoin: Coin Pusher Roguelike | 8 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | — |

Shield sources beyond the per-game grant: items (**Anchor** — "when a game is
selected, gain +1 Shield"), and future tag routes / scrolls.

### 3.1 Characters, Level Up & the reward loop

**This reuses the current project's level-up mechanic directly** (`CharacterData`
+ `Overworld._resolve_level_up`). In `characters2.0`, **the columns left of `Level
Up` (Health, Bash, Dash, Push, Transmute, Scramble, Bombs, Keys) are the character's
starting stats**; `Level Up` is a per-game challenge and `Reward` is what meeting
it grants.

| Character | Level Up objective (per game) | Reward |
|---|---|---|
| Rodney | Beat a game without meta progression | +1 Max Health, +1 Health, +1 Scroll |
| Isaac | Unlock a new Item | +1 Small Chest |
| Zoe | Perfect a Game | +1 Dash |
| Minä | Craft or combine a spell or weapon | +1 Transmute |
| Ironclad | Unlock a new difficulty | +1 Small Chest |
| Manager | Collect 3+ different types of currency | +1 Push |

How it already works in the project (to be kept):
- After each game, the **post-game verification modal** asks the character's
  `level_up_condition` as an honour-system **Yes/No**. Yes → apply `level_up_stats`
  and grant the reward (`_level_up_once`). So **each game is a fresh chance** to
  hit the challenge and level again — exactly as requested.
- **Crown** already exists as `bonus_level_up_chance` (roll an extra level-up);
  **Snowball** as `stat_gain_bonus` (+1 on a keyed stat gain). Both need only the
  new stat ids (transmute, bash, …) added.
- **"Perfect a Game"** (Zoe) already exists as the `perfect_aware` /
  `perfect_effects` verification path — reuse it.
- Rewards draw from the same resource vocabulary as drops (Max Health, Dash,
  Transmute, Scroll, Small Chest — see §8.1 Chests).

### 3.2 Shields = the tries (the attempt tracker)

A roguelike is not beaten in one run, so **shields are how many runs you get**:

- **Selecting a game grants them** — **3** for any game, **5** for a
  **Traditional** roguelike (the long haul); nothing else moves the number, so it
  reads straight off the game's type. Items hooked on *"when a game is selected"*
  add to the grant, which is what **Anchor** now does (+1 Shield): the extra try
  has to arrive *before* you go and play. The grant is part of the routing
  decision, so it's on every offered card and previews in the HUD on hover.
- **Every run of that game you LOSE is one tick of the attempt tracker**, and each
  tick **spends a shield**. The tracker lives with the checklist in the left column
  of the playing screen; the board stands in the right column (with the pack under
  it) and draws the pool as pips on the hero, so ticking visibly drains it. The
  stage keeps that shape between games: the board stays put and the checklist
  becomes the standing-goals list — the level-up challenge and every follower's
  outstanding goal (§2) — so "what do I need to do?" is answerable before you
  commit to a game, not only after.
- **Out of shields, a lost run costs 1 Health** — and Health reaching 0 ends the
  run right there, exactly like an enemy hit.
- **Whatever is left when you report the game absorbs the followers' hits** before
  Health, then **expires**. Shields never bank into the next game: an easy game
  cleared first try does not arm you for the next one.

The tension is *spend your tries getting the goal done → what you didn't need is
the armour that carries you through the enemies you left alive.* A game cleared
first try leaves the whole pool standing, so the stack can't touch you; a game that
fights back leaves you open to it. **Health is meant to be hard to reach while
you're playing well** — the followers' 1–3 damage is a threat to a player who is
burning tries, not to one who isn't.

---

## 4. The verbs & consumables (the "hand")

These replace card-play as the way you manipulate the board. All are small
integer counts on the HUD.

### Verbs (map manipulation)
| Verb | Effect |
|---|---|
| **Bash** | **Destroy a game outright — it is removed from the pool and can never show up again.** The card it vacated is **refilled from the same pool the offering is drawn from**: another game *connected to where you are standing*, with its own freshly-rolled goal-enemy (the other cards keep the enemies they were already showing). When that node has no other connection left to give, the slot simply goes — bash is destruction, not a guaranteed reroll. Two bashes are refused outright, because both end the run rather than shape it: the **Amulet game** (destroying the goal makes the run unwinnable) and the **last card on the table** with nothing to replace it. |
| **Transmute** | **Turn a game into a random game of the *same game type* that is *not connected to the map*.** (New verb — this is the "replace with a fresh game" role bash used to have, now type-constrained and pulling from off-graph games.) **Traditional is the exception**: it transmutes into a random game of any *other* type, drawn flat from the non-Traditional catalog. A Traditional roguelike is the run's long haul — it grants 5 tries rather than 3 — so swapping one for another is no relief, and the verb has to be able to get you out of the type. |
| **Dash** | **As in the current project: a total select, not a skip** — pick *any* connected game and move to it (bypassing the normal limited offering). Costs 1 dash charge. See `Overworld._try_dash`. |
| **Scramble** | **Reroll the offering** — re-draw the games filling the (base three) choice slots, each with a freshly-rolled enemy/goal. At a node with no spare neighbours the slots hold and only the enemies change. Granted by the **D6** item. |
| **Push** | **Shove a following enemy back one space — delay its next attack by one game (§7.2).** Spends 1 push charge; rides the same per-enemy delay counter as Stun, but is player-triggered. The **Manager**'s signature verb (gained on level-up: "Collect 3+ different types of currency" → +1 Push). |

### Consumables
| Item | Effect |
|---|---|
| **Key** | Unlock a new game path (blocked edge / unconnected "wild" game). *(No 2.0 content grants keys yet — see open questions.)* |
| **Bomb** | Deal 1 damage to an enemy. Normal enemies have **Health 1** (`enemies2.0`), so one bomb removes one (no item drops). A **boss is a legal target but takes no bomb damage** (§7.1) — the charge only buys what an item hangs off the throw. Three items change what a bomb does: **Brimstone Bombs** widen the blast to the target's whole row *and* column, **Sticky Bombs** stun whatever the blast fails to destroy (in practice, bosses), and **Blood Bombs** pay +1 Health per bomb via the `bomb_used` trigger. |
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
**spawning** enemies (Create Monster). **Stun makes the enemy skip its next
attack** — it pushes the enemy's attack one game later in the timing model (§7.2),
buying the player another game to solve it.

**Identification (reuse `PotionSystem`'s pattern via a new `ScrollSystem`).** The
project already ships full consumable identification — `PotionSystem.is_identified
/ identify / display_name / art_texture` with a mystery-art fallback, plus an
existing `images/scrolls/Unidentified.png`. Scrolls get the identical treatment:

- A scroll type starts **unidentified**: it shows the generic **Unidentified**
  art and a masked name, and reading it is the Preference gamble.
- It becomes **identified** by reading one (learn-by-use) or via **Scroll of
  Identify**; from then on that type shows its real name and art. **Amnesia** can
  re-hide (`unidentify`) a known scroll.
- **The `File` column is the identified art** — it resolves to
  `images2.0/scrolls/<File>.png` (§10.1). Unidentified scrolls always show the
  shared Unidentified art, so a scroll only reveals its `File` art once learned.
- **Fallback:** an *identified* scroll with **no image** (blank `File`, or a file
  that doesn't resolve) **also defaults to the Unidentified scroll art** — never a
  missing/broken texture. So Unidentified art is both the pre-identify mask and
  the safety fallback for authored-but-artless scrolls.

*(The old **Fog** scroll and **Keys** are both **deferred — author later**; they
stay in the design but no `2.0` content exists for them yet.)*

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
| `Size` | battlefield footprint, **rows first** — `1x1`, `1x2` (two wide), `2x1` (two tall), `2x2`, or a shaped one like `2x3 L 90 CC` (§7.3) |
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
stacks and hits you (per §7.2) until you do. A boss **cannot be dashed
past**, and unlike a normal enemy **takes no damage from bombs** — a boss can
*only* be removed by fulfilling its goal. It can still be *bombed*, though: the
throw is legal and spends the charge, it just does no damage, which is how
**Sticky Bombs**' stun (§4) reaches a boss at all. **[OPEN]** exact boss attack value, and
whether the pre-commit escapes (**scramble** the goal / **bash** the game) are
allowed on a boss node or whether difficulty-gate bosses are fully unskippable.

### 7.2 Enemy timing — the one-game grace

Enemies don't hit immediately; there's always **one extra game** to find a
solution:

1. **Spawn** — an enemy appears when you **choose** its game.
2. You play & **beat that game**. If its goal wasn't met, the enemy persists (it
   does *not* attack yet).
3. Its **first attack lands after the *next* game is chosen and beaten** — i.e.
   one game later. That intervening game is the "extra step" where you can still
   fulfill the old goal (§2), bomb a normal enemy, or Stun it.
4. Thereafter it keeps attacking on each game beaten, per §2, until its goal is
   met or it's removed.

The grace is **one game**, not one action, and it survives §7.4: however many
turns the enemies are taking, the current game's enemy resolves *after* all of
them, so it never strikes on the game that spawned it.

**Stun** (Scroll of Scare Monster, §4.1) costs the target **one turn** — it
neither strikes nor steps, and one stack of stun ticks off with it. Out in the
wilds that is the whole game; on the Amulet's doorstep it is a third of one (see
§7.4). Old-goal **fulfilment** works the other way round: a follower you engaged
this game holds its fire for **every** turn of it, so it grows *more* valuable
as the pace rises. This grace window is why bombs, old-goal fulfilment, and Stun
are all viable answers rather than needing to solve an enemy the instant it
appears.

### 7.3 The battlefield grid — footprints, rows, and blocking

The stack is drawn as a **Mega-Man-Battle-Network-style board**: the player on
the left, a **4 x 4 grid** of columns (distance) x rows (lanes) on the right.
Column 1 is melee, column 4 the back edge.

4 x 4 is the **starting** size, not a fixed one. Two things grow it, and they
add together:

- **The difficulty tier.** Every step of the tier ladder (§7.1) adds **a column
  and a row**: 4x4 at Low, 5x5 Medium, 6x6 High, 7x7 Insane, and there it stops,
  because the tier does. This is the counterweight to §7.4 — the tier that makes
  the enemies heavier also gives you more ground to lose before they arrive, so
  three turns a game at the high tiers is still a couple of games of warning.
- **Mine-r Construction** (Broomsweeper, Uncommon) adds another column and row
  **per copy owned** — a deeper board to cross before anything reaches you, and
  another lane to stand in, which also means one more body can pack the front
  line.

`GameLoop2.grid_cols()` / `grid_rows()` answer the current size (base 4 plus
`GameLoop2.grid_growth()`, which is the tier's growth plus the inventory's), so
nothing measures the board against a constant. Growth doesn't shove the
bodies already standing on it — they keep their column, and the gain lands on
what spawns next — but it does open room for the overflow queue, which walks
onto the new lane immediately, picking its row by the usual clearest-run rule.
Should the item ever leave the inventory the board shrinks back, and anything it
would strand off the edge is put back in the queue rather than left hanging.

- **Spawn** — an enemy walks onto the board positioned so its **rightmost cell
  lands on the back column**. A 1x1 therefore starts on column 4, but a 3-wide body
  starts on column 2, with its leading edge already two columns closer. The row
  is **random among the lanes it can actually reach the player from** — enemies
  never change lanes, so a row with a body parked in it would leave the new
  arrival stuck behind a wall forever, and those rows are skipped while any
  clear lane is left. Nothing waits outside the board unless it has nowhere to
  stand; that overflow queue slides on as space frees.
- **Advance** — each turn (§7.4), every enemy that isn't striking closes one
  column, front-first.
- **Strike** — an enemy attacks once **any** of its cells is in column 1. Wide
  bodies reach that line in fewer games; that's the point of `Size`.
- **Blocking** — an enemy occupies every solid cell of its footprint, and moves
  only when its **whole** footprint clears. A big body is a wall: it plugs the
  lanes behind it, and the queue stalls until it moves or dies. **Push** needs
  the entire footprint to fit one column back, so a jammed board can't be
  untangled by shoving.

**`Size` notation** — `RxC`, **rows first**: `1x2` is two cells wide, `2x1` two
cells tall. A trailing shape + rotation carves a non-rectangle out of that box:
`2x3 L 90 CC` is an L turned a quarter turn counter-clockwise, i.e.

```
. . #
# # #
```

The **empty cells of the bounding box are real gaps** — another enemy (or a
dropped item) can stand in the notch. Only the solid cells block. The **art is
always drawn across the full bounding box**, so the parts that stick up out of
the solid rows are never cropped.

**Drawing order** — bodies lower on the grid paint over the ones above them
(ordered by the bottom edge of the footprint), so overlapping art layers
naturally. **Hovering** any enemy lifts it above everything else, so a body
that's partly covered can still be read and clicked; hit-testing follows the
**mask, not the bounding box**, so an L's notch belongs to whoever is standing
in it. **Health and damage badges draw on a layer above every body** (and above
a hovered one), so an overlapped enemy's stats are never hidden. All of this
layers by **tree order, never `z_index`** — `z_index` is relative to the parent
and would punch the board out through the enemy info card and the reward
screens, which sit above the battlefield only because they're mounted after it.

### 7.4 Amulet pressure — the enemies speed up as you close in

The run has two difficulty axes. The tier ladder (§7.1) is the clock: it ticks
up on its own, every `GAMES_PER_TIER` games, and the player only rides it. This
is the other one, and it's the one the player **steers**.

**How many turns the enemies take each game is read off how far you are from the
Amulet**, in hops over the run graph:

| Hops to the Amulet | Turns per game | Band |
|---|---|---|
| 5 or more | 1 | Distant |
| 3 – 4 | 2 | Closing |
| 2 – 0 | 3 | Doorstep |

A **turn** is one action, and every enemy takes one on each of them: a body
touching column 1 **strikes**, everything behind it **steps** a column closer. A
turn is exactly the strike-then-advance the loop has always resolved, so the
Distant band *is* the pre-ladder game and the near bands are that same beat,
repeated. One turn a game therefore changes nothing about the rules — it just
stops being the only speed.

**Why.** The routing decision used to be one-directional: the Amulet is the win
condition, so every step toward it was strictly good and the only reason to take
the long way was to farm. This makes the long way a real option. Route wide and
you fight a slow stack for more games; bum-rush the Amulet and you fight a fast
one for fewer. Neither dominates, and the stack you've accumulated decides which
is right — three followers on your tail is a very different calculation at ×3
than at ×1.

The consequences fall out of the same rule rather than being special-cased:

- An enemy two columns back is no longer safe. At ×3 it walks into range **and**
  swings before the game is out, so "how far away is it" has to be measured in
  turns, not columns (`GameLoop2.games_until_strike`).
- **Stun** costs one turn, so it's worth a third of a game at the doorstep and a
  whole one in the wilds — the same charge, priced by the pace.
- **Old-goal fulfilment** holds a follower's fire for the whole game, so it goes
  the other way and is worth *more* the closer you push (§7.2).
- **Aggravate Monsters** buffs each hit, so a three-turn game is three buffed
  hits — the pace amplifies it like everything else.
- Taking the **Amulet card itself** ends the run on the spot, so it carries no
  pace warning: there is no next game for the enemies to act in.

**Where the player sees it.** All of it, before committing:

- A **strip across the top of the battlefield**, in the band's colour, reading
  `⏱ ENEMY TURNS ×N`, a three-rung ladder filled to the current band, and the
  hop count that put it there — plus the board's current size and tier on the
  right, since §7.3 is the other half of the same bargain.
- Every **offered card** says what taking it does to the pace — *speeds up*,
  *slows down*, or *still ×N* — next to the route badge that says what it does
  to the distance, because they are the same decision.
- Each **body on the board** carries what it does on the next game reported:
  `×2` for two swings, `in 2` for two games of walking still to do. Threat
  colours follow that number rather than the raw column.
- The **resolve plays turn by turn**, counter and all (`TURN 2 / 3`), instead of
  collapsing into one slide — watching the same beat land three times is how the
  ladder is felt rather than merely read.

`RunDifficulty.turns_for_hops` owns the ladder and `GameLoop2.enemy_turns()`
applies it; both are pure, so the board, the cards and the resolver cannot
disagree about the number. A run with no Amulet picked, or standing somewhere
with no route to it, reads as Distant — nothing is closing in on a goal that
isn't there.

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
| `Triggered` | Fires on a game event — usually **"after beating a game"** (Burning Blood +1 Health, Meat on the Bone conditional heal), or **"when a game is selected"** (Anchor +1 Shield, §3.2). |
| `Charged, N` | Usable, recharges over N beats (D6 → +1 Scramble; Wand of Wishing → any item, 6). |
| `Usable` | Active, player-triggered (Ride the Bus → teleport to a random Deckbuilder game). |
| `Passive` | Always-on modifier (Mine-r Construction: grow the Grid). |

**"After beating a game" is the dominant trigger** — the core `TriggerBus` event
the item layer hangs on (§11). Others seen: "when Levelling Up" (Crown), "when
your Health ≤ 50% Max after beating a game" (Meat on the Bone), "when you would
gain +1 Transmute" (Snowball).

**Effect vocabulary** items grant, all small: `+Health`, `+Max Health`, `+Shield`,
`+Bash / +Dash / +Transmute / +Scramble`, `+Scroll`, Small Chest, Level Up (extra),
teleport (by type), obtain-item, and **grow the Grid** (Mine-r Construction,
§7.3). **Sorting** buckets them for UI: Health / Defense / Economy / Stats /
Movement / Bomb / Grid — a design-side column the generator does not read.
**tags** (alien, dice, food, sea…) drive synergy with enemy tags (§7) and goals.

Sample synergies already in the sheet: **Crown** doubles Level Ups; **Snowball**
doubles Transmute gains; **Alien Baby** (+6 Max Health but all enemies +1 Health)
plays against the `alien` bounty; **Unstable Genome** self-destructs for a
3-item choice.

### 8.1 Effect DSL — reuse the existing item grammar

The `items2.0.Effect` column is authored in the **same grammar the project already
uses**, so no new engine is needed:

- **Triggered / Usable / Charged** items → `ItemData.triggers = [{on: <TriggerBus
  signal>, if_*: <gates>, effects: [{type: <EffectSystem handler>, …}]}]`.
- **Passive** items → `stat_bonuses` (an always-on verb bonus, e.g. `{bash: 1}`).
- **Pickup** items → a one-shot `item_acquired` trigger with scene-free effects
  (`gain_hp` / `gain_max_hp` / …).
- The two run-lifecycle triggers are **`game_beaten`** ("after beating a game")
  and **`game_selected`** ("when a game is selected", the shield hook §3.2),
  alongside the existing `item_acquired` hook.
- Effect handlers reused as-is: `gain_hp`, `gain_max_hp`, `gain_stat` (shields and
  the verbs), `gain_chest`,
  `chance`, `if_hp`, `counter`, plus new small ones for the verbs (`gain_stat`
  already grants ability points; extend its vocabulary to bash/transmute/
  scramble/bombs/keys).

Scrolls/encounters keep their **semicolon-separated, space-delimited token** DSL
(`generate_scroll_tres.py` / `generate_encounter_tres.py`); the item generator
(`generate_item_tres.py`) compiles the `Effect` column into `triggers`.

### 8.2 Chests (reuse `grant_chest` + `RewardScreen`)

A **chest** is the project's existing item-reward container
(`GameState.grant_chest` → `RewardScreen`, `BASE_ITEM_CHOICES = 2`). Sizes map to
the number of choices offered:

| Chest size | Choices |
|---|---|
| **Small** | 1 item (no choice) |
| **Medium** | pick 1 of 2 |
| **Large** | pick 1 of 3 |
| **Huge** | pick 1 of 5 |

Level-up rewards (`+1 Small Chest`, `+1 Large Chest`) and drops both mint chests
through this same flow. A level-up Reward cell that NAMES a size carries the
choice count on `CharacterData.level_up_reward_chest_choices` (Zagreus'
`+1 Large Chest` → pick 1 of 3); an unsized `+1 Chest` leaves it 0 and takes the
reward screen's own default. A **`+1 Random Sized Chest`** reward (the Vampire Survivors characters — Poe
Ratcho, Antonio Belpaese) rolls the chest's SIZE (`Data.ChestSize`, wording that
describes how big the chest is, not the rarity of the items inside it) on the same
ladder as every other rarity draw in the game (`Data.roll_rarity_step` — 75% / 20%
/ 5%, with the top step having a 10% chance to bump one further), so Small /
Medium / Large / Huge come up at exactly those odds (`Data.CHEST_SIZE_CHOICES`).

---

## 9. OBS companion window

- The player-facing HUD is a **separate slim companion window** captured in OBS,
  **not** the main app window you drive from.
- **Designed to help the viewer follow the run** — at a glance the audience should
  see the current game, the enemy and **what its goal is** (so they know what
  they're rooting for), health, shields, the stack of undefeated enemies, and the
  verb/consumable counts.
- Renders: health, shields + attempts, current enemy + its goal, the **stacked-enemy count**,
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

**What `Year` means, and what a backward connection is.** `Year` is the year a
game first became **available to influence others** — an early-access date, or a
demo where that's when it started mattering (Balatro is dated 2023 for its demo,
not its 2024 release). It is *not* the year the game stopped changing. Roguelikes
are frequently decades-long projects (NetHack, DCSS, Cataclysm, HyperRogue,
ADOM), and a game still under active development can take an influence from
something that shipped after its own first release.

So a **backward connection** — an influence pointing at a game with an earlier
`Year` — is **legal and supported end to end**: `import-games-godot.py` writes it
like any other, `RunGraph` traverses the graph undirected, the Atlas lays out
from hop distance rather than from years, and `map_layout.py` draws it sweeping
upward into the older game instead of down. `check_map_sync.py` lists them
without failing, purely so a mistyped year — which produces the identical shape —
gets noticed rather than buried.

### 10.1 Art / image folders (`images2.0/`)

Reshaping the project creates a **new `images2.0/` drop folder** (parallel to the
existing `images/`, which stays for legacy/combat art), with one subfolder per
2.0 content type:

```
images2.0/
├── characters/
├── items/
├── enemies/
└── scrolls/
```

- Art resolves from each sheet's **`File` column** →
  `res://images2.0/<category>/<File>.png` (PascalCase, matching the current
  convention). `items2.0`, `enemies2.0`, and `scrolls2.0` all carry a `File`
  column, and `characters2.0` now carries one too (its art lives under
  `Full/` and `Icon/`); a blank `File` falls back to the de-spaced `Name`.
- **Scrolls:** `File` is the *identified* art; unidentified scrolls — **and
  identified scrolls whose `File` art is missing** — fall back to the shared
  `Unidentified.png` under `images2.0/scrolls/` (§4.1).
- The generators point their art lookups at `images2.0/<category>/` instead of the
  old `images/<category>/`.

---

## 11. Codebase impact

**Reuse heavily (already built — the redesign leans on these):**
- **Level-up** — `CharacterData.level_up_*` + `Overworld._resolve_level_up` /
  `_level_up_once` / `_roll_bonus_level_up`, the verification-modal Yes/No, Crown
  (`bonus_level_up_chance`), Snowball (`stat_gain_bonus`), and the "Perfect a
  Game" path (`perfect_aware`/`perfect_effects`). (§3.1)
- **Items** — `ItemData` (ItemKind = Passive/Triggered/Usable/Charged/Pickup maps
  1:1 to `items2.0.Type`), `triggers`/`stat_bonuses`, `EffectSystem` handlers,
  `TriggerBus`. (§8/§8.1)
- **Chests** — `GameState.grant_chest` + `RewardScreen`. (§8.2)
- **Verification** — the post-game modal, `GameStats`, `last_game_*` state.

**Keep & repoint:** overworld graph, `GameData` (+ richer tags/types), encounters
(shops/deals/teleporters), `EnemySpawner` (roll goal-enemies by type + tier, §7),
scrolls, Collection. Add trigger `game_beaten` for the "after beating a game" item
hook.

**Add:** the tiny health/**max-health**/shield model; the **bash / dash /
transmute / scramble** + keys/bombs resource layer; the **Level Up** loop (§3.1);
a **`ScrollSystem`** mirroring `PotionSystem` for identification + **Stun** (§4.1);
item **behavior-class** dispatch (Pickup / Triggered / Charged / Usable / Passive,
§8); the **`images2.0/`** folder tree + generator art-path repoint (§10.1);
generators + Resource schemas for the four `*2.0` sheets; the OBS companion HUD
scene; the play-session resolver (accept game → report result → resolve
drop/damage/level-up).

**Cut (behind an archive git tag, like `strategy-grid-combat-archive`):**
`scenes/deckbuilder/`, `scenes/action/`, `scripts/deckbuilder/`, `scripts/action/`,
`scripts/strategy*`, enemies-as-combatants (`data/enemies`, `data/action_enemies`
— the combat stat blocks; the *goal* enemies are new content), combat
cards/statuses, potions-as-combat-items (repurpose or cut).

---

## 12. Open decisions (rolled up)

Still open:
1. **Boss escapes** — are scramble/bash allowed on a boss node, or fully
   unskippable? Plus boss damage value. (§7.1)
2. **OBS HUD** — deferred: architecture + layout once mechanics lock. (§9)
3. **Enemy `Ability`** — column exists but all `N/A`; reserved for later specials? (§7)

Deferred by decision (author later): **Fog** scroll and **Keys** + locked paths.

**Resolved:**
- **Shields are the TRIES at a game** (§3.2): granted on selection (3, or 5 for a
  Traditional roguelike), one spent per lost run via the attempt tracker, 1 Health
  per lost run once they're gone, leftovers absorb the followers' hits and then
  expire with the game. This replaced the earlier "Block carries over between
  games, no cap" rule. **Anchor** moved to the new **`game_selected`** trigger so
  its +1 Shield is an extra try rather than a reward after the fact.
- **Level Up = the current project's mechanic** (per-game `level_up_condition`
  Yes/No → stats + reward, repeats each game). The stats left of the `Level Up`
  column are the character's **starting stats** (§3.1).
- **Chests: Small = 1 item, Regular = 1 of 2, Large = 1 of 3**, via the existing
  `grant_chest`/`RewardScreen` flow (§8.2).
- **Statuses rewrite GOALS, and each side is authored** (§13): a status's `On
  Player` and `On Enemy` halves each name a mode (`goal` / `clause` / `bonus`) plus
  an optional `decay`, so the two can differ. `Type` (Buff / Debuff) is flavour —
  the HUD tint and the collection filter — and drives nothing.
- **Stun skips the enemy's next attack** — pushes it one game later in the timing
  model (§7.2).
- **Enemy timing: one-game grace** — spawns on game choice, first hits after the
  *next* game is beaten, giving an "extra step" to solve it (§7.2).
- **Item Effect DSL = the existing `ItemData.triggers`/`EffectSystem` grammar**;
  add the `game_beaten` and `game_selected` triggers (§8.1).
- **Scroll identification reuses `PotionSystem`** (new `ScrollSystem`): scrolls
  read blind (Preference is the gamble), learn-by-use or via Scroll of Identify,
  Amnesia re-hides. The **`File` column is the identified art** (§4.1).
- **New `images2.0/{characters,items,enemies,scrolls}/` folder**; art resolves via
  each sheet's `File` column (§10.1).
- **Bash** destroys a game out of the pool and refills its slot from the games
  connected to where you stand; **Transmute** turns a game into an unconnected
  same-type game — or, from a Traditional game, an unconnected game of any other
  type (§4).
- **The run opens on a choice of three starting games**, one per game type, each
  6–8 games from the randomly-rolled amulet (`RunGraph.pick_amulet_and_starts`).
  The start is where you BEGIN — it spawns no enemy and grants no shields; the
  run's first game is whatever you travel to from it.
- **A run can be saved and resumed.** The save carries GameState (vitals, verbs,
  pack, visited/beaten games), GameLoop2 (the enemy stack and its positions, the
  destroyed games, the attempt tracker) and the overworld's own view (the cards on
  the table, the game in play, any unanswered kill-drop). The overworld's **💾 Save** button
  writes a named save; the run also keeps an **autosave** that is rewritten every
  time it moves and cleared when it ends. Both are resumable from the menu's
  **Continue** list.
- **Normal enemies have Health 1** → one bomb removes one; bosses bomb-immune
  (§4/§7.1).
- **Starting values authored per character** (`characters2.0`, Health 5–10);
  **Max Health** is a raisable stat (§3).
- Goal Types = Bounty/Restriction/Discovery (§7). Item Types =
  Pickup/Triggered/Charged/Usable/Passive (§8). Scrolls carry a Preference and are
  identified; Fog not in the new set (§4.1). Dash is a total select (§4). Enemies
  follow until beaten, can't be dashed past (§2). Bosses appear on difficulty
  change (§7.1). Enemies roll by type + tier (§7). Must beat the game to advance;
  unbeaten enemies stack (§2). Curses shelved
  (§5). Bingo retired (§10). Types = Action/Deckbuilder/Traditional/Strategy (§6.1).

---

## 13. Statuses (`statuses2.0`)

A **status** is the balance lever. It is not a stat modifier and not combat state
— it is a **clause bolted onto a goal**, because goals are the only currency this
game has. That is what lets a location, an item, or a scroll change how hard the
run is without any of them knowing what a goal is.

A status has **two sides** — `On Player` and `On Enemy` — authored independently,
so its halves can do genuinely different things. Each side names a **mode**, and
the mode is the whole of what that side does:

| Mode | What the side does |
|---|---|
| `goal` | a **standing objective of the holder's own** — "If \<condition\>, gain \<reward\>". On the player it is an extra checklist row, offered every game and paid every time it is met. |
| `clause` | **ANDed onto goals and required** — the goal is not met until both were done. On an enemy it tightens that enemy's goal; on the player it tightens **every** enemy's goal. |
| `bonus` | an **optional objective** — "and if \<condition\>, gain \<reward\>" — claimable for its reward and free to skip. |

A side may also carry `decay`: completing it sheds one stack.

Because the mode says what a side does, **`Type` (Buff / Debuff) drives no
mechanic** — it is the HUD tint and the collection filter, nothing more. The
interesting statuses are the ones whose two sides differ. Marked taxes every one
of your goals on the player's side and *pays out* on the enemy's, so the same
status is a tax you grind off and a reason to engage the thing carrying it.

### 13.1 Schema

`statuses2.0` columns: `Name | Type | Game | On Player | On Enemy | Stackable |
Image | On Player Effect | On Enemy Effect`.

The two **prose** columns (`On Player` / `On Enemy`) are the author's wording,
carried onto `StatusData` for tooltips. Beside each sits its machine-readable
counterpart, which is what the engine runs on:

    <verb> "<condition>" [decay] [-> <reward>; <reward>; …]

where `<verb>` is one of the three modes above. So the current roster reads:

| Status | `On Player Effect` | `On Enemy Effect` |
|---|---|---|
| Strength | `goal "the difficulty is increased {X} times" -> gain_chest small {X}; gain_stat bash {X}` | `clause "the difficulty must be increased {X} times"` |
| Dexterity | `goal "beaten in {1+(1/2)^(X-2):hours} or less" -> gain_chest small {X}; gain_stat dash {X}` | `clause "must be beaten in {1+(1/2)^(X-2):hours} or less"` |
| Marked | `clause "you must get {X} achievements" decay` | `bonus "you get {X} achievements" decay -> gain_chest small {X}` |

A `clause` may not carry a reward — it is a requirement, not a payout, and the
generator rejects one rather than silently dropping it. Either side may be left
blank, which reads as "this side is inert".

**Reward token DSL** (compiled by `tools/generate_status_tres.py` into
`EffectSystem` effect dicts, so a chest a status grants is the same chest an item
grants, §8.2): `gain_chest [small|medium|large|huge] <n>`, `gain_stat <stat> <n>`,
`gain_hp <n>`, `gain_max_hp <n>`, `gain_gold <n>`. Any `<n>` is a literal or an
`{expr}`; expressions are held in a `scaled` sub-dict and evaluated at apply time,
since X isn't known until the status is on something.

**`{expr}` holes** are arithmetic over X, evaluated at runtime through Godot's
`Expression`. The generator normalises the sheet's `a^b` into `pow(a, b)` and every
integer literal into a float — `1/2` under integer division is 0, which turned
Dexterity's one-stack window into `pow(0, -1)` hours. Alongside them,
`[singular|plural]` markers agree in number with the last `{expr}` resolved, so one
authored string reads correctly at every stack count.

**Stackable: Intensity** — a second application **raises X**, it does not start a
second timer. Marked twice is one Marked at 2. No max stack is authored.

**Decay is authored per side**, with the `decay` flag. A side that decays sheds a
stack each time it is completed — once per game, not once per goal, so a game where
you cleared four followers cannot wipe a four-stack status whole. Strength's
standing goal does *not* decay: it **is** the reward, and putting a timer on it
would only make it a worse item.

### 13.2 The current roster

| Status | Type | From | Condition | Reward |
|---|---|---|---|---|
| **Strength** | Buff | Slay the Spire | the difficulty is increased X times | +X Small Chests, +X Bashes |
| **Dexterity** | Buff | Slay the Spire | beaten in 1+(1/2)^(X-2) hours or less | +X Small Chests, +X Dashes |
| **Marked** | Debuff | Mewgenics | you get X achievements | +X Small Chests |

Dexterity's window halves toward a floor of one hour: **3 hours** at one stack,
**2 hours** at two, **1 hour 30 minutes** at three, **1 hour 15 minutes** at four.
The reward grows with X while the window tightens, which is the whole trade. A
fractional window is rendered as hours and minutes rather than as a decimal — it
is a time the player holds against a clock, and "1.5 hours" is arithmetic they
would have to do themselves mid-run.

Two items hand statuses out, the pair of Slay the Spire relics that grant these
same two stats there: **Vajra** (+1 Strength) and **Oddly Smooth Stone**
(+1 Dexterity). Both are `Pickup` items firing `item_acquired`, so the status
lands when the relic is taken and stays for the run.

### 13.3 Where they live at runtime

- **On the player** — `GameState.player_statuses` (id → stacks), with
  `apply_status` / `remove_status` / `status_objectives` (the claimable rows) /
  `status_clauses` (the taxes). Run-scope: cleared by `reset_run`, saved under
  `player_statuses`.
- **On an enemy** — a `statuses` dict on the **GameLoop2 stack entry**, so a status
  rides the *body* and survives the current enemy walking onto the board. Saved
  inside `GameLoop2.serialize()`.
- **`GameLoop2.goal_text_for(entry)` is THE goal line.** Every live view asks for
  it rather than reading `GoalEnemyData.goal`, which is only ever the unmodified
  stem — the checklist, the enemy card, the scroll target picker, and the headless
  `PlaySession2` driver all go through it. (Catalog views — Collection, the Atlas,
  the note modal — keep showing the authored goal, since they describe the enemy
  rather than the run.)
- **Applying one** — the `apply_status` effect (`apply_status <id> [N]
  [target=player|current|all|random]` in the item Effect DSL). `player` is the
  default; `current` / `all` / `random` route through
  `GameLoop2.apply_enemy_status`. This is the hook locations and items use.
- **Claiming one** — `beat_game(goal_met, fulfilled, claims)` takes the status half
  of the self-report: `{"status_goals": [id…], "bonuses": [{instance, status}…]}`.
  Claims resolve **before** the board does, so beating an enemy and claiming its
  bonus in the same game pays both.
- **Editing the sheet** — `tools/_statuses_sheet_setup.py` and
  `tools/_items2_statuses_setup.py` go through `tools/_xlsx_surgery.py`, which
  rewrites one sheet's two XML parts and copies every other zip entry through
  untouched. An openpyxl round-trip of this workbook silently drops its seven
  charts, so nothing here may use one.
