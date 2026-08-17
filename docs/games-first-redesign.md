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
   guaranteed item drop. Committing to it also spawns an **escort** (§7.5) — a
   second enemy from the same pool, with a second goal, that beating the game
   does *not* answer for. Boss rounds are the exception and spawn solo.
3. **Go play the real game. You must beat the game to advance to the next area.**
4. Resolve:
   - **Goal met → enemy defeated → item drops.**
   - **Game beaten but goal not met → the enemy is not defeated: it *stacks*.**
     No item drops. The enemy has been standing on the board since you chose its
     game (§7.2) and simply keeps walking — from the back column it takes a game
     or more to reach you — and once it is in the front column it **attacks after
     each game you play**, for its `Damage`, until its goal is fulfilled. Unspent
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
| Max Health | character-set | The cap Health heals up to; **items raise it** (`+N Max Health`). Raising it heals by the same amount — a container arrives full — so the item that means an *empty* one says so with its own token (`gain_empty_max_hp`, Hollow Heart). Lowering it is not the mirror: it takes the room and leaves the Health, which only moves when it no longer fits. |
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
  decision, so it's stated in the game's popup (§4.2) and previews in the HUD on
  hover.
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
integer counts, and each is drawn **once, by whatever owns it** — there is no HUD
strip. **Bash, Dash, Transmute and Scramble** are chips under the offering, since
all four change what is on the table. **Push and Bombs** need no row of their
own: the board's toolbar buttons already read `⇤ Push (1)` / `✸ Bomb (3)`, just
as its pressure bar already ends in the run's tier and its hero already carries
Health, the shield pips and the player's statuses. **Keys are not drawn at all** —
they are deferred and unauthored (§4.1), so there is nothing yet for a count to
mean.

### Verbs (map manipulation)
| Verb | Effect |
|---|---|
| **Bash** | **Destroy a game outright — it is removed from the pool and can never show up again.** The card it vacated is **refilled from the same pool the offering is drawn from**: another game *connected to where you are standing*, with its own freshly-rolled goal-enemy (the other cards keep the enemies they were already showing). When that node has no other connection left to give, the slot simply goes — bash is destruction, not a guaranteed reroll. Two bashes are refused outright, because both end the run rather than shape it: the **Amulet game** (destroying the goal makes the run unwinnable) and the **last card on the table** with nothing to replace it. |
| **Transmute** | **Turn a game into a random game of the *same game type* that is *not connected to the map*.** (New verb — this is the "replace with a fresh game" role bash used to have, now type-constrained and pulling from off-graph games.) **Traditional is the exception**: it transmutes into a random game of any *other* type, drawn flat from the non-Traditional catalog. A Traditional roguelike is the run's long haul — it grants 5 tries rather than 3 — so swapping one for another is no relief, and the verb has to be able to get you out of the type. |
| **Dash** | **As in the current project: a total select, not a skip** — pick *any* connected game and move to it (bypassing the normal limited offering). Costs 1 dash charge. See `Overworld._try_dash`. **Earned by going back**: beat a game **this run has already played** — cleared, failed, or walked away from — and it pays **+1 Dash** (`Overworld2._grant_repeat_dash`). The trip back is what earns it; the goal still has to be met on the return. The offering flags such a card with `⚡ +1 DASH`. |
| **Scramble** | **Reroll the offering** — re-draw the games filling the (base three) choice slots, each with a freshly-rolled enemy/goal. At a node with no spare neighbours the slots hold and only the enemies change. Granted by the **D6** item. |
| **Push** | **Shove a following enemy one cell, in any cardinal direction.** Spends 1 push charge. *Back* is the classic use — delay its next attack by a game (§7.2), riding the same per-enemy delay counter as Stun but player-triggered. *Up / down* is a **lane change**, the one move enemies can never make for themselves, so it is how a blocked lane is opened or a clear one is plugged. *Forward* is legal too, and the player's own business. The verb is armed first and aimed second: press **⇤ Push** on the board's toolbar, click the enemy, then pick one of the arrows that appear on every side it could actually move to. Nothing is spent until an arrow is pressed. The **Manager**'s signature verb (gained on level-up: "Collect 3+ different types of currency" → +1 Push). |

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
| Aggravate Monsters | Negative | Every enemy on the board gains **+1 Strength** — +1 damage on every hit, permanently (§13.4). |
| Amnesia | Negative | Forget 1 random scroll. |
| Create Monster | Negative | Spawn a random enemy at the current difficulty. |
| Identify | Positive | Choose 1 scroll to identify. |
| Scare Monster | Positive | Choose 1 enemy to **Stun** (see below). |
| Teleportation | Neutral | Teleport to a random space ~the same distance from the Amulet game (±1). |

**Sacred Bark doubles all of it** (§8) — the Negative rows included. Whether the
Bark doubled the downside was a real choice, and doubling it is what keeps the
relic a decision: a version that only ever doubled the upside would make reading
an unidentified scroll a strictly better gamble than it is, which is the one
thing the identification minigame cannot afford. The multiplier is applied to
*named* fields per effect, not to every integer in the dict — a Teleportation
scroll's `spread` is how far the landing may vary, and doubling that is not twice
the scroll, it is a worse one.

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

