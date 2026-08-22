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
| Shields | granted per game, **no cap** | **The ARMOUR the game you selected granted** (see §3.2). Each one stops **one whole instance of damage**, however big, before `health` is touched — and they **expire with the game that granted them**. Losing a run does not spend them. |
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
selected, gain +1 Shield"), and future tag routes / scrolls. **Bonus Shields**
(§4.3) are the one pool that is *not* per-game: gained off the board from a pill
or banked out of a resolved game by Barricade, spent after the per-game shields
are gone, and carried until something breaks them.

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

### 3.2 Shields, and the attempt tracker

These were one mechanic and are now two, which is the whole of this section.
Losing a run of the real game moves the **board**; shields are **armour** and
nothing but armour.

**A LOST RUN GIVES THE ENEMIES A TURN.** Every run of the game in play you lose
is one tick of the attempt tracker, and a tick costs exactly one turn of the
board — the same `_resolve_enemy_turn` a reported game takes `enemy_turns()` of
(§7.4): the ground burns whoever is standing on it, every body touching the front
column **strikes** for what its statuses make of its damage, everything behind it
**steps a column closer**, and a stun costs one turn of either. It can kill —
Health reaching 0 ends the run right there, exactly like an enemy hit at the end
of a game.

- **There is no limit on how many times you may fail.** What there is, is a board
  that is one turn closer every time you do. The cost compounds where it should:
  the board a tick moves is the board the *next* tick moves again.
- **Nobody holds their fire**: the goals-met exemption is a fact about a
  *reported* game, and nothing has been reported yet.
- **A board with nothing in reach charges nothing**, and that is the design
  rather than an oversight: the turn *is* the cost, so a cleared stack has
  nothing to take and a body still walking in merely walks. The tick is still
  logged — it is what the escape hatch counts and what the tracker shows.
- **The undo is a restore, not a refund.** A turn walks bodies, burns ground,
  breaks the trinkets that break on a hit (§8.1) and pays out whatever losing
  Health pays out, so `GameLoop2.log_attempt` snapshots the board and the run's
  resources before it resolves and `undo_attempt` puts the whole thing back.
  Those snapshots are **runtime-only** — a save carries the run, not its undo
  history — so a turn taken before a reload cannot be taken back, which
  `can_undo_attempt` answers and the undo button reads off.

**A SHIELD STOPS ONE INSTANCE OF DAMAGE.** The whole of it, whatever its size: a
3-damage swing breaks one shield and lands for nothing, and so does a 1-damage
one (`GameLoop2._take_hit`).

- **Selecting a game grants them** — **3** for any game, **5** for a
  **Traditional** roguelike (the long haul); nothing else moves the number, so it
  reads straight off the game's type. Items hooked on *"when a game is selected"*
  add to the grant, which is what **Anchor** now does (+1 Shield): the extra cover
  has to arrive *before* you go and play. The grant is part of the routing
  decision, so it's stated in the game's popup (§4.2) and on the card's hover
  line.
- **A block, not a point.** That is deliberately blunt, and it is what makes the
  pool readable: three shields is three hits you don't take, and the arithmetic of
  "which hits do these five points cover" never has to be done. It also makes a
  big hit the one you *want* a shield to meet — the same shield spent on a chip
  hit is the worse trade, which is a thing to play around (a Push, a Stun) rather
  than a sum to do.
- **Any instance of damage**, whatever threw it: a follower's swing, Burn's "take
  3 Damage" bill at the end of a game (§13), a `take_damage` effect from anywhere.
  They all funnel through `_take_hit`, which is the only path damage reaches the
  player by. A **`lose_hp` bill** — an event's price, a machine's lever — is not
  damage and never was: it does not come through there and shields do not stop it.
- **Marked pierces.** A debuff is felt by whoever carries it, so Marked on the
  player doubles what lands *and* takes it straight past the shields (§13.4).
- **Enemies read the same rule.** A Dexterity stack gives a body a shield, and
  that shield eats one whole hit (`_damage_enemy`). Every hit in this game is
  worth exactly 1 today, so it changes nothing right now — it is written that way
  so both sides of the board answer "what does a shield do" identically the day
  something hits for more.
- **They expire when you report the game.** Shields never bank into the next one
  on their own: an easy game cleared first try does not arm you for the next.
  **Barricade** (§4.3) is the exception, and it banks the survivors into Bonus
  Shields rather than stopping the expiry.

The tension is *don't lose runs → the stack never moves, and the wall is still
whole when you report.* A game cleared first try leaves the board where it was and
the whole pool standing; a game that fights back walks the stack into your face
and then makes you report from there. **Health is meant to be hard to reach while
you're playing well** — the followers' 1–3 damage is a threat to a player who is
already having a bad time, not to one who isn't.

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
| **Transmute** | **Turn a game into a random game of the *same game type* that is *not connected to the map*.** (New verb — this is the "replace with a fresh game" role bash used to have, now type-constrained and pulling from off-graph games.) **Traditional is the exception**: it transmutes into a random game of any *other* type, drawn flat from the non-Traditional catalog. A Traditional roguelike is the run's long haul — it grants 5 shields rather than 3 — so swapping one for another is no relief, and the verb has to be able to get you out of the type. |
| **Dash** | **As in the current project: a total select, not a skip** — pick *any* connected game and move to it (bypassing the normal limited offering). Costs 1 dash charge. See `Overworld._try_dash`. **Earned by going back**: beat a game **this run has already played** — cleared, failed, or walked away from — and it pays **+1 Dash** (`Overworld2._grant_repeat_dash`). The trip back is what earns it; the goal still has to be met on the return. The offering flags such a card with `⚡ +1 DASH`. |
| **Scramble** | **Reroll the offering** — re-draw the games filling the (base three) choice slots, each with a freshly-rolled enemy/goal. At a node with no spare neighbours the slots hold and only the enemies change. Granted by the **D6** item. |
| **Push** | **Shove a following enemy one cell, in any cardinal direction.** Spends 1 push charge. *Back* is the classic use — delay its next attack by a game (§7.2), riding the same per-enemy delay counter as Stun but player-triggered. *Up / down* is a **lane change**, the one move enemies can never make for themselves, so it is how a blocked lane is opened or a clear one is plugged. *Forward* is legal too, and the player's own business. The verb is armed first and aimed second: press **⇤ Push** on the board's toolbar, click the enemy, then pick one of the arrows that appear on every side it could actually move to. Nothing is spent until an arrow is pressed. The **Manager**'s signature verb (gained on level-up: "Collect 3+ different types of currency" → +1 Push). |

### Consumables
| Item | Effect |
|---|---|
| **Key** | Unlock a new game path (blocked edge / unconnected "wild" game). *(No 2.0 content grants keys yet — see open questions.)* |
| **Bomb** | Deal 1 damage to an enemy. Normal enemies have **Health 1** (`enemies2.0`), so one bomb removes one (no item drops). A **boss is a legal target but takes no bomb damage** (§7.1) — the charge only buys what an item hangs off the throw. Three items change what a bomb does: **Brimstone Bombs** widen the blast to the target's whole row *and* column, **Sticky Bombs** stun whatever the blast fails to destroy (in practice, bosses), and **Blood Bombs** pay +1 Health per bomb via the `bomb_used` trigger. **A bomb is aimed at a SQUARE, not only at a body** (`GameLoop2.bomb_cell`): every cell of the board lights up when the verb is armed, and an empty one is a legal target — which is how **Hot Bombs** lays fire in front of the stack and how **Brimstone** is aimed down a lane rather than off whoever happens to be standing in it. A click on an occupied square still routes through the body-aimed path (`GameLoop2.bomb`), so the target reaches the blast, the boss rule and the `bomb_used` trigger unchanged. |
| **Scroll** | Consumables with an identity that starts **unidentified** and a **Preference** (Positive / Negative / Neutral). See §4.1. |
| **Pill** | The same gamble held by a **colour** rather than by a type, with an oversized **horse** dose behind a 5% roll. See §4.3. |

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
| Fire | Negative | **+3 Burn on you**, and +3 Burn on every enemy in the front column (§13). |
| Identify | Positive | Choose 1 scroll to identify. |
| Scare Monster | Positive | Choose 1 enemy to **Stun** (see below). |
| Teleportation | Neutral | Teleport to a random space ~the same distance from the Amulet game (±1). |

**Fire is the first scroll that points both ways**, and the first whose `Effect`
cell is two clauses rather than one: `apply_status burn 3 player;
apply_status burn 3 front`. Semicolons separate clauses here the same way they do
in every other sheet's Effect column, and the two targets it needed are new —
`player` is the reader, `front` is everything touching the column that strikes
next (the same `in_front` test the strike itself uses, so "about to hit me" and
"what this lands on" are one list). It is read for its second half: the bodies in
your face come down to half damage and grow a cheap way out of their goals. Its
first half lands whether or not the room has anyone in it.

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

Scrolls are carried, and since pills arrived they are carried **with the pills**:
both live in the loot window described in §4.3 rather than as tokens on the pack
strip. The strip was the right home while a scroll or two was all there was; a
nine-piece pack of loot beside a run's relics is not a strip, and splitting loot
across two places to keep the old shape would be worse than moving it.

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
- the **game**: cover at full size, type and year, the **shields** it grants (§3.2),
  what taking it does to the board's **pace** (§7.4), whether going back to it
  pays a Dash (see below), and the player's own record in it;
- the **enemy waiting there**: portrait, name, and the goal as it would actually
  be played — the player's own status clauses included (§13) — plus which enemies
  on the board have already been beaten *at this game*;