The game opens in an ordinary **window** (2560×1440, clamped to whatever the
screen leaves free) — see README's "The window" for why a window rather than
either fullscreen, and for the fact that the **canvas** stays a fixed 1280×720
that is *scaled* into that window rather than enlarged by it.

Scrolls are carried, so they are **tokens on the pack strip** above the board,
beside the relics, each with a small Read control above its tile — the same shape
a Usable relic's Use button takes. Not a panel of their own: a scroll is a thing
you carry and spend, which is what the pack is.

### 4.2 Choosing a game is a screen, not a click

The offering is a **routing decision**, and a routing decision cannot be made off
a cover. Clicking an offered card therefore **opens it** rather than taking it,
and the card is only the **cover art, the game's name, and the Amulet's flag**
when it is the game the run is a search for.

The popup is where the decision is actually made. It carries:

- the **optimal path from that game to the Amulet**, drawn as the same arrowed
  shortest-path ladder the 🗺 map window shows (§6), routed from the game being
  considered rather than from where the player stands — plus the route badge in
  words (`★ OPTIMAL — 4 steps left` / `↩ Detour +1` / `🏆 THE AMULET`);
- the **game**: cover at full size, type and year, the **tries** it grants (§3.2),
  what taking it does to the board's **pace** (§7.4), whether going back to it
  pays a Dash (see below), and the player's own record in it;
- the **enemy waiting there**: portrait, name, and the goal as it would actually
  be played — the player's own status clauses included (§13) — plus which enemies
  on the board have already been beaten *at this game*;
- and the three things that can be done about the card: **Travel**, **Bash**,
  **Transmute**. Bash and Transmute only appear when there is a charge, and the
  Amulet's card never offers a Bash (§4).

---

## 5. Curses — shelved for now

**The combat-era curses are not part of the current design.** The
enemy-with-a-goal *is* the challenge mechanic, so `CurseData` / `data/curses` —
the 16 curse cards of the build this one replaced — are deliberately set aside to
avoid duplicating that role. That content and its hooks stay in the repo (not
deleted), and they may return later as an opt-in gambit layer, but nothing in the
core loop depends on them.

**Not to be confused with a CURSE GOAL**, which is live and authored: a row on the
post-game checklist that you are trying *not* to complete, defined in the
`curses2.0` sheet and described in `event-sheet-authoring.md` §6. Same word,
different thing, and nothing wires the two together. Its penalty is always the
same one — **spawn a random enemy at the run's current difficulty** — so a curse
bills in the run's own currency rather than competing with the enemy stack for
the Health bar. Events hand them out (`add_curse`), and so does one relic: the
Calling Bell arrives with a permanent Curse of the Bell (§8).

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
more damage and (naturally) a better drop. One enemy is what the game *owns* —
committing to it stands a second body from the same pool beside it (the escort,
§7.5), which the game's own goal does not answer for.

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
- and drops a **Boss relic** — not a better roll on the ordinary table, but a
  relic out of a pool nothing else can reach (§8).

**A boss round announces itself in a popup** (`BossNoticeModal`), once, as the
offering that carries it comes back. It was a strip above the offering, which is
the wrong shape for a thing that happens once and has to be acknowledged: it
shoved the offering, the checklist and the board down the page at the moment
those were being read, and then held a row of a one-screen layout for the whole
round. The popup also has room for the part the strip never said — that a boss
round is a different set of rules (no bomb damage; bash / transmute / scramble
buy you a *different* boss rather than a way past this one) — and it shows the
bosses standing on the cards, which the cards themselves already name. **Those
portraits open**: clicking one puts the ordinary enemy card (`EnemyInfoCard`)
over the popup, so the goal, the damage and the tier are readable at the moment
the warning is given rather than one screen later. It is read-only — the boss has
no body on the board yet, and the card's Push / Bomb verbs are aimed at one — and
the warning is still there, unanswered, underneath it.

Otherwise a boss follows the same rules: fulfill its goal to defeat it, or it
stacks and hits you (per §7.2) until you do. A boss **cannot be dashed
past**, and unlike a normal enemy **takes no damage from bombs** — a boss can
*only* be removed by fulfilling its goal. It can still be *bombed*, though: the
throw is legal and spends the charge, it just does no damage, which is how
**Sticky Bombs**' stun (§4) reaches a boss at all. **[OPEN]** exact boss attack value, and
whether the pre-commit escapes (**scramble** the goal / **bash** the game) are
allowed on a boss node or whether difficulty-gate bosses are fully unskippable.

### 7.2 Enemy timing — spawn onto the board, then walk

An enemy **spawns onto the battlefield the moment you choose its game**, at the
back column, and from that moment it is an ordinary body on the board: it takes
its turns, it is drawn with everything else, and it is `GameLoop2.current` only
in the sense that it is the one whose goal this game is being played for
(`current` and its stack entry are literally the same record).

1. **Spawn** — the enemy appears **on the back column** when you choose its game.
2. You play & **beat that game**, and the resolve runs in this order: goals met
   this game land their hits (the current enemy's, plus any old goals you also
   cleared), then every surviving body takes its `enemy_turns()` actions.