- and the three things that can be done about the card: **Travel**, **Bash**,
  **Transmute**. Bash and Transmute only appear when there is a charge, and the
  Amulet's card never offers a Bash (§4).

### 4.3 Pills (`pills2.0`)

Pills are the **second loot consumable**, and they are the scroll's identification
minigame moved off the *type* and onto a **colour**. A scroll's mystery is one
shared Unidentified art and a name you learn by reading it; a pill's is thirteen
distinct coloured capsules, ten of which mean something this run and three of
which mean nothing at all — so learning a pill is learning *this run's* alphabet
rather than a fact that was always true.

| Pill | Preference | Effect | Horse Effect |
|---|---|---|---|
| Luck Up | Positive | +1 Luck | +2 Luck |
| Luck Down | Negative | −1 Luck | −2 Luck |
| Telepills | Neutral | Teleport ~the same distance from the Amulet (±2) | Teleport to a space **1–3** from the Amulet |
| 48 Hour Energy | Positive | +3 charges, each landing on a random chargeable relic | Fully charge 3 random chargeable relics |
| Health Up | Positive | +2 Max Health | +4 Max Health |
| Health Down | Negative | −2 Max Health | −4 Max Health |
| Bad Trip | Negative | −2 Health | −4 Health |
| Full Health | Positive | Heal to full | Heal to full, +3 Bonus Shields |
| Balls of Steel | Positive | +2 Bonus Shields | +4 Bonus Shields |
| Amnesia | Negative | A random curse goal (§5) | A random curse goal, and forget every identified loot — **itself included** |

**The colours.** `images2.0/pills/` ships **13 colours**, each with a horse twin
(`<Colour>.png` / `<Colour>Horse.png`). A run binds **10 of the 13** to the ten
pills and the other **three sit out** — they never drop, and next run the whole
mapping is redealt. This is `potion_color_map`'s pattern (§4.1's sibling), and the
three spare colours are the reason a pill can't be deduced by elimination: nine
known colours do not tell you what the tenth is.

**Horse pills.** Every pill that drops rolls **5%** to arrive as the horse dose
instead — the colour's oversized art, reading the row's Horse Effect. It is a roll
per *drop*, so one colour can turn up both ways in a run. **Identification belongs
to the colour, not to the dose**: take either one and both are known from then on,
in both directions, and an identified colour's card shows what each dose does.
Because the art is visibly oversized, the player always knows a horse pill is a
horse pill — what they may not know is what colour means.

**And the UI has to actually draw it that way.** For a long time it did not: every
surface fitted loot art into a *fixed* box (`UITheme.crisp_tex`), which renders a
19px capsule and a 25px one at identical size, so the one tell the design promises
was being scaled away by the thing drawing it. Loot art is now sized through
`LootSystem.art_tex` / `art_box`, which asks `PillSystem.art_scale` how much bigger
this dose's own file is than the normal dose's — **measured from the art rather
than hardcoded**, so redrawing the horse capsule bigger makes it draw bigger. In
the grid the art sits in a band tall enough for the largest dose, so an oversized
capsule fills more of its cell without making its row taller than the other two.

**A pill says what it would do to you right now.** Bad Trip's dose is lethal at
low Health, so it does the one thing a Negative pill never does: at or below its
own damage it **heals to full instead**, and it *names itself* accordingly — an
identified Bad Trip colour reads **Full Health** while you are in death range and
**Bad Trip** the rest of the time. The label follows the current Health rather
than the pill, which is why two colours can both claim to be Full Health.

**Bonus Shields.** Shields can now be gained **outside a game** (Balls of Steel,
horse Full Health), and those are a separate pool from the per-game shields of
§3.2:

- They are drawn **closest to the player** — nearest the portrait on the board's
  hero, and beside the always-visible Health chip in the header, because a pool
  gained on the overworld has to be readable when no board is on screen.
- They are **spent last**: a hit breaks one of the per-game shields first and
  only reaches these once those are gone (§3.2). A lost run spends neither — it
  costs a turn of the board and nothing else.
- They **never expire.** The per-game pool dies with the game that granted it;
  a bonus shield stays until something breaks it, which is what makes it worth
  saving across several games.

**Barricade banks into that pool.** The relic used to stop the per-game shields
expiring, which quietly made them a second non-expiring pool with its own rules.
It now **converts what a resolved game left standing into Bonus Shields**, so
there is one pool that persists and one relic that fills it. That is a small buff
— banked shields are spent last too, where the old behaviour spent them first —
and it is the right one: the relic is about the cover you *didn't need*.

**Where pills come from.** **Beating a game pays 1 random piece of loot** — a
straight 50/50 between a scroll and a pill, and the run's baseline loot income.
It is paid for any game the player actually saw through: **walking away from a
game pays nothing**, and it is **on top of** whatever the enemies defeated there
dropped, not instead of it. It arrives the way a kill drop does — the same asked
modal, one queued behind the other — rather than as a toast, because with a
**nine-piece cap** on the pack, taking a piece of loot is a decision.

Four relics move that number:

| Relic | | |
|---|---|---|
| **Mom's Coin Purse** | Common, Pickup | +4 Pills, once, on pickup. |
| **Mom's Bottle of Pills** | Common, Charged 2 | +1 Pill per firing. |
| **Caffeine Pill** | Common, Passive + Pickup | +1 Speed **while held**, +1 Pill **kept** — the split is the point: lose the relic and the Speed goes with it, but the pill was already spent into the pack. |
| **Lucky Foot** | Uncommon, Passive + Pickup | +1 Luck while held, +1 Pill kept, and a **Negative** pill taken while it is held **rerolls into a random Positive pill** rather than being swapped for a fixed opposite. Neutral pills are untouched — Telepills is not an upgrade waiting to happen. |

**What Lucky Foot does NOT change is the alphabet.** The reroll is flat across the
five Positive pills — including the ones whose colours are sitting out this run,
since the roll is over the *pills* and not over what dropped — and a Negative
**horse** dose rerolls into the **horse** dose of the same pool. But the colour
still identifies as **what it actually is**: take an unknown colour that was Luck
Down, gain Luck instead, and the colour is now known as Luck Down. The Foot
changes the outcome, never the fact, which is the only version of it that stays
honest when the relic is lost.

**The loot window.** Nine pieces of loot will not fit in the pack strip beside a
run's relics, so loot moves off it into a window of its own: a **Loot** button at
the **head** of the pack strip — the count, and a peek at the first few capsules —
that opens a **3×3 grid** of what is carried, each cell its art, its name, its
**Preference** and a **Use** button, and each carrying the same hover card an item
or an enemy gets.

**The toggle is the pack panel's foot** — a full-width bar under the relics rather
than a button beside them. It has now been in three places and the first two were
each wrong in their own way: at the *tail* of the relic row it sat underneath the
notification toasts (a right-anchored column drawn over the page) and was hidden
for most of every report; at the *head* of that row it was clear of them but ate
the left end of the strip the relics wrap into, which costs a relic tile a whole
row the moment the pack gets long. On its own row it costs the relics no width at
all, and being full width it is a **bar**, which is the shape a "the rest of what
you are carrying is through here" control should have had all along. Its contents
pack to the LEFT and its right half is deliberately empty — that end is where the
toasts cross the panel.

It is deliberately **thin** (`LootWindow.TOGGLE_H`), and the pack panel's own
padding was trimmed to pay for the row it added: the page is fitted to a 720p
canvas with about five pixels to spare and
`test_the_page_still_fits_the_window_*` fails at +2, so those numbers are load
bearing. It also wears **red at 9/9**: a full pack turns the next payout into "leave it", and the moment to know
that is before the drop asks. **Tab** opens and shuts it — the `backpack` action
had been sitting in `project.godot` with nothing on the overworld listening for it,
and the loot window is both the surface a run opens most often and the only pack
surface that has to be opened at all. It is ignored while a drop modal or a card is
up, where the pack behind them is not what the key is about.

**The cell is bigger than a relic's token, and that is the correction.** Loot tiles
were drawn at exactly the pack strip's 34px on the reasoning that a pill and a
relic are both "a thing you are carrying" — right about parity, wrong about where
parity is measured. In a strip of twelve tokens 34px is the size that fits; in a
panel with 240px of slack it is a debug widget, with 9px names under it, smaller
than any other type on the page. The cell is now 48px of art in a 66px band with an
11px name, and the name reserves **two lines whether it needs them or not** — a
one-line name used to pull its Use button above the two-line names either side of
it, which made a full row read as broken.

It is **shut until the button is pressed**, and when it opens it opens as a panel
**over the board**, centred on the battlefield directly under the toggle that
opened it. Not as a row inside the pack: that grew the pack panel downward, which
pushed the board and re-flowed the right column every time the player looked at
what they were carrying — the window cost the page a relayout for the crime of
being opened. The board is the right thing to cover, and for two reasons: the
pack strip stands on top of it, so the window drops out of its own button rather
than appearing across the page from it; and the board is a picture of what is
chasing you, which does not change while you decide which pill to take — where
the offering on the left is the decision you may be taking the pill in order to
make. It **follows the board** as the page settles under it, rather than being
placed once.

**The grid is always nine.** Nine is the cap, and an inventory that draws only
what is in it says nothing about the room left, which is the fact the cap makes
interesting — so the empty slots are the count. They are also what keeps the thing
a *grid*: three tiles in a 3×3 read as three of nine, while three tiles in a row
that wraps read as all there is. **Nine is the cap** for now; a tenth
piece has nowhere to go, which is what makes the drop modal's "leave it" a real
answer. Scrolls live here too — one window for loot means one place to look, and
the pack strip goes back to being the relics.