3. So an enemy whose goal you met is **defeated before it acts at all**, and one
   whose goal you missed **starts walking during its own game** — reaching the
   front column takes it the width of the board, which is where the breathing
   room comes from.
4. Thereafter it keeps attacking on each game beaten, per §2, until its goal is
   met or it's removed.

**This used to be a rule and is now a distance.** The enemy used to wait in an
off-field lane and step onto the grid only once its game was reported, which
bought it a guaranteed "one-game grace" no matter what. The grace is now simply
that it spawns at the far edge: it is worth exactly the ground between the back
column and the front, which the difficulty tier widens (§7.3) and the amulet
pressure ladder eats into (§7.4). The board says how long you have instead of a
rule saying it, and the enemy you are playing against is visibly *on the board*
you are trying to survive.

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
- **Philosophers Stone** and **Runic Dome** (Slay the Spire, Boss) each add a
  column and *no row*, per copy owned. Length without width is the better half of
  the trade — pure distance, with no extra lane for the stack to attack from —
  which is why both of them charge for it: the Stone gives every enemy that spawns
  +1 Strength (§13.4), and the Dome hides the enemy behind a game until you have
  committed to it, so the column is bought with routing blind.

`GameLoop2.grid_cols()` / `grid_rows()` answer the current size (base 4 plus
`GameLoop2.grid_growth()`, which is the tier's growth plus the inventory's, and —
for columns alone — `GameState.grid_length_growth()`), so
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
  the entire footprint to fit the cell it is being shoved into — in whichever of
  the four directions — so a jammed board can't be untangled by shoving into an
  occupied space.

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
- **Strength** buffs each hit, so a three-turn game is three buffed hits — the
  pace amplifies it like everything else. Aggravate Monsters hands it out to the
  whole board at once (§13.4), and unlike the temporary damage bonus it replaced,
  it never expires.
- **Speed** buys extra columns per step, so it is worth most in the far band —
  where there are still columns left to skip — and nothing at all once a body is
  already in the front line.
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

### 7.5 The escort — nothing spawns alone

**Committing to a game puts TWO bodies on the board**: the enemy that was
standing on it, and an **escort** rolled from the very pool that enemy came out
of — *another enemy that could have been waiting there*, at the same game type
and the same tier, through the same widening (`GameLoop2.roll_escort`).

Both spawn the ordinary way (§7.2): back column, a random row with the clearest
run at the player, off-grid queue when the back column is full. From the moment
they land there is nothing to tell them apart mechanically — the escort walks,
strikes, blocks a lane, takes a bomb, carries its own goal, and drops its own
item and gold when that goal is cleared.

**What separates them is ownership.** Only the named enemy is the game's:

- Beating the game and meeting its goal answers for **that enemy alone**. The
  escort's goal is an old goal from the moment it spawns, clearable during any
  later game like every other follower's (§2).
- So a game played and reported perfectly still leaves **one body on the board**,
  and a game whose goal you missed leaves two. The stack now grows by default
  and shrinks only when you go and work at it.
- Both are on the report checklist: the game's enemy as the top **Goal** row, the
  escort as an *Also cleared* row alongside every other follower.

**Two rules carve out of it**, both for the same reason — the escort must not
stack on top of a difficulty rule that was meant to be felt on its own:

- **A boss spawns solo.** A tier change already swaps in the heavier, bomb-immune
  pool at triple gold (§7.1); doubling the bodies on that round as well would
  merge the two steps into one wall.
- **Scramble rerolls the pair.** `choose_game` supersedes the game in play, and
  the escort came with the enemy being rejected, so it leaves with it
  (`GameLoop2.current_escort` is what makes that possible). Otherwise a D6 charge
  would be a way to *buy* bodies, one per press.

The escort is **rolled on arrival, not with the offering**. A card promises the
count and withholds the name — `⚠ One more enemy spawns with it — which one is
rolled on arrival` — so how many bodies a card puts on the board is part of the
routing decision, while which ones is not. It is named in the log and in a
notification the moment it lands, because it is the only body on the board the
player did not choose.

**Why.** Combat was too easy in exactly one way: a run's stack only ever grew
when the player failed, so a player who kept meeting goals never had a board to
survive at all, and §7.3's footprints, §7.4's turn ladder, Stun, Push and the
bombs were machinery aimed at a board that was usually empty. A guaranteed
second body makes the stack the baseline rather than the punishment, and it does
it without touching a single number: no enemy hits harder, nothing has more
Health, and every existing answer to a follower works on it unchanged.

---

## 8. Items (`items2.0`)

Every defeated enemy drops an item, so the item table *is* the reward economy.
Items are authored in `items2.0` with these columns: `Name | Rating | Type |
Description | Effect | Reference | tags | File | Sorting`.

**Rating** = where the relic comes from. Four of the values are rungs on the
rarity ladder a random draw walks — **Common / Uncommon / Rare / Legendary** — and
three are not:

| Rating | Comes from | In the random pools? |
|---|---|---|
| Common … Legendary | any drop, chest or shop shelf, weighted 75/20/5 with a 10% bump off the top | yes |
| **Starter** | a character's opening loadout (Burning Blood, D6) | no |
| **Boss** | a defeated **boss**, and nowhere else (§7.1) | no |
| **Event** | one authored event, and nowhere else (Golden Idol, `event-sheet-authoring.md` §12) | no |

The three are **flags beside the rarity, not extra rungs on it**
(`ItemData.starter` / `.boss` / `.event`, read together through `item_class()`).
That is deliberate: `ItemData.Rarity` and `Data.RarityStep` are the same four
rungs with no holes, and a shop price is *base + the rung* (§14) — a fifth value
nothing can ever roll would put a hole in both ladders and in the price list.
`ItemData.is_rollable()` is the single test every random draw uses, so the three
classes are excluded from drops, chests, shop shelves and the Relic Trader's
shelf by one rule rather than by three remembered ones.

Each gets its own colour and its own word on the card, because a Boss relic drawn
in Common grey is a lie every screen would then repeat.

**The Boss relics** (3): **Sacred Bark** doubles every loot consumable, good and
bad alike; **Calling Bell** pays three relics — one Common, one Uncommon, one Rare
— and saddles you with the permanent Curse of the Bell; **Lord's Parasol** empties
the next shop you walk into, free (§14).

**Type** = *behavior class* (how the item works, not what it grants):

| Type | Behavior |
|---|---|
| `Pickup` | One-time instant effect on acquire (e.g. Hollow Heart: +4 *empty* Max Health; Mango: +4 Max Health, healed). |
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

A **`[chest reward]`** is a number of chest **points** spent on that ladder rather
than a count of chests of one size — Small 1, Medium 2, Large 3, Huge 4, and past
four greedily as Huge chests plus one remainder:

| Points | Chests | | Points | Chests |
|---|---|---|---|---|
| 1 | Small | | 5 | Huge + Small |
| 2 | Medium | | 6 | Huge + Medium |
| 3 | Large | | 7 | Huge + Large |
| 4 | Huge | | 8 | 2 Huge |

It exists because every scaling payout in the game used to read "+X Small Chests",
which grew into X separate one-item screens each worth less than the last. Spending
the same X on a *bigger* chest keeps a growing reward growing. `Data.chest_reward_sizes`
is the equation, `Data.chest_reward_text` the wording, and the `chest_reward`
effect banks the chests it names through `GameState.grant_chests` — one grant, one
announcement, because a reward promised as one line has to arrive as one line — so
a status's payout reaches the same screen, in the same shape, as an enemy's drop.

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
- **Enemy timing: spawn onto the board, then walk** — an enemy stands on the back
  column from the moment its game is chosen and closes in from there, so the
  "extra step" to solve it is the ground it has to cross (§7.2).
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
- **The run opens on a choice of starting games** (`RunGraph.NUM_START_OPTIONS`,
  currently two), one per game type, each 4–7 games from the randomly-rolled
  amulet (`RunGraph.MIN/MAX_PATH_LENGTH`, via `pick_amulet_and_starts`) and, where
  the graph allows it, at *different* distances — so the panel is a choice of run
  length as well as genre.
  **The start is the run's first game, not a doorstep**: taking one rolls its
  goal-enemy, stands it on the board, hands over the game's tries, and drops
  straight into the report step — so a run opens with something to go and play
  rather than with a free move. The card opens the ordinary `GameChoiceModal`
  (enemy, goal, tries, connections, route) before you commit; Bash and Transmute
  are withheld there, since they reshape an offering and the picker is not one.
  **The amulet is named on this panel** — on its heading, on each card's distance
  line and on the last rung of the map the card opens. It used to be the run's one
  secret until a start was taken, with the maps drawing the destination as an
  unnamed box; choosing a start is a routing decision, and the game the road ends
  on is half of what tells one road from another.
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
- **Currency & shops** (§14): 1 gold an enemy, 3 a boss, paid with the drop (so a
  bomb pays nothing); characters open on the sheet's new `Gold` column (3 each);
  prices are 3 + the rarity rung; shops stand at the **ten best-connected games**,
  open on beating one, keep their three-item shelf for the whole run, and reroll
  for a **Scramble**. Gold never carries between runs. **`Epic` was deleted from
  `ItemData.Rarity`** — nothing rolled it and nothing was authored at it, and the
  price ladder wants no holes in it.
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

`statuses2.0` columns: `Name | Type | Game | On Player | On Player Effect |
On Enemy | On Enemy Effect | Combat | EnemyOnly | Enemy Combat Effect |
Stackable | Image`.

The two **prose** columns (`On Player` / `On Enemy`) are the author's wording,
carried onto `StatusData` for tooltips. Beside each sits its machine-readable
counterpart, which is what the engine runs on:

    <verb> "<condition>" [decay] [-> <reward>; <reward>; …]

where `<verb>` is one of the three modes above. So the current roster reads:

| Status | `On Player Effect` | `On Enemy Effect` |
|---|---|---|
| Strength | `goal "the difficulty is increased {X} times" -> gain_chest reward {X}; gain_stat bash 1` | `clause "the difficulty must be increased {X} times"` |
| Speed | `goal "beaten in {1+(1/2)^(X-2):hours} or less" -> gain_chest reward {X}; gain_stat dash 1` | `clause "must be beaten in {1+(1/2)^(X-2):hours} or less"` |
| Marked | `clause "you must get {X} achievements" decay` | `bonus "you get {X} achievements" decay -> gain_chest reward {X}` |
| Dexterity | `goal "{X} bosses were beaten without getting hit" -> gain_chest reward {X}` | `clause "you must beat {X} bosses without getting hit"` |

A `clause` may not carry a reward — it is a requirement, not a payout, and the
generator rejects one rather than silently dropping it. Either side may be left
blank, which reads as "this side is inert".

**Reward token DSL** (compiled by `tools/generate_status_tres.py` into
`EffectSystem` effect dicts, so a chest a status grants is the same chest an item
grants, §8.2): `gain_chest [small|medium|large|huge] <n>`,
`gain_chest reward <n>`, `gain_stat <stat> <n>`, `gain_hp <n>`,
`gain_max_hp <n>`, `gain_gold <n>`. Any `<n>` is a literal or an
`{expr}`; expressions are held in a `scaled` sub-dict and evaluated at apply time,
since X isn't known until the status is on something.

**`gain_chest reward <n>` is the `[chest reward]` the sheet's prose writes** — one
payout that grows with X rather than X identical Small chests. `<n>` is a count of
chest **points**, spent on the size ladder of §8.2: Small 1, Medium 2, Large 3,
Huge 4, and past that greedily as Huge chests plus one remainder. So 3 is a Large,
6 is a Huge and a Medium, 8 is two Huges. `Data.chest_reward_sizes` owns the
equation and `Data.chest_reward_text` owns the wording, so what a checklist row
promises and what the reward screen hands over cannot drift.

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

| Status | Type | From | Condition | Reward | In combat |
|---|---|---|---|---|---|
| **Strength** | Buff | Slay the Spire | the difficulty is increased X times | [chest reward X], +1 Bash | deals +X damage |
| **Speed** | Buff | Mewgenics | beaten in 1+(1/2)^(X-2) hours or less | [chest reward X], +1 Dash | closes +X tiles per turn |
| **Dexterity** | Buff | Slay the Spire | X bosses were beaten without getting hit | [chest reward X] | +X Shields |
| **Marked** | Debuff | Mewgenics | you get X achievements | [chest reward X] | takes double damage, ignoring Shields |

Speed's window halves toward a floor of one hour: **3 hours** at one stack,
**2 hours** at two, **1 hour 30 minutes** at three, **1 hour 15 minutes** at four.
The reward grows with X while the window tightens, which is the whole trade. A
fractional window is rendered as hours and minutes rather than as a decimal — it
is a time the player holds against a clock, and "1.5 hours" is arithmetic they
would have to do themselves mid-run.

**Speed was Dexterity** until the combat side landed. The time-window buff kept
its goal and its curve and took the name that describes them; Dexterity is now the
Slay the Spire relic's own reading of the word — a shield — with a
boss-flawless goal of its own. Anything that referred to the old Dexterity means
Speed.

Two items hand statuses out, the pair of Slay the Spire relics that grant these
same two stats there: **Vajra** (+1 Strength) and **Oddly Smooth Stone**
(+1 Dexterity). Both are `Pickup` items firing `item_acquired`, so the status
lands when the relic is taken and stays for the run. Two more hand them to the
OTHER side: **Scroll of Aggravate Monsters** (§4.1) puts +1 Strength on every body
on the board, and **Philosophers Stone** (§8) puts +1 Strength on every body that
spawns while it is owned.

### 13.3 Where they live at runtime

- **On the player** — `GameState.player_statuses` (id → stacks), with
  `apply_status` / `remove_status` / `status_objectives` (the claimable rows) /
  `status_clauses` (the taxes). Run-scope: cleared by `reset_run`, saved under
  `player_statuses`.
- **On an enemy** — a `statuses` dict on the **GameLoop2 stack entry**, so a status
  rides the *body* and survives the current enemy walking onto the board. Saved
  inside `GameLoop2.serialize()`, alongside a `shield` int — the pool a
  shield-granting status handed out, which is spent rather than recomputed (§13.4).
- **On screen** — the player's statuses draw as art pips between the hero's
  portrait and their health on the battlefield, and an enemy's below its box,
  under the ❤/⚔ row (which was shrunk and dropped onto the box's bottom edge so
  the art underneath stays readable). Every pip carries `StatusData.tooltip_for`,
  the one place a status's hover text is built, so the board, the enemy card and
  the HUD chip cannot disagree about what a status says.
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
- **Editing the sheet** — `tools/_statuses_sheet_setup.py`,
  `tools/_statuses2_combat_setup.py` (the combat columns, §13.4) and
  `tools/_items2_statuses_setup.py` go through `tools/_xlsx_surgery.py`, which
  rewrites one sheet's two XML parts and copies every other zip entry through
  untouched. An openpyxl round-trip of this workbook silently drops its seven
  charts, so nothing here may use one.