**The grid is the thing you handle, not just the thing you read.** A piece can be
**dragged from one slot to another**, and the piece a game pays out is **dragged
into the slot you want it in** — see the drop modal below. Clicking a piece opens
its **card** (`LootInfoCard`), the twin of the relic's: a relic answered a click by
opening its card and a pill answered a click with nothing at all, which is the same
class of object with two different gestures, and the one that did nothing was the
one whose entire subject is *what is this*. So: **click reads, drag moves, the
button spends** — and the card's own Use goes back through the same `use_loot`, so
there is one spend path and inspecting a piece can never cost you one.

**What an arrangement is allowed to be: any of them.** A piece goes wherever it is
dropped — onto another piece, which **swaps** the two, or onto **any empty slot**,
which moves it there and leaves the slot it came from empty. A pack with a hole in
the middle of it is an arrangement somebody wanted, and a grid that quietly closed
the hole up was refusing to be tidied.

This used to be the one thing the grid would not do, because a slot *was* an index:
`GameState.loot_items` is dense and its indices are what `use_loot` and
`remove_loot_at` are addressed by, so an arrangement had to be one a dense array
could hold and a piece dragged into the far corner slid back to third place. The
array is still dense — **it is pickup order**, which is what `loot_scrolls()`, the
kind-blind drops and the toggle's peek all read — and the **slot rides on the entry
instead**, as `pack_slot`. `GameState.loot_layout()` is the one place the two are
put back together: slot → index, or −1 for a free slot. So nothing in the loot code
had to learn about holes, the save carries the arrangement for free (it is a key on
an entry that was already being serialized), and a piece with no slot of its own —
anything `add_loot` grants, anything from an older save — takes the lowest free one
in pickup order, which is exactly what the dense array used to do.

The grid redraws from that layout afterwards, so where a piece lands is where the
*run* says it is rather than a position the view is remembering on its own. And
what follows the cursor is **the whole cell** — the same border, art and name the
slot draws — rather than the bare capsule, which read as the art coming loose from
its tile and gave the player nothing to line up against the slot they were aiming
at.

**LOOT IS SPENDABLE WHENEVER YOU WANT IT.** The mid-report lock holds the pack
*still* — nothing dragged, taken or binned between "played the game" and "said what
happened", because that gap is not a moment for the inventory to move — and it used
to hold spending too. That was the wrong rule twice over. Mid-game is exactly when
a player knows what they want out of a piece: the body walking toward them is right
there, a Scare Monster or a Scroll of Fire is the answer to it, and an unknown
capsule is a gamble they are taking *because* of what is on the board. Being told
to finish their paperwork first is the run refusing the thing it wants them to
risk. Scrolls were held back further still, by an overworld-only rule of their own
(`GameState.can_use_scrolls`), on the reasoning that Teleportation only makes sense
on the map.

**So the answer is a fizzle, not a refusal.** A Use button that will not press is a
worse thing than an effect that lands on nothing: it teaches the player the piece
is unusable rather than that this *moment* is wrong for it. Only one op in either
roster genuinely needs the map — a **teleport** — and `Overworld2.loot_teleport`
returns nothing while `Phase.PLAYING`, so the use screen says the thing it already
knew how to say: *it fizzles, you do not move*. Every other scroll op lands
perfectly well mid-game: `apply_status` and `apply_tile` reach a board that is
standing right there, `spawn_enemy` and `stun_enemies` act on the stack about to
resolve, and `forget` and `identify_scrolls` never needed a map at all.

**And the piece is identified either way.** Both `ScrollSystem.read_scroll` and
`PillSystem.take_pill` identify *before* they apply anything, so a fizzle still
teaches you what the thing was — the gamble paid off even where the effect did not.
That is the whole reason a fizzle is an acceptable answer here and a refusal was
not: the player spent the piece and got the information they spent it for.

`GameState.can_use_scrolls` survives under its old name and now means only what it
always meant underneath: is there a map here to move on.

**The drop modal shows the pack — and the pack it shows IS the inventory**
(`LootDropModal`). A payout that arrives with a **report** is not a modal at all
any more: it is the right-hand column of the screen the game ends on (§18), which
is the same code embedded. Everything below is true of it either way. The 3×3 on the right is the same `LootGrid` the loot window
draws, with the same everything: pieces drag between slots, each carries the button
that spends it, clicking one opens its card, and the bin under it takes anything.
The only thing this screen has that the loot window does not is the offer on the
left — the bin and the "Known this run" fold come with it. It used to show the piece alone and say *"Your pack is full (9/9)"* in red
when it wasn't going to fit — a sentence about a thing the player could not see, on
the one screen where what you are already carrying is the whole basis of the
answer. Now the 3×3 comes with it, and the piece is **dragged into the slot it
should live in**, so taking it and placing it are one gesture and a pack with no
room says so by having nowhere to drop. The buttons stay — **Take it** puts it in
the first free slot, **Leave it** is still the answer the cap makes interesting —
because drag is the good gesture, not the only one, and a decision this final
should not depend on a drag landing.

**It asks about a HANDFUL, not only about one.** A game's own payout is a single
piece, but **Mom's Coin Purse is four pills at once** and Sacred Bark doubles what
a grant pays. A screen built around exactly one offer answered that by shovelling
the rest straight into the pack and **silently dropping whatever did not fit** —
which is the one thing the nine-piece cap exists to make into a decision. So the
offer is a **list**: one cell per piece, laid out two abreast up to four and three
abreast beyond that, each taken, used or binned on its own terms, and the screen
closes when the table is empty. Beyond three rows it scrolls rather than pushing
its own buttons off the bottom of the screen — a payout that cannot be answered is
worse than one you have to scroll. **Take** takes as many as still fit and leaves
the rest **on the table** rather than throwing them away.

Which piece is which matters here: four identical unidentified capsules cannot be
told apart by their entry, so a drag carries the **offer's index** alongside it
(`LootSlot.offer_index`) and the screen crosses off the one the player actually
moved.

**A grant of loot asks, too** (`GameState.offer_loot`, `EffectSystem._grant_loot`).
It rolls the pieces and hands them to whoever is listening — the page queues them
as *one* question behind the same drop queue as everything else — and falls back to
the direct `add_loot` when nobody is, which keeps it a pure state change on
headless runs, in `PlaySession2` and in the tests. A **negative** grant is a loss
rather than an offer (nobody is asked which pills to be robbed of), so it goes
straight through as it always did.

**This screen places its own takes**, which is the one place it departs from every
other drop. With several offers on the table, and uses and bins interleaved between
them, the slot the player chose is only meaningful at the instant they choose it —
one use later every index behind it has moved. So each offer is committed as it is
resolved, and `answered` reports the finished list for the page to log.

**And the pack it shows is a LIVE one.** Every piece on that screen can be spent
from it, the offered one included. A full pack used to leave exactly two answers to
a payout — leave it, or close the modal, go and spend something, and never get the
payout back — and only the first was on offer. So:

- **a carried piece has its Use button**, the same one the loot window draws, and
  spending it frees the slot the offer needs *in front of the offer*, which is
  where the decision is being made. The drop stays on the table while you do it:
  spending is not answering.
- **the offer can be used where it stands**, without ever being carried
  (`LootSystem.use_entry`). A Full Health that will not fit is not a piece of loot
  anyone should have to throw away, and "drink it now" is the answer every
  roguelike gives to a full bag. It costs no slot, so it is offered whether the
  pack is full or not — and it is a real use, so an unknown colour taken this way
  is **identified**, remembered, and echoed like any other. It resolves the drop:
  nothing entered the pack, so "taken" would be a lie and the page has nothing to
  collect.

The use modal opens on a **layer above** the drop modal (`USE_LAYER`) — a
`CanvasLayer`'s order is global, so a modal opened from on top of another has to be
told to clear it.

**A use ends by saying what it did** (`LootUseModal._show_outcome`). Taking a pill
used to close the modal the instant it resolved, which put the answer to *what did
that do to me* into the run log on the far side of the page — the one place the
player was not looking, having just been looking at the pill. On an **unidentified**
capsule that is the whole minigame: the reason to swallow an unknown pill is to find
out what it was, and finding out was happening off-screen.

So the piece gets one more screen, the same furniture as the intro said in the past
tense: the art, the name it turned out to have, its Preference now that there is one
to show, **what it turned out to be** when this use is what identified it (the
capsule is right there above the line, so the colour is named without the run ever
having to spell a colour out — see *Known this run*), **what it did** as the lines
the effect itself reported (the same ones the log gets, so the two cannot say
different things), and **where your Health landed** when it moved — `You lose 4
Health` is the size of the hit, and the number that decides what to do next is the
one left afterwards.

The **pickers come first and the summary last**: a request is part of what the piece
did, so a Scroll of Identify has nothing to report until you have chosen and a
Telepill has already moved you by the time it does. **Cancel is not a use** and
never reaches this screen. On the drop modal, a piece used from that screen now
resolves the drop when the outcome is dismissed rather than the instant it fires.

**Every piece has to have something to say, and three of them didn't.** The screen
can only report what it is handed, and `read_scroll` / `take_pill` return their
logs *before* a request has been fulfilled — so a scroll whose whole effect is a
request contributed no line at all. Three pieces came out of a use reporting
*"Nothing happens"*:

- **Teleportation and Telepills.** A teleport is the one op on either consumable
  that resolves nowhere near the system that owns it, so `Overworld2.loot_teleport`
  **returns** the sentence it logs, and it says the distance as well as the
  destination — *`spread` keeps you about where you were* and *`amulet` is the only
  move in the game that can drop you on the doorstep*, and a landing reported as a
  game's name alone is the half that doesn't say which happened.