### 13.4 The combat side

A status started out as goals and nothing else — it never touched a number on the
board. It touches four of them now, authored in the `Combat` / `EnemyOnly` /
`Enemy Combat Effect` columns and parsed onto `StatusData.combat`:

| Clause | What it does |
|---|---|
| `damage_dealt +{X}` | this body's hits land for X more (Strength) |
| `damage_taken +{X}` / `damage_taken x2` | hits on this body land for more (Marked) |
| `shield +{X}` | applying the status grants X shield points (Dexterity) |
| `tile_move +{X}` | this body closes X extra columns per step (Speed) |
| `pierce_shields` | damage aimed at this body ignores shields outright (Marked) |

Three rules hold the side together:

- **Additive fields scale with the stack count; multipliers do not.** Marked
  doubles at one stack and at four. A doubling that compounded per stack would
  turn a board where a hit is worth 1 into one where it is worth 16, off a status
  the player never chose to stack.
- **`EnemyOnly` is what Buff/Debuff always meant.** Every buff sets it, because
  Strength on the player would want a player attack to sit on and this game has
  none. Every debuff clears it, so **a debuff is felt by whoever is carrying it**:
  Marked on the player doubles the damage they take and takes it straight past the
  Shields — the tries — they were counting on to absorb it.
- **Shields are a POOL the status hands out, not a reading of the stack count.**
  Dexterity 2 grants two shield points; each absorbs one damage and is gone. The
  body still has two Dexterity stacks afterwards (its goal clause is unchanged) and
  no shield left, which is why `shield` is saved on the board entry beside
  `health` rather than recomputed from the statuses on load.

Every number goes through **one** function per side.
`StatusData.combat_totals(held, which)` aggregates a holder's statuses — bonuses
sum, multipliers multiply, flags OR — and both holders call it:
`GameLoop2.enemy_combat(entry)` for a body, `GameState.combat_totals()` for the
player. `GameLoop2._damage_enemy` is the only place a hit on an enemy resolves (a
met goal, a bomb and a scroll all land there) and `GameLoop2._take_hit` is the only
place damage reaches the player, so there is nowhere for "does Marked pierce?" to
be answered twice.

---

## 14. Currency & shops (`gold`, hub shops)

Gold is what the drops were never allowed to be: a reward you **choose what to do
with**. Every other payout in the run is a thing arriving — an item off a corpse,
a chest off a level-up — and the player's only say is take it or leave it. Gold
banks that decision instead, and the shops are where it is spent.

### 14.1 The numbers, and why they are this small

| | |
|---|---|
| Enemy defeated | **+1 gold** |
| Boss defeated | **+3 gold** |
| …while the **Golden Idol** is held | **+1 more** off every body, boss or not (§8) |
| Starting purse | the character's **`Gold`** column (**3** across the roster) |
| Item price | **3 + the rarity's rung** — Common 3, Uncommon 4, Rare 5, Legendary 6 |
| Carries between runs | **No.** A run opens on the character and nothing else. |

A run is 6–12 games, so a player clearing most of their goals earns roughly
**8–15 gold** and can make **two to four purchases in a whole run**. That is the
point of the scale: at combat-era numbers (gold started at **99**, the Challenge
Rift paid **50**) a price is a rounding error, and every purchase is automatic.
At these numbers each one costs something. It also keeps every figure on the HUD
to a single digit, which §9's OBS companion window needs.

**Three gold to start** is exactly one Common item, so the first shop a run
reaches is always worth walking into.

**Gold rides the DROP, not the corpse** — it is paid inside the branch of
`GameLoop2._defeat` that grants the item. So:

- the current game's enemy beaten on time **pays**;
- a follower whose old goal you fulfilled games later **pays the same** — the
  goal was the price either way, and taxing a slow solve would argue against the
  stack the whole run is built on;
- a **bombed** enemy **pays nothing**. A bomb already drops no item (§4); it is
  an escape from a goal you couldn't or wouldn't do, and letting it mint currency
  would make bombing the cheapest way to farm the shops.

### 14.2 Where shops are: the ten hubs

A shop stands at each of the run's **ten best-connected games**
(`RunGraph.hub_ids`). On the full catalog those are the genre's landmarks — Slay
the Spire (141 connections), Vampire Survivors (85), The Binding of Isaac (69),
Hades and Balatro (46), Spelunky Classic (37), FTL (36), NetHack (29), Dead Cells
(28), Enter the Gungeon (26) — and the degree curve has a real shoulder there,
with the eleventh game down in the low twenties and a long flat tail behind it.

Hubs are measured **after the game filter and the main-component prune**, like
every other degree question, so an OWNED run's ten are the ten biggest games on
the map that run is actually walking.

**This is a second routing axis, and it is deliberately the opposite shape to
events.** An event (`docs/event-sheet-authoring.md`) hangs off a **dead end**: a
two-game round trip for one game's reward, which is why it needs a badge to be
worth taking. A hub is the **middle** of the map — rarely far off the road — so
"swing through the big node" is a cheap, repeatable decision rather than a
committed detour. Until now every step was measured against one question (does
this take me closer to the Amulet); this is the second one.