- **Identify** and **Scare Monster**. `identify_scrolls_chosen` and
  `stun_enemies_chosen` return their line too, and both **name** what they touched
  — a scroll whose entire subject is *what is this* cannot answer with a count.
  Their `random` modes were silent for the same reason and now say the same thing.

`stun_worth()` — what a Stun costs its target at the run's current pace (§7.4) —
moved onto `ScrollSystem` so the screen that ASKS which enemy to stun and the one
that reports the answer quote one sentence rather than two.

**Echo Chamber's copies are named on the outcome, too.** The relic's replays merge
into the same `logs` as the piece's own, so a run holding it reads four pieces'
worth of effects — and, until the outcome screen said so, no account of where three
of them came from. The names are snapshotted *before* the use, since the use joins
that same memory as it resolves.

**The bin** (`LootTrash`). Spending a piece is not the same as being rid of one: a
pack holding three known-Negative pills is full of loot the run will never
willingly use, and *reading the Amnesia scroll to make room* is a worse answer than
throwing it away. So both surfaces that draw the grid draw a red zone under it, and
anything can be dragged onto it — a carried piece, or the offer, which is **"Leave
it" said with the hands**.

It **lights up the moment you pick anything up**, anywhere in the viewport
(`NOTIFICATION_DRAG_BEGIN`): idle it is a quiet outline that does not shout about
destruction on a screen nobody is discarding on, and armed it is the one red thing
on the panel. It is a drop target only — never a drag source, never a click — which
is the point of making drag the verb: you have to pick a specific piece up, carry
it across the panel, and let go on the red.

Binning a **carried** piece **asks first** (`LootTrash.confirm`), because it is the
one gesture on either screen that destroys something and gives nothing back —
spending a piece at least fires it — and a drag that ends on the red by accident
should not be able to cost a run its Full Health. The **offer** is the exception:
binning that is "Leave it", which is already a one-click answer. The confirmation
sits on **a layer of its own**, above both surfaces and owned by neither: the loot
window's panel floats with `top_level` set (so a confirmation parented to the page
draws *underneath* the thing it is asking about) and the drop modal rebuilds itself
when the pack changes (which would free a confirmation parented to it mid-answer).

Nothing can be spent or binned **mid-report**, on all three surfaces alike — the
report step is between "played the game" and "said what happened". In practice a
drop modal never opens in that state anyway: `Overworld2._open_next_drop` is
deferred precisely so the report has finished resolving before the question is
asked, which is why the offer can carry a Use button at all.

**What you have learned lives at the foot of the pack**, behind a folded *"Known
this run"* line — on **both** surfaces that draw the pack, since the reward
screen's right-hand side is the inventory and not a picture of one. It is one fold
(`LootDiscoveries.open` is static): shut in the window and open on the reward
screen would be two answers to one question. A pill's identity belongs to a **colour** and only for
**this run**, and until now the only place that knowledge ever existed was a toast
that had already scrolled away — so a player who learned that green is Bad Trip on
game three had nowhere to go and check on game eleven. That is the whole
identification minigame with no record of itself. The fold lists what has been
learned, with art and name and the same hover card, and **counts** what has not:
naming the unlearned colours would hand back exactly the deduction the three
sitting-out colours exist to prevent.