The ten are **frozen at run start** onto `GameState.hub_games` and saved.
`RunGraph.hub_ids()` is a live read and the graph can be rebuilt underneath a run
(the game filter does exactly that), so re-asking is not guaranteed to give the
same answer — and a shop appearing or vanishing mid-route would make the flag on
an offered card a lie, which is the thing every badge in this build is designed
around.

### 14.3 The shelf

**Three items, and they stay.** Stock is rolled once — on the standard
75/20/5-with-a-10%-bump ladder (`Data.roll_item_rarity`) — and **persists for the
whole run**. Buying marks a slot sold rather than removing it. So a hub you
cleared out is a hub you know is empty, and a hub you left two items at is a
reason to come back.

Two preferences shape the draw, both aimed at the same problem — 21 authored
items against a run that already gets one free per defeated enemy: **no duplicate
slots**, and **items the player doesn't already own are preferred**. Both are
preferences rather than filters, and fall back rather than leaving a slot empty.

**Rerolling costs 1 Scramble, not gold.** Scramble is the run's reroll verb
everywhere else (§4 — "re-draw the offering"), so a shelf of three things you
don't want is the same kind of problem as an offering of three games you don't
want, and takes the same answer. Pricing it in gold would let a rich player grind
the whole catalog at one hub. A reroll redraws **all three slots, sold ones
included** — the generous reading, and the right one, because gold is the real
limiter and three fresh items you still can't afford is not a windfall.

### 14.4 When it opens, and what the road can see

The shop appears **after the hub's game is beaten**, queued behind the board's
resolve playback on the same path an event takes (`Overworld2._pending_shop`) —
and it appears **on the page, under the battlefield** (`ShopPanel2`), not as a
modal over it. A shop is not an interruption: the run's rhythm is report the
game, see what it cost you on the board, choose where to go next, and a
full-screen shop dropped into the middle of that stopped everything to ask a
question the player had not asked yet — while covering the board and the offering
the answer depends on. Mounted under the board it blocks nothing, stays for the
whole visit (travelling on is what closes it), and is read next to the run it is
being spent on. Because it can sit below the fold, a **`🛒 Shop ↓` pointer**
floats at the foot of the screen until the panel has been scrolled to.
**Escaping opens nothing** — escape fires no `game_beaten` triggers anywhere in
the build, and this is not the place to make it an exception.

**Lord's Parasol resolves the moment you stand in one.** The Boss relic (§8)
sweeps the whole shelf into the pack for **no gold** — not "buy everything you can
afford", which would make it weakest exactly when the shelf is best and would read
as a discount rather than as a relic. It fires from `ShopSystem.mark_seen`, behind
the `seen` guard, so it is the *first* visit to each hub that empties it and a
rerolled shelf on a return trip is not swept a second time. If the Amulet game
is itself a hub, winning the run beats the shop: the run is over.

**A hub pays no event — the shop is what happens there.** An event fires after
every other game played (§12), and for a while a hub paid both: the shop mounted
under the board and the event opened a modal over it, so the shop the player had
routed towards was something they had to dismiss an event to reach. Two things
queued on one arrival was one thing too many, and of the two the shop is the one
the player chose to be standing in. `EventSystem.roll_for_arrival` returns null
at a hub, so the rule holds for every caller rather than for the overworld only.
It reads off the game actually PLAYED at the node: a transmuted spot plays an
off-map game, off-map games are never hubs, so the shop leaves with the game it
belonged to and the spot goes back to paying an event.

From the road, a hub card carries a **`🛒 SHOP` flag**, the only flag ranked
below the Amulet — and its tooltip says the shop is *instead of* an event, which
is the one way a hub costs differently from every other card. Its
colour is a **green**, not a gold — the flag occupies the Amulet's own slot on
the card, so it has to be a different colour rather than a different shade
(`UITheme.SHOP_GREEN` / `COIN_GOLD`).

Opening the card shows the shop block, and this is the part that makes the
mechanic route: **a shop you have already stood in lists what is still on its
shelf and what it costs.** A shop you have *not* visited says only that one is
there — the stock is what the first visit is for, and drawing a card must never
decide what is in a shop the player hasn't walked into (`ShopSystem.peek` exists
so the offering can ask without rolling). `ShopSystem.headline` / `stock_lines`
are the one place a shop is put into words, so the card's tooltip and the popup's
block cannot disagree — the same rule `StatusData.tooltip_for` follows (§13.3).

### 14.5 What is still to come

**The shopkeepers.** `data/encounters/` already carries two combat-era ones (P
Mart's Tracy from Mewgenics, Trorc from Enter the Gungeon) with pools and
discounts. A `shopkeeper` field is read by `ShopPanel2` and falls back to the
hub's own game name, so an authored roster drops in without reshaping anything.

**A wider stock.** Today a shop sells items only. The obvious next step is the
things drops *don't* give — bombs, scrolls, verb charges, health, an extra try —
so gold buys a different axis rather than a slower version of the same one.

---

## 15. Objects (`objects2.0`)

An **object** is a machine you stand in front of. Full authoring spec:
[`docs/object-sheet-authoring.md`](object-sheet-authoring.md).

It is the same authored shape as an event — one row, a prompt, choices in
numbered column groups, Effect cells in the shared reward DSL, resolved by the
same `EventSystem` calls — and it is a separate kind for three reasons:

- **an event is a room; an object is a thing in the room.** An event opens, is
  answered, and is over. An object stands in front of you for as long as the run
  is on that game, and **travelling on** is what ends it.
- **an object is spawned.** Events arrive on their own after every game. Objects
  are put in front of you — by an event (`spawn_object tag=arcade 2-3`), or by
  anything else — and **several can be there at once**.
- **an object is stateful.** It jams, it gets blown up, and the Donation
  Machine's bank outlives the run entirely.

### 15.1 Where one draws

Two places, and which one depends on what spawned it:

- **spawned by an event** → inside that event's modal. The Arcade Room *is* the
  room the cabinets are in, so they are laid out in there with you and the
  room's own `Leave` walks you out of both.
- **spawned by anything else** → under the board, in the space a hub's shop
  takes (`ObjectPanel2`, §14.4). Same argument as the shop: the run's rhythm is
  report the game → see the board → choose where to go, and neither a shop nor a
  machine may interrupt it. The one difference is what survives leaving — a
  shop's shelf persists on `ShopSystem` so coming back is a real option, and a
  machine simply ends.

A machine's buttons are **drawn and greyed** when unavailable rather than
dropped, which is the one place an object's UI deliberately departs from an
event's. An event's options are a list of things you may do; a machine is a
physical object, and its buttons do not vanish because you cannot afford them.
The refusal goes on the button — **"Jammed"**, **"Full"**, **"Needs 1 Bomb"** —
because the reason is the whole of what the player wants to know.

### 15.2 The two machines

**Blood Donation Machine.** No prompt — it keeps Isaac's silence. Pay 1 Health
for 1 Gold, as often as you can pay, with a **6.7%** chance per press that it
bursts and pays a Blood Bag or an IV Bag instead of the coin. Or spend a Bomb
for **2-4** loose pickups, each independently a heart or a coin. Either ending
destroys that machine; another may still turn up.

**Donation Machine.** Gold in, and it does not come back out — the bank is
**persistent across runs** (`GameStats`), holds **999**, and is the only number
in this build deliberately not about the current run. Each coin rolls **5%** for
a point of Luck and **{1+X}%** to jam, where X is coins already in this visit —
so the jam chance climbs 1%, 2%, 3%… while you stand there and resets when you
travel on. A jam is permanent for the run; a jammed machine still turns up and
takes nothing. Bombing it pays **2-5** gold out of the bank (capped at what it
holds) and takes **every** donation machine off the run.

### 15.3 What is still to come

**A way for an object to stand on the map in its own right.** `ObjectData`
carries `where` / `requirement` / `trigger` — the same three an event gates on —
and nothing reads them. When something wants a machine that is simply *at* a
node rather than spawned into it, that is the seam, and the under-board panel is
already the place it would draw.

---

## 16. Luck

**Every point of Luck buys one more roll, and the better result is kept.**

That is the whole model, and it reaches every random decision the run makes. At
1 Luck a 25% chance is really 43.75% (`1 - 0.75²`); at 3 Luck, 68%. It compounds
rather than adding. Negative Luck is the same machine reversed — `|Luck|` extra
rolls, keep the worse — so −2 puts that 25% at 1.6%.

It replaced a 10%-per-point chance of *advantage*, which at a single point did
nothing at all nine times in ten. That is not a tuning difference: the old Luck
was a stat you could hold for a whole run and never observe.

### 16.1 Direction is declared, never assumed

A reroll only means something when the roll has a side the player wants, and
most rolls do not say so on their own. So every call site names its direction
(`Stats.Favour`), and the ones with no honest answer opt out:

| | |
|---|---|
| `HIGH` | a bigger number or a success is wanted — the rarity ladder, a chest gamble, how many pickups a bombed machine scatters |
| `LOW` | success is the bad outcome — the Donation Machine's jam, Curse of Decay's item downgrade |
| `NONE` | there is no better side — *which* of the twelve Commons you drew, whether a burst machine dropped a Blood Bag or an IV Bag |

The case that reads backwards: the Blood Donation Machine's 6.7% explosion is
`HIGH`. Bursting pays an Event relic where the loss pays one gold, so Luck makes
the machine *more* likely to go off in your face.

### 16.2 Where it lives

`Stats.roll_chance` / `roll_range` / `roll_rarity_step_with_luck` are the entry
points. `Data.roll_item_rarity` calls the last of them, which is what makes
"Luck affects every roll" true without thirty call sites having to remember it —
item rewards, chest sizes, scrolls, shop stock and the object pools all walk that
one ladder.

Odds shown to the player are the odds **Luck will actually roll**
(`Stats.effective_chance`), not the number on the sheet. A button that said 6.7%
to a player holding a Clover would be lying to them about the thing they bought
it for.

Luck comes from the **Clover** (Uncommon, `+1` as a passive bonus, so it goes
away with the item) and from the Donation Machine's 5% roll. There is no cap.