**Echo Chamber** (Rare, Passive) is the one that turns loot into a resource
worth hoarding: using a piece of loot also uses **a copy of the last 3 you used
since picking it up**. Isaac's rule, and Isaac's ordering — the loot you just used
enters the memory *after* the echo, so nothing echoes itself, and the echoed
copies do not themselves enter the memory. Its hover lists those three and its
card shows them with art and name (an unidentified entry there means the run
forgot something it knew, which Amnesia's horse dose can do).

**Sacred Bark stacks with all of it.** The Bark doubles every loot consumable
(§8), Echo Chamber multiplies the number of consumables a single use fires, and
the two compose rather than cancelling: one pill taken with both relics is two
doses of it plus three echoes at two doses each. That is deliberately a lot —
it is a Boss relic meeting a Rare one — and the Negative rows are doubled too, so
the pile it makes is only good if the alphabet is already learned.

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

**A boss cancels the ways out, and now it SAYS so.** A boss comes off the board on
its goal alone: bombs do nothing to one, and an `instead` clause riding it (§13 —
Burn's enemy side is the one in the roster) buys nothing.
`GameLoop2.claim_enemy_alternative` has always refused it and `alternatives_for`
has always declined to offer it, which meant a burned boss got **no row at all** —
the checklist drew nothing, the card drew nothing, and the tick that would have
cleared an ordinary body simply did not exist. Silence there reads as the burn
having failed to apply, not as a rule about bosses.

`nullified_alternatives_for` is the other half of that pair: the alternatives a
boss is *carrying and ignoring*. The checklist draws them as a read-only line
("nullified: a boss comes off the board on its goal alone"), the enemy card says
it on the chip, and the status's own hover and tooltip take a `nullified` flag so
the pip stops promising a way out and stops reading gold. The pip itself is still
drawn — the stacks are real and the player put them there.

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
back column, and from that moment it is an ordinary body on the board with **no
tie to the game that rolled it**: it takes its turns, it is drawn like the rest,
it can be bombed and pushed like the rest, and its goal is one row in the report
checklist among all the others.

**There is no "this game's enemy".** There used to be: `GameLoop2.current`
pointed at that body for the whole game, the board drew it in its own accent and
refused to aim a verb at it, the checklist gave it an emphasised **Goal —** box
at the top, and "did you beat the game" was the flag that cleared it. That is
gone. A card advertises what will walk on if you take it, and once it has walked
on it is a follower. `GameLoop2.arrivals` is only the record of which bodies came
with the game in play, kept so a Scramble can supersede them.

**Beating the game and clearing an enemy are two separate claims.** Pressing
**✓ Completed Game** says you played and finished the real video game — that is
what the run's beaten set, the repeat-visit Dash and the lifetime tally read.
What you did to the bodies is the tick boxes, one per enemy on the board.

1. **Spawn** — the enemy appears **on the back column** when you choose its game.
2. You play & **report**, and the resolve runs in this order: every goal you
   ticked lands its hit — bodies that walked on this game and bodies you have
   owed for ten, on the same terms — then every survivor takes its
   `enemy_turns()` actions.
3. So an enemy you ticked is **defeated before it acts at all**, and one you
   left unticked **starts walking during its own game** — reaching the
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

### 7.4 Amulet pressure — the enemies get bonus turns as you close in

The run has two difficulty axes. The tier ladder (§7.1) is the clock: it ticks
up on its own, every `GAMES_PER_TIER` games, and the player only rides it. This
is the other one, and it's the one the player **steers**.

**Every enemy takes one turn per game reported, wherever the run is standing.**
That is the floor and nothing moves it. What closeness to the Amulet buys them is
**BONUS TURNS on the end of the game** — taken after every enemy has had its own
— read off how far you are in hops over the run graph:

| Hops to the Amulet | Bonus turns | Total turns | Band |
|---|---|---|---|
| 5 or more | +0 | 1 | Distant |
| 3 – 4 | +1 | 2 | Closing |
| 2 – 0 | +2 | 3 | Doorstep |

A **turn** is one action, and every enemy takes one on each of them: a body
touching column 1 **strikes**, everything behind it **steps** a column closer. A
turn is exactly the strike-then-advance the loop has always resolved, so the
Distant band *is* the pre-ladder game and a bonus turn is that same beat again,
at the end.

**Authored as the bonus, not as a total.** The ladder used to be the turn count
itself (1 / 2 / 3), and the number a player needs is what the route is *costing*
them: `+1` is a price, `×2` is a stat. It also removes the wrong reading the
total invited — the enemies never act twice in one beat; they act once, and then
the Amulet hands them another beat. `TURN_BASE` is the floor, `BONUS_FAR/MID/NEAR`
the ladder, and `turns_for_hops` is still there as base + bonus for the resolver,
which counts turns rather than prices.

**Why.** The routing decision used to be one-directional: the Amulet is the win
condition, so every step toward it was strictly good and the only reason to take
the long way was to farm. This makes the long way a real option. Route wide and
you fight a slow stack for more games; bum-rush the Amulet and you fight a fast
one for fewer. Neither dominates, and the stack you've accumulated decides which
is right — three followers on your tail is a very different calculation at +2
than at +0.

The consequences fall out of the same rule rather than being special-cased:

- An enemy two columns back is no longer safe. At +2 it walks into range **and**
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
  `⏱ ENEMY TURNS 1 +N` (just `1` in the Distant band, because "no bonus" is a
  state worth reading as calm), a three-rung ladder — first pip the turn every
  game gives, the other two the Amulet's — and the hop count that put it there,
  plus the board's current size and tier on the right, since §7.3 is the other
  half of the same bargain.
- Every **offered card** says what taking it does to the pace — *speeds up —
  +1 bonus turn*, *slows down*, or *still no bonus turns* — next to the route
  badge that says what it does to the distance, because they are the same
  decision.
- Each **body on the board** carries what it does on the next game reported:
  `×2` for two swings, `in 2` for two games of walking still to do. Threat
  colours follow that number rather than the raw column.
- The **resolve plays turn by turn**, counter and all — `TURN 1 / 3` for the
  game's own and `BONUS TURN 1 / 2` for the Amulet's, so what is being watched
  says which half of the bargain it came from — instead of collapsing into one
  slide.

`RunDifficulty.bonus_turns_for_hops` owns the ladder, `turns_for_hops` adds the
base turn to it and `GameLoop2.enemy_turns()` applies that; all three are pure,
so the board, the cards and the resolver cannot disagree about the number. A run
with no Amulet picked, or standing somewhere with no route to it, reads as
Distant — nothing is closing in on a goal that isn't there.

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
Description | Effect | Reference | tags | pools | File | Sorting`.

**A full bar means ready, on every screen.** Every active used to be held back
until the game in play had been reported — right for a **Usable** consumable,
which wants a combat or an event around it (`GameState.can_use_items`) and has
neither while the player is off playing the real thing, and wrong for a **Charged**
one in the way that shows: a full bar is the game saying the thing is ready, and
the pack then refused to fire it and offered *finish reporting this game first* as
the reason. D6, Staff of Flame and Mom's Bottle of Pills are all charged, and all
three do something wanted precisely **while** the board is live — a Scramble
before the next offering, a Burn on the body walking toward you, a pill in hand
for the run ahead. A charge that cannot be spent when it is full is a charge
permanently one game behind.

`PackStrip.fires_while_reporting` is the one place that rule lives, and the pack
strip, the item card and the loot window all ask it. Nothing about the charge
economy moves: a firing still empties the bar and it still refills on the same
hooks.

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
| `Charged, N` | Usable, recharges over N beats (D6 → +1 Scramble; D10 → re-roll the board, 2; Staff of Flame → +3 Burn on a body you point at, 3). |
| `Usable` | Active, player-triggered (Ride the Bus → teleport to a random Deckbuilder game). |
| `Passive` | Always-on modifier (Mine-r Construction: grow the Grid). |
| `Incremental` | A `Triggered` item whose payout is on the **Nth** time, not every time (Charm of the Vampire: every third defeated enemy is +1 Health). The count lives on the inventory slot (`ItemData.counter_value`), so two copies each keep their own — Slay the Spire's rule — and it is **drawn on the item's own art**, bottom-right, the way the Spire draws a relic counter. |

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

**pools** is a different question from tags: *where a relic is drawn from*, not
what it is about. Only `shop` is wired up today, and it is a **weight rather than
a filter** — an item in the shop pool counts **double** when a hub's shelf is
rolled (`ShopSystem.SHOP_POOL_WEIGHT`, §14), so Piggy Bank and There's Options
turn up at a shop more often than the rest of their rarity while still dropping
off a body like anything else. Isaac's shop pool is a separate table nothing else
reaches; against a catalogue of thirty relics and a run that visits at most ten
hubs, that would have made every shop the same two items. `devil_room` /
`angel_room` are authored ahead of the encounters that will read them and are
inert until those exist.

Sample synergies already in the sheet: **Crown** doubles Level Ups; **Snowball**
doubles Transmute gains; **Alien Baby** (+6 Max Health but all enemies +1 Health)
plays against the `alien` bounty; **Unstable Genome** self-destructs for a
3-item choice.

**The Isaac seven**, each of which named a moment or a rule the loop did not have
and so brought a piece of machinery with it:

| Relic | | Brought with it |
|---|---|---|
| **Piggy Bank** | Uncommon, `shop` | The `health_lost` hook — *any* Health leaving the player, anywhere in the run. |
| **There's Options** | Uncommon, `shop` | A dropped item restated as a Small **chest**, and `boss_chest_bonus` to buy a boss's one a size up (§8.2). |
| **The Mark** | Uncommon, `devil_room` | Nothing new: +1 Bash and the **Speed** status (§13), the way Vajra grants Strength. |
| **Stigmata** | Uncommon, `angel_room` | Nothing new: +2 Max Health arriving full, and +1 Bash. |
| **Charm of the Vampire** | Uncommon | The **incremental** counter, and `enemy_killed` for it to count. |
| **D10** | Common, Charged 2 | `reroll_enemies` — the board re-rolled at its own difficulty and type. |
| **Wooden Nickel** | Common, Charged 1 | Nothing new: a 50% `chance` at +1 Gold, on the shortest bar in the game. |

**The Mewgenics three** are one rule wearing three hats — **Lucky Hat**
(Common, +1 Luck), **Bionic Face Plating** (Uncommon, +3 Speed) and **Fortune
Necklace** (Common, +1 Gold on every game selected). Each is *fragile*: an enemy
attack that costs Health destroys it. What they brought is the distinction
between a grant that is **kept** and one that is **rented**:

- A `Pickup` hands you something and lets go of it — The Mark's Speed is yours
  after the item is gone, which is why the sheet's `Status` type maps onto
  `PICKUP` rather than `PASSIVE`.
- A `Passive` holds its grant up for as long as you hold the item. `stat_bonuses`
  already worked that way (Clover's Luck comes off with the clover);
  **`status_bonuses`** is the same channel for statuses, put up by
  `GameState.add_item` and taken back by `remove_item_at`, and it only ever takes
  back its own share — Speed gained any other way is not the plating's to remove.

The destruction is narrower than either "damage" or "Health lost", in both
directions: **Shields absorb first** (§3), so a swing they eat whole costs no
Health and breaks nothing, and the Health a **failed try** charges — or an
event's bill, or a curse's drain — is not an attack and breaks nothing either.
`GameState.change_hp` carries a `source` for exactly this one distinction, and
`GameLoop2._take_hit` is the only caller that tags it as a swing.

**Ban Hammer** (Uncommon, Yet Another Zombie Survivors) rounds the set out and
brought nothing with it: +2 Bashes on pickup, the same `gain_stat` The Mark pays
one of.

### 8.1 Effect DSL — reuse the existing item grammar

The `items2.0.Effect` column is authored in the **same grammar the project already
uses**, so no new engine is needed:

- **Triggered / Usable / Charged** items → `ItemData.triggers = [{on: <TriggerBus
  signal>, if_*: <gates>, effects: [{type: <EffectSystem handler>, …}]}]`.
- **Passive** items → `stat_bonuses` (an always-on verb bonus, e.g. `{bash: 1}`)
  and/or `status_bonuses` (always-on status stacks, e.g. `{speed: 3}`). Both are
  held up by the inventory slot and come back down when it empties.
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

Three more run-scope hooks and two more flags carry the Isaac relics, and they
are listed here because each is a *moment* or a *rule* the 2.0 loop did not
previously name:

| Token | What it is |
|---|---|
| `health_lost:` | A trigger prefix — the player's Health went **down**, from any source anywhere in the run. Not `damage_taken`: Shields absorb first (§3), so a swing they eat whole is damage taken and no Health lost, and **Piggy Bank** must not pay for it. Emitted once per loss by `GameState.change_hp`, the choke point every drain funnels through, so an event's bill and the swing a failed try bought count exactly as an enemy's swing at the end of a game does. A failed try is the one Health loss that can be **undone**, and `GameLoop2.undo_attempt` restores what the tick's turn moved — the purse it minted included, otherwise the undo button is a coin press. |
| `enemy_killed:` | A body was **defeated** (`GameLoop2._defeat`). A bombed enemy is destroyed rather than defeated and never reaches it, the same rule that decides whether the body pays gold (§14). **Charm of the Vampire** counts them. |
| `counter key=K every=N -> …` | The **incremental** wrapper: fire the inner effects on every Nth time, then roll the count back to zero. The count lives on the inventory slot, not on the run — see the `Incremental` row above. |
| `boss_chest_bonus: N` | **There's Options.** Chest points added to a boss's drop; see §8.2. |
| `passive_status: <status> N` | The status half of a passive grant → `status_bonuses`. **Bionic Face Plating**'s +3 Speed. Read `item_acquired: apply_status` as the *kept* form of the same grant and this as the *rented* one. |
| `destroy_on_damage` | **The Mewgenics three.** The item is destroyed when an **enemy attack** costs the player Health — not on a swing the Shields ate, and not on the Health an event charges. A failed try reaches it now that the try is a *turn* (§3.2): the swing it buys is an enemy attack like any other, and `undo_attempt`'s snapshot is what puts the broken trinket back. Fires from `GameState._on_health_lost` off the `source` tag `GameLoop2._take_hit` sets, so one swing that gets through breaks every fragile item at once. |
| `reroll_enemies` | **D10.** Re-roll every non-boss body on the battlefield at *its own* difficulty and game type, keeping the square it stands on and the statuses hung on it. Health resets to the new body's own, because Health here is goal completions and the goals just changed. Bosses shrug it off, the same way they shrug off a bomb (§7.1). |
| `apply_status <s> N target=enemy` | **Staff of Flame**, and the one target word that means *a body the player points at* rather than one a rule names. `ItemData.wants_target()` already reads it, so an item declares "aim me" in the same breath as what it does: `Overworld2.use_item` arms the board instead of firing (`BattlefieldView.begin_item_aim`), the bodies light up as they do for a Bomb, and the click fires it with the instance riding the effect ctx. **Nothing is spent until the click** — a charged item that emptied its bar on the press would charge for a picker you then cancelled. |

Scrolls/encounters keep their **semicolon-separated, space-delimited token** DSL
(`generate_scroll_tres.py` / `generate_encounter_tres.py`); the item generator
(`generate_item_tres.py`) compiles the `Effect` column into `triggers`.

### 8.2 Chests (reuse `grant_chest` + `RewardScreen`)

A **chest** is the project's existing item-reward container
(`GameState.grant_chest` → `RewardScreen`, `BASE_ITEM_CHOICES = 2`). Sizes map to
the number of choices offered.

**A dropped item IS a chest** — a Small one. That is not a rename: it is what
lets There's Options exist without a second reward path. A defeated body's drop
is one item and two buttons (`ItemDropModal`), which is exactly "choose 1 of 1"
— asked as a section of the post-game screen (§18) when it fell to a report, and
as its own modal when it did not;
a boss holding There's Options drops a chest worth one point more, and a Medium
chest is the same modal offering two cards to pick between. Points past a Huge
overflow into a second chest — a second question, asked after the first — so a
stack of copies keeps paying instead of running off the end of the ladder.

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
  Traditional roguelike), one spent per lost run via the attempt tracker, **one
  enemy turn** per lost run once they're gone (it used to be a flat 1 Health, which
  billed a number the board could not see), leftovers absorb the followers' hits
  and then expire with the game. This replaced the earlier "Block carries over between
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
  goal-enemy, stands it on the board, hands over the game's shields, and drops
  straight into the report step — so a run opens with something to go and play
  rather than with a free move. The card opens the ordinary `GameChoiceModal`
  (enemy, goal, shields, connections, route) before you commit; Bash and Transmute
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
| `demand` | an **obligation with a price** — "You must \<condition\>, or \<penalty\>". Pays nothing for being met and **charges for being missed**, billed at the end of every game it goes unanswered. Burn's player side. |
| `instead` | an **alternative to the goal it hangs off** — "\<goal\> or instead \<condition\>". Clears the body without its own condition ever having been set, so the run **banks no record of the beat**. Burn's enemy side. |

Every mode but `demand` is answered by doing it or not doing it, and doing it is
worth something. A `demand` is the one that costs. It exists because Burn is not
a challenge you opt into — it is a debt, and a debt with no consequence for
ignoring it is a suggestion.

A side may also carry `decay`: completing it sheds one stack. That is authored in
the **`Decrease` column** now (§13.1) rather than per cell.

Because the mode says what a side does, **`Type` (Buff / Debuff) drives no
mechanic** — it is the HUD tint and the collection filter, nothing more. The
interesting statuses are the ones whose two sides differ. Marked *charges* you on
the player's side and *pays out* on the enemy's, so the same status is a debt you
work off and a reason to engage the thing carrying it.

### 13.1 Schema

`statuses2.0` columns: `Name | Type | Game | On Player | On Player Effect |
On Enemy | On Enemy Effect | Combat | Decrease | EnemyOnly |
Enemy Combat Effect | Stackable | Image`.

The two **prose** columns (`On Player` / `On Enemy`) are the author's wording,
carried onto `StatusData` for tooltips. Beside each sits its machine-readable
counterpart, which is what the engine runs on:

    <verb> "<condition>" [decay] [-> <reward>; …] [else -> <penalty>; …]

where `<verb>` is one of the five modes above. So the current roster reads:

| Status | `On Player Effect` | `On Enemy Effect` |
|---|---|---|
| Strength | `goal "the difficulty is increased {X} times" -> gain_chest reward {X}; gain_stat bash 1` | `clause "the difficulty must be increased {X} times"` |
| Speed | `goal "beaten in {1+(1/2)^(X-2):hours} or less" -> gain_chest reward {X}; gain_stat dash 1` | `clause "must be beaten in {1+(1/2)^(X-2):hours} or less"` |
| Marked | `demand "get {X} achievements" else -> take_damage 3` | `bonus "you get {X} achievements" decay -> gain_chest reward {X}` |
| Dexterity | `goal "{X} bosses were beaten without getting hit" -> gain_chest reward {X}` | `clause "you must beat {X} bosses without getting hit"` |
| Burn | `demand "skip or trash {X} items/upgrades" else -> take_damage 3` | `instead "skip or trash {4-X} items/upgrades"` |

**One arrow per cell**, and which arrow it is says whether the payload is earned
or owed: `->` is a reward, `else ->` is what missing it costs. A `clause` and an
`instead` may carry neither — both are requirements, not payouts, and the
generator rejects a reward on one rather than silently dropping it; a `demand`
must carry a penalty, since an obligation with no price is a `goal` that forgot
its reward. Either side may be left blank, which reads as "this side is inert".

**`Decrease` says how the status depletes**, for the player and for the code at
once: `N/A` never, `On Completion` sheds a stack each game a side of it is
completed. The generator reads it as the truth and checks the older `decay` flags
against it, so a status cannot say one thing in its column and another inside a
cell.

**`Stackable` may carry a ceiling.** `Intensity` is the usual "a second
application raises X"; `Max: 3` is that with a cap, enforced on the way up in
`GameState.apply_status` and `GameLoop2._add_status_to`. Burn is the status that
needed it: on the player its condition costs X items, so an uncapped Burn would
eventually ask for more than any game has to give.

**Reward token DSL** (compiled by `tools/generate_status_tres.py` into
`EffectSystem` effect dicts, so a chest a status grants is the same chest an item
grants, §8.2): `gain_chest [small|medium|large|huge] <n>`,
`gain_chest reward <n>`, `gain_stat <stat> <n>`, `gain_hp <n>`,
`gain_max_hp <n>`, `gain_gold <n>`. A penalty is written in the same vocabulary
pointed the other way (`lose_hp`, `lose_gold`, `lose_stat`) plus one verb of its
own: **`take_damage <n>` is damage, not a bill** — it resolves through
`GameLoop2.damage_player`, so a shield stops it outright like any other instance
(§3.2) and the player's own statuses scale it, where `lose_hp` comes straight off
Health whatever is standing in front of it. Any `<n>` is a literal or an
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
second timer. Marked twice is one Marked at 2. Only Burn authors a maximum.

**Decay is what the `Decrease` column says**, and a side that decays sheds a
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
| **Marked** | Debuff | Mewgenics | you get X achievements | [chest reward X] on an enemy; on the player it charges 3 Damage for being missed | takes double damage, ignoring Shields |
| **Burn** | Debuff | Brutal Orchestra | skip or trash X items/upgrades (4-X on an enemy) | *nothing* — it charges 3 Damage for being missed | deals half damage |

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

**Burn's two sides run opposite curves, and that is one rule rather than two:
Burn is bad for whoever is carrying it.** On the player it asks for **X** items
skipped, so it costs more the deeper it stacks, and `Max: 3` is the ceiling on
that. On an enemy it asks for **4-X**, so a burned body's way out gets *cheaper*
the more Burn is on it — which is what makes setting something alight worth
doing. The same status, read from either end of the board.

The condition is honour-system like every other one on the checklist — it is
about the **real game you are playing**, not about this project's own item
economy: you skipped or trashed that many pickups in the roguelike in front of
you, and you say so on the report step.

Its two sides bite in opposite directions, which is the point:

- **On the player** it is a `demand`: an extra row on every report, and the only
  row whose *unticked* state does something. The 3 Damage lands at the **end of
  the game, after the enemies have swung** — through the normal hit path, so one
  of that game's shields stops it outright before it reaches Health (§3.2), and a
  run the enemies already ended is never billed. Answering it sheds a stack, which makes the next
  game's asking price *lower*; missing it does not, so it keeps asking at the
  same price until you pay.
- **On an enemy** it is an `instead`: that body's goal grows "or instead skip or
  trash 4-X items/upgrades", and doing that clears the body — same hit, same
  drop, same gold. What it does *not* do is go on the record. The enemy's own
  condition was never set, so nothing is banked against the game it happened at:
  no "beaten in \<game\>" tally, no note (the row carries no Notes button at
  all), and no player `clause` ticks off it either, since a goal nobody met
  carried nothing to satisfy. **Never on a boss** — a boss's goal is the whole of
  what the boss is (§7.1), so `GameLoop2.alternatives_for` refuses one and
  `claim_enemy_alternative` refuses the claim behind it too.

**MARKED IS BURN-SHAPED NOW, on the player's side.** It used to be a `clause` — a
tax ANDed onto every enemy's goal — and it is a `demand`: get X achievements, or
take 3 Damage. Its enemy side is untouched, so the status keeps the thing that
made it interesting (a cost on your side, a payout on theirs) with the cost made
of the same stuff Burn's is. The two demands differ in one place, and it is the
place that matters: Burn is capped at 3 because its condition gets *easier* per
stack on an enemy, while Marked's asks for more the deeper it goes on both sides
and so needs no ceiling to stay honest.

With that change, **nothing in the shipped roster has a player-side `clause`** any
more. The mode is still real and still implemented — `status_clauses` and
`_tick_player_clauses` are what it is — and `test_statuses.gd` registers a
synthetic status to exercise it, rather than borrowing whichever shipped status
happens to be shaped that way this month.

**Two pieces of content hand Burn out**, one to each side of the board:

- **Scroll of Fire** (§4.1) — `apply_status burn 3 player; apply_tile fire front;
  apply_status burn 3 front`. Three clauses now, and the middle one lights the
  ground itself (§17). The first scroll whose cell is more than one thing, and the first that burns
  the reader: +3 Burn on you, +3 Burn on everything touching the front column.
  Negative, obviously, and read for the second half — the bodies about to hit you
  come down to half damage and grow a cheap way out. Its cost lands whether or
  not the room is empty.
- **Staff of Flame** (§8) — `item_used: apply_status burn 3 target=enemy`, a
  Rare `Charged, 3` active. The first relic that has to be **pointed at
  something**: the pack arms it, the board aims it (`BattlefieldView.aiming_item`,
  the same arm-then-aim bargain as the Bomb), and the click on a body is what
  fires it and spends the bar — so cancelling costs nothing. A boss is a legal
  target, exactly as it is for a bomb: what a burned boss loses is its damage,
  not its condition.

Two more items hand OTHER statuses out, the pair of Slay the Spire relics that
grant these same two stats there: **Vajra** (+1 Strength) and **Oddly Smooth Stone**
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

**A reader who is on neither side gets both** (`StatusData.tooltip_both`). A
status is authored independently per side and the two are routinely opposites:
Burn on **you** is an obligation that bites for 3, and Burn on an **enemy** is a
second way to clear its goal. So the keyword strip under an item's description —
which describes the *mechanic*, not a particular application of it — used to quote
the player's side and get it exactly backwards: Staff of Flame reads "Apply +3
Burn to a target enemy", and the footnote under it explained what Burn does to
you. That is not a short version of the answer, it is the wrong half. `tooltip_both`
prints one side when the other is inert and labels them when both do something.

The card that describes a status **on a body** still asks for that body's side and
nothing else, and the enemy card now branches on the mode: an `instead` reads "or
instead: …" rather than falling through to the clause branch and printing a clause
the status does not have.

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
  Shields they were counting on to stop it.
- **Shields are a POOL the status hands out, not a reading of the stack count.**
  Dexterity 2 grants two shields; each stops one whole hit and is gone. The
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

A third rides on top of them: an item in the sheet's **`shop` pool** (§8) counts
**double** in the draw (`ShopSystem.SHOP_POOL_WEIGHT`), so Piggy Bank and There's
Options are twice as likely to be standing at a hub as anything else of their
rarity. A weight and not a separate table, for the same reason as the two above:
Isaac's shop pool is a table nothing else reaches, but against thirty relics and
ten hubs that would have made every shop the same two items, every run. A shop
relic still drops off a body, and a shelf can still come up three ordinary ones.

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

**It is shown once on arrival, then it goes under the board.** Everything above
stays true, and the one thing it never fixed was that a shop mounted below the
fold on the frame you arrive is a shop you may not notice at all — the pointer
says it is down there, not what is on it. So the panel is *first* mounted on the
screen the game ends on (§18) and handed back to the page — the same node,
reparented — when the player leaves it. The moment of arrival gets the shelf in
front of you; the rest of the visit gets it under the board, exactly as before.
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

---

## 17. Tile effects & units (`tiles2.0`, `units2.0`)

Two things can be on a cell of the battlefield that are not a body:

- a **tile effect** — something done to the **ground**, which stays where it was
  put and acts on whoever walks in;
- a **unit** — something of the **player's** standing on it.

They **layer**: a unit stands on top of a tile effect, which is why they are two
sheets and two resources rather than one with a flag. What happens when a
particular pair meets is authored in the content, not in the code.

**Neither blocks a body.** An enemy walks into the cell and whatever is there
*reacts*. That is the whole difference between this and the footprint rules of
§7.3: `occupancy` is about who cannot stand where, and this is about what it
costs to stand there. The one place the two meet is routing — a mined lane scores
worse than a clear one, so the stack walks *around* a minefield rather than being
unable to cross it.

**A tile effect is not a status.** A status rides a body and travels with it; a
tile effect stays where it was put. That is what makes Fire a way to threaten
ground you cannot reach, rather than a body you have to aim at.

### 17.1 The two sheets

    tiles2.0: Name | Description | Effect | Interactions | Decay | Img
    units2.0: Name | Type | Description | Effect | Interactions | Health | Img

Generated by `tools/generate_tile_tres.py` and `tools/generate_unit_tres.py` into
`data/tiles2.0/` and `data/units2.0/`, onto `TileEffectData` and `UnitData`. The
unit generator **imports** the tile generator's parsers rather than restating
them: a unit and a tile effect react to the same board and the same events, so a
second grammar for the same two triggers would only be a second thing to keep in
step.

(`TileEffectData`, not `TileData` — Godot already ships a native `TileData` for
TileMaps, and a `class_name` that shadows one is a parse error. The sheet, the
data folder and every id stay "tile".)

**Effect DSL** — `trigger: effect; effect; …`, the item sheet's shape:

| Trigger | When |
|---|---|
| `enemy_enters` | a body's footprint newly covered the cell — it stepped in, spawned onto it, was pushed into it, or the board grew and reseated it there |
| `enemy_turn_start` | a body was **already** standing here when an enemy turn began |

The pair is the whole vocabulary on purpose. Between them they cover "walked into
it" and "stayed in it", which is what a tile effect has to be able to say to be
worth putting down: a cell that only bit on entry would be free to park on, and
one that only bit at turn start would be free to walk through.

**A tile effect laid UNDER a body fires `enemy_enters` on the spot**
(`GameLoop2._fire_tile_on_standing`). The ground arriving under somebody is as
much a meeting as somebody walking into the ground, and it is billed the same:
one stack per cell of the footprint the tile covers, immediately. It used to wait
for that body's next turn, which made a Red Candle aimed at an occupied square
read as a click that had missed. Only the **tile's** list runs, never the cell's
unit's — the body did not step on anything, so a mine it was already standing on
has no more reason to go off than it had a moment before. A tile that annihilates
on arrival (fire onto a mine) bills nobody, because the check runs after the
interaction and there is no longer a tile there.

| Effect | What it does |
|---|---|
| `apply_status <status> <n>` | puts a status on the body that triggered it |
| `detonate` | the cell's unit goes off where it stands |

**Interactions DSL** — `<kind> <id>: outcome; outcome`, parsed to
`{"unit:landmine": ["detonate_unit", "remove_tile"]}`. The outcomes are
`detonate_unit`, `remove_tile` and `remove_unit`.

**Both sides of a pairing author the same outcome**, deliberately. Fire meeting a
mine and a mine meeting Fire are one event, and the player will look it up from
whichever of the two they are holding. The runtime **unions** the two lists, so an
interaction written on one sheet only still resolves; writing it on both is what
keeps either sheet readable on its own.

**`Decay` is read in GAMES, never in turns.** How many turns a game buys is read
off the distance to the Amulet (§7.4), so a tile authored in turns would burn for
three games out in the wilds and less than one on the Amulet's doorstep — the same
content, worth most where it is needed least. A cell written in turns is **refused
by the generator** rather than silently reinterpreted. It ticks once per game
**resolved** (`GameLoop2.beat_game`), beaten or missed: the ground burns for the
time spent, not for the result.

### 17.2 The roster

| | Fire (tile) | Landmine (unit) |
|---|---|---|
| From | Brutal Orchestra's burn | Brotato |
| Does | +1 Burn to anything that enters or starts its turn on it | on contact with an enemy, destroys itself and explodes |
| Lasts | 3 games | Health 1 — going off spends the whole of it |
| Meeting the other | the mine goes off and the fire goes out | the mine goes off and the fire goes out |

**A body pays per cell.** A 2x2 standing on two fire tiles takes two stacks a
turn — the same rule footprints follow everywhere else on this board (§7.3).

**A Landmine is a PROXY BOMB, and that is the whole reason it is a unit rather
than a one-off trap.** It spends none of the player's Bombs, but everything that
modifies a bomb modifies it, because there is one blast in `GameLoop2._explode`
and both go through it: **Brimstone** widens it to the row and column,
**Sticky** stuns what survives it, **Blood Bombs** pays its Health, **Hot Bombs**
leaves Fire behind. A mine is worth exactly what the pack has made bombs worth.
It also inherits the rest of a bomb's terms: a body destroyed by one is
*destroyed, not defeated* — no drop, no gold — and a boss shrugs it off.

**Fire and a Landmine annihilate each other**, whichever arrived second: the heat
sets the mine off and the blast blows the fire out. The pieces come off the board
*before* the blast resolves, so a detonation that lays fire back over its own cell
(Hot Bombs) does not set off the mine that just caused it. A chain of these is
finite — every detonation spends the unit that caused it — and `MAX_CHAIN` is the
belt to that brace.

### 17.3 The four pieces of content that reach them

- **Scroll of Fire** (§4.1) — `apply_status burn 3 player; apply_tile fire front;
  apply_status burn 3 front`. Its prose gained the middle clause and its cell
  followed: the bodies in your face are burning now, *and* the strip they are
  standing on keeps burning whatever steps into it for three more games. That
  second half is what makes the scroll worth reading into an empty room.
- **Red Candle** (Common, `Charged, 1`, shop) — `item_used: apply_tile fire
  target=tile cols=2-3`. The first item aimed at **ground** rather than at a body:
  `target=tile` is the tile-side twin of Staff of Flame's `target=enemy`, and the
  board arms a cell picker instead of lighting up the stack
  (`BattlefieldView.aim_cells`). `cols=2-3` is the reach — never column 1, where
  it would be a free hit on whatever is already swinging, and never the back,
  where nothing would walk over it before it burned out. The fence is enforced in
  `EffectSystem` as well as in the highlight, so a cell that arrives some other way
  obeys it too.
- **Hot Bombs** (Uncommon) — `item_acquired: gain_stat bombs 1; bomb_tile fire`.
  The bomb synergy that hands out **ground** rather than damage: every cell the
  blast covered is left on fire, so a bomb that failed to kill still costs the
  survivor a stack of Burn a turn for three games. Widened by Brimstone for free,
  because what it reads is the blast rather than the target — and it reaches a
  Landmine's blast for the same reason.
- **Landmines** (Uncommon) — `game_beaten: apply_unit landmine
  target=random_empty`. One mine per game finished, on a cell with **nothing on it
  at all** — no body, no unit, no tile effect. That is "a random empty Tile" read
  strictly, and it is the right reading: a mine dropped onto burning ground would
  go off on the spot and take the item's whole payout for that game with it.

### 17.4 Routing: how the enemies read a minefield

`path_blockers` now answers `{enemies, cells, mines}`, and `_spawn_rows` ranks
lanes lexicographically on **(bodies in the way, mines to cross, cells those
bodies block)**.

**Mines rank BELOW bodies on purpose.** A body in the lane is a wall that may
never move; a mine is a **toll** — one point of Health, paid once, and then the
lane is clear. An enemy that treated the two as equally bad would rather queue
forever behind a boss than step on a mine, which is not caution, it is a bug that
reads as one. So the stack routes around a minefield when it has anywhere else to
be and walks straight through it when it doesn't — which is what makes Landmines
an item that **shapes** the board rather than one that seals it.

### 17.5 Where they live at runtime

- **On the board** — `GameLoop2.tiles` and `GameLoop2.units`, both
  `Vector2i(col, row) -> {…}`, keyed by CELL rather than held on the entry
  standing there. Serialized as flat lists (JSON has no key type but string).
- **Arriving in a cell** — `GameLoop2._move_entry` is **the** one place an
  on-board entry changes cells. A step, a spawn, a push and a board that grew
  under a body all come through it, so there is nowhere for "does walking into
  fire burn you?" to be answered twice. It returns whether the body **survived**,
  and every caller that was going to keep moving it checks that.
- **The start of a turn** — `_fire_turn_start_cells`, before anything swings, so a
  body parked on fire is already burning when it strikes rather than a turn late.
- **On screen** — units draw in a layer **under** the bodies (a unit is on the
  floor), and a tile effect draws as a shallow strip hugging the **bottom edge**
  of its cell in a layer **over** them. Over, because a fire tile under a 2x2
  would be a fire tile nobody can see; shallow, because the point is to read the
  ground without losing the body standing on it. The strip is never clickable —
  it overlaps the bodies, and one that ate their clicks would make the front row
  unselectable exactly when it matters. A per-cell hover in the **lower** layer
  reads whatever is on a square, and tree order does the precedence for free: a
  cell with a body on it answers with the body's card, bare ground answers with
  the ground.
- **What the ground says** — the same `HoverCard` an enemy, an item and a status
  carry (`TileEffectData.hover_card` / `UnitData.hover_card`, assembled per cell by
  `BattlefieldView.ground_hover`), not Godot's grey system tooltip. The tile's
  **clock is a pip** — `⏱ 2 games left` — rather than a sentence, because how long
  a burning square has left is the one thing about it that changes between one
  look and the next. A square carrying **both** a unit and a tile answers with ONE
  card: the unit heads it, the tile joins as a pip and a line, because "what is on
  this square" is one question.

### 17.6 Keywords — the dropdown a mention carries

An item or a scroll describes itself in the player's vocabulary: "Gain +3 Burn",
"Bombs Apply the Fire Tile", "Apply the Landmine Unit to a random empty Tile".
Every one of those names a mechanic with rules of its own, and the sentence has no
room to carry them. So the card names the thing and a **keyword strip** underneath
says what the thing is, Slay-the-Spire style.

`scripts/ui/Keywords.gd` is **one registry for all three kinds** — statuses, tile
effects and units — because from the reader's side they are one question ("what is
that?"), and three registries would be three places for the answer to go stale.
Each kind already owns its own words (`StatusData.tooltip_for`,
`TileEffectData.tooltip_for`, `UnitData.tooltip_for`), so the registry finds the
mentions and hands the writing back to the content.

Matching is on the display name at **word boundaries**, so "Burn" does not light
up inside "Burning Blood" (which is a real relic). A tile answers to both "Fire"
and "Fire Tile", and a unit to both "Landmine" and "Landmine Unit", because the
sheet's prose uses both.

`Keywords.attach(host, text)` adds nothing when the text names nothing, which is
what makes it safe to call on every card rather than only the ones expected to
need it. It hangs off the **reading** surfaces — the item info card, the item drop
modal's single-item layout, the scroll read modal (identified scrolls only; a
strip naming Burn and Fire under "reading it is a gamble" would give the whole
thing away), and the Collection's detail pane. Not the shop shelf or the
five-abreast chest cards, which have no room.

## 18. The end of a game — one screen (`PostCombatScreen`)

A report used to fire **six independent surfaces**, none of which knew about the
others: one `ItemDropModal` per defeated body, then the `LootDropModal`, then the
event, then the shop appearing under the board, then the boss notice, with the
toasts running underneath all of it. On a boss round at a hub that is five popups
in a row, each re-centring on the same spot, each with its own Take/Leave, and
nothing tying any of them to the game they came out of.

Worse, **the first two opened on top of the resolve animation**. Drops are queued
in the middle of `GameLoop2.beat_game` and were pumped on the next idle frame,
while `Overworld2._hold_for_resolve` was still playing the strike and the advance
back — the one place the run's consequences are ever *shown*. So the player
answered "do you want this relic" over the top of the blow that had just taken
eight Health off them.

So the haul is **a screen**, and it opens when the board has stopped moving.

| Section | What it carries |
|---|---|
| **The verdict** | the game's cover and name, and which of the three reports this was — beaten, goal missed, or walked away (they are three different things; see §2) |
| **The fight** | damage taken and blocked, goals cleared, what is still following, shields left over or banked, the difficulty tier, and the board's growth if it just stepped (§7.3) |
| **The spoils** | every relic chest down the left and the loot payout down the right, **all of it at once** rather than one question after another |
| **The shelf** | a hub's shop, if this game was one of the ten (§14) |
| **The warning** | the boss notice as a banner rather than a sixth popup (§7.1) |

And **one button out**. It is the **event** when the node owes one — clicking it
is what opens the event, so the player leaves this screen *into* the next thing
rather than having the next thing dropped on them — and "travel on" when it
doesn't. It counts what it is about to bin (`exit_text`), because a Legendary left
on the ground should be a decision and not a side effect of pressing Continue.

**The sections are the real modals, embedded.** `ItemDropModal.embed`,
`LootDropModal.embed` and `BossNoticeModal.embed` build the same cards, run the
same selection, and answer through the same signals; what they skip is the
backdrop, the centring and the `CanvasLayer`. So the 3×3 on this screen is the
inventory in exactly the sense §4.3 means it, a chest is still "which one of
these", and a boss portrait still opens its card. One code path, two frames.

**The standalone modals stay**, and that is the point of embedding rather than
replacing: `GameState.offer_loot` fires from `EffectSystem`, so an item, an event
or a machine can hand over loot at any moment, and a payout that did not arrive
with a report has no haul screen to be a section of. `Overworld2._pump_drops`
suppresses itself only while `_resolving` — which only a report sets — so an
out-of-band offer still asks for itself, on the spot.

**The shelf is borrowed, not moved.** §14's decision that a shop blocks nothing
and stays for the whole visit is still right; what was missing was it being seen
at the moment you arrive. So this screen mounts the panel and hands **the same
node** back to the page on the way out (`release_shop` → `Overworld2._adopt_shop`),
reparented rather than rebuilt, so a card left open survives the handover.

**Every chest is on the screen at once**, and that is the point of the screen.
They were drained one at a time at first, which is how the page's queue had always
worked — but a queue hides the thing a player most needs when several relics land
together, which is what the *others* are. There is often an order: a relic that
changes what a chest is worth should be taken before the chest it changes, and a
Charged active you are about to fire is worth more than one you are not. None of
that can be reasoned about a card at a time. Each chest is still its own question —
"which one of these" — and answering one leaves the rest exactly where they were.

A one-item chest lays out **sideways** there (`ItemDropModal`, the `sideways`
branch): the card on the left, Leave and Take stacked on the right. Stacked it is
~135px, and three of those is more than the column holds — which puts the third
relic behind a scrollbar on the one screen built so relics can be weighed against
each other. And a relic is **always a picture**: both layouts used to draw art only
when `item.image` was non-null, so an unarted row would come up as a name over a
gap; `_item_art` draws a tinted stand-in instead.

**The payout does not close on its last piece, and it has no buttons.** As a modal
the table emptying is the end of the question. Here it is the opposite: the piece
has just gone *into* the pack, and the pack is the reason to still be looking —
the next thing a player usually wants is to spend it. So the section stays, with
its 3×3 and its bin live, until they leave the screen. Take and "Leave the rest"
go with it: they were the modal's way of ending itself, the drag already puts a
piece in the slot you want, and the bin under the pack is "leave it" said with the
hands. What is still on the table when the player walks off is counted on the way
out, so nothing goes quietly.

The two columns are **top-aligned** when embedded. Centred, the offer floated down
to sit level with the middle of the nine slots, so a piece's name and description
started lower than the pack and read as having slipped underneath it.

**A chest banked while the screen is up lands on it** (`add_chest`). A level-up
reward, Unstable Genome firing on the beat, a status paying out — all of those
call `grant_chest`, and `RewardScreen` mounts as an ordinary child of the page,
*below* this screen's CanvasLayer. The player saw nothing and then found a reward
screen waiting the moment they left. `Overworld2._hand_chests_to_post_game` rolls
them on the same ladder the RewardScreen would (`Data.roll_item_rarity`,
`BASE_ITEM_CHOICES + Discovery` for a default-size chest) and hands them over.

**A section that raises its own card needs a layer above this one.** The shop's
shelf opens an item card at `ShopPanel2.card_layer`, whose default (122) clears
the page but not this screen — so clicking a row opened a card nobody could see
and produced it a screen too late. The host sets `card_layer` to 131 while it
holds the panel and puts it back on the way out.

It sits on layer 128: **below** the run's header bar (135), so Health and Gold
stay readable over it, and below the loot use modal (130), so spending a piece
from the pack still opens on top. Its page is inset under the bar the same way
every other modal is (`ModalScaffold.reserved_top`).
