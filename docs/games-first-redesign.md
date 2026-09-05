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
defeats the enemy and drops loot; beating the game *without* the goal lets the
enemy hit your health. Reach and clear the **Amulet** game to win; hit 0 health
to lose.

Designed **stream-first**: the player-facing state (health, shields, the enemy and
its goal, the verb/consumable counts) renders to a slim **OBS companion window**,
so every number must stay small and glanceable.

---

## 2. Core loop

1. **Choose a game** on the graph. Routing is the core decision (see §6).
2. The game presents **one enemy** = one goal, plus its attack value and its
   guaranteed loot drop. Committing to it also spawns an **escort** (§7.5) — a
   second enemy from the same pool, with a second goal, that beating the game
   does *not* answer for. Boss rounds are the exception and spawn solo.
3. **Go play the real game. You must beat the game to advance to the next area.**
4. Resolve:
   - **Goal met → enemy defeated → loot drops where it fell, and its difficulty
     is banked toward the chest the report pays (§8.2).**
   - **Game beaten but goal not met → the enemy is not defeated: it *stacks*.**
     No drop. The enemy has been standing on the board since you chose its
     game (§7.2) and simply keeps walking — from the back column it takes a game
     or more to reach you — and once it is in the front column it **attacks after
     each game you play**, for its `Damage`, until its goal is fulfilled. Unspent
     `shields` (§3.2) absorb, remainder comes off `health`. The more unbeaten enemies on
     the stack, the more damage per game, ramping until you die or clear them.
   - **Old goals can still be fulfilled later.** Fulfilling a stacked enemy's goal
     during any later game **defeats it** (removing it from the stack and stopping
     its per-game hits) and drops its loot, exactly as if you'd beaten it on time.
   - **Enemies follow the player until beaten.** A following enemy **cannot be
     dashed/moved past** (moving to another game never drops it). It is removed by
     fulfilling its goal — or, for a **normal** enemy, by a **bomb** (bombs damage
     normal enemies; no drop when bombed). **Bosses take no bomb damage** and can
     only be removed by their goal. Pre-commit escapes (**scramble** the goal /
     **bash** the game) also exist before you play.
5. Repeat until the **Amulet** game is cleared (win) or **health = 0** (loss).

### 2.1 A tick is a confirm, and a confirm resolves NOW

The checklist (`ReportChecklist`) is the honour system, and every box on it is a
**confirm**. Ticking one raises "did you really?"; answering Yes **resolves that
row on the spot**, while the game is still being played:

| Row | What Yes does, immediately |
|---|---|
| An enemy's goal | deals the goal's hit (`GameLoop2.fulfill(inst, true)`) — the body dies if that is enough, and its loot lands on the square it fell in (§8.2) |
| …or instead (Burn, §13) | the same hit, by the other route (`fulfill_instead`) — engagement, but no beat on the record |
| An enemy's bonus objective | pays it (`claim_enemy_bonus`) |
| A player status goal / `demand` | pays it, and answers the demand so it cannot bill you at the end of the game |
| The character's level-up | takes the level and its reward |
| An event goal | claims it |
| A curse | nothing to pay — what it buys is the penalty *not* firing at the report |

**There are no take-backs.** The confirm is the safeguard; past it the row locks.
An enemy that is already dead cannot be un-killed and a relic already in the pack
cannot be handed back. (The **Undo** beside the lost-run tracker is a different
thing: it takes back a *turn*, which is the board's, not yours.)

**And the list follows the board it is describing.** The goals can change while a
game is being played — a **D10** re-rolls every non-boss body where it stands
(§8), a **Scroll of Create Monster** conjures a new one onto the stack, a bomb
takes one off — and the report step used to be built once, when the game was
taken, and never look again. So a player who spent a charge escaping a goal they
could not do went on being asked to tick that goal, off a list describing a board
that no longer existed.

`Overworld2._refresh` rebuilds it now, guarded by a signature of **what the rows
say** (`ReportChecklist._play_panel_sig`). Two things about that guard are load-
bearing. It is not the standing list's signature, close as the two are: that one
counts `in_front`, so a lost run would rebuild the panel under the player once a
turn for a list whose words had not changed. And rebuilding is *safe* only
because a confirmed row is remembered by `GameLoop2.answered_rows` rather than by
its checkbox — which is exactly what "there are no take-backs" is implemented as.
A rebuild re-locks everything that was answered, and the only thing it can lose is
a tick that was never confirmed, which the confirm rule means cannot exist.

This exists because the report used to be the only moment anything could happen.
That was fine while a game was one long wait for a single point. It is wrong now
that the board moves whenever you *fail* (§3.2) and a kill is something you can go
and make: a goal you cleared in the first hour sat unpaid for the rest of the
evening, and the reward for it was behind a screen you had not reached. **Losing
runs does not gate any of it** — a lost run is the enemies' turn, not a lock on
the checklist.

**The confirm is also where the note is written.** Ticking an enemy goal or the
level-up row raises the confirm, and the confirm carries the write-up field for
the pair the row is about — (game, enemy) or (game, character), the same note
`EnemyNoteModal` edits from the Atlas and the Collection, saved on Yes and thrown
away with the panel on No (`ReportChecklist._arm_row`'s `note` hooks). It is asked
for *there* because the moment you confirm a kill is the moment you remember how
it went, and because the alternative was a `🗒 Notes` button on every line of a
list whose lines are already a portrait, a symbol, a wrapped sentence and a box.
The rows carry no such button now, and the width it was taking is the checklist's.

**A completed goal sinks.** Once a row is answered it is a record rather than a
question, and left in place it is a line the player re-reads every time they scan
for what is still to do — the list being longest exactly when they have done the
most. So an answered level-up / status / event / curse row drops under everything
still open (`ReportChecklist._add_row` / `_flush_sunk`).

**The enemy rows do not sink**, and that is the exception the rule needs. A body
with more Health than one goal completion can take (`effective_health` > 1, an
Alien-Baby board) has been *answered* without being *finished*: it is still
standing, still walking, still on the board beside the list. A body that did go
down leaves the stack entirely and comes back as a ghost row, which sinks with
the rest — so "cleared enemies at the bottom" falls out of the same rule without
the enemy rows needing to know about it.

**The loop remembers, not the boxes.** The page rebuilds this list on every
repaint, so a tick that cannot be taken back must not be something a repaint can
lose. `GameLoop2` keeps the per-game record and clears it when the game is chosen
or handed in:

- `cleared_this_game` / `instead_this_game` — bodies engaged mid-game.
- `staggered_this_game` — the engaged bodies that **survived** the hit, from
  either path: a goal ticked mid-game, or one claimed at the report. A staggered
  body is out of the game — see **Staggered** in §7.2.
- `goals_met_this_game` — so a player clause riding a goal still ticks (§13) for a
  game whose goals were all answered hours earlier.
- `answered_this_game` — player objectives already claimed, so a `demand` does not
  bill someone who answered it.
- `answered_rows` — the rows the four above have no room for (a bonus, a curse, a
  status goal, the level-up), keyed by the checklist's own strings.
- `claimed_event_goals` — the display fields of the event goals claimed this game.
  Claiming one takes it off the run, which used to take its row with it on the next
  repaint: it was the one answered row that *vanished* rather than staying ticked,
  and a player who had just ticked it was left wondering whether they had.
- `_ghosts` — the entry a body defeated this game used to be. The report always
  resolved bonuses *before* goals so that "an enemy you failed can still pay its
  bonus" held; with the goal resolving when it is ticked the order is the
  player's, so killing a body first must not forfeit the bonus you earned off it.
  Its row stays on the list, and `claim_enemy_bonus` reads the ghost.

The report then only deals with what is still **outstanding**: `ticked_fulfilments`
and `ticked_status_claims` skip any row that is pressed *and* locked, which in
practice is all of them.

**…and the RUN remembers what the game forgets.** Everything above is scoped to
one game and cleared when it is handed in (`_clear_game_record`), which is right
for a list read to decide what to play for and leaves the run with no record at
all of the work behind it: eight games in, the checklist says "three things to
do" and nothing whatsoever about the twenty already done. On a game that is
played entirely on the honour system, being able to show its working is not a
decoration.

So every confirm also appends to `GameLoop2.completed_goals` — `{kind, text,
game}`, oldest first, cleared only by `reset()` and carried by both the save and
the turn snapshot (an undone turn is an undone resolution). What it keeps is the
row's **finished sentence**, not the objective it was rendered from: the status
may have expired, the body may be off the board, an event goal is off the run the
moment it is claimed, so a record that had to look any of them up again would be
a record that rots.

The **✓ *N* done** button at the head of either checklist state
(`ReportChecklist._verify_head_row`) opens it as `CompletedGoalsPanel` — the
graveyard's twin, grouped by the game each line was done at, newest first, tinted
by kind. It is a scoreboard and not a control: every line in it is already
resolved, so nothing there can be claimed, unclaimed or edited.

---

## 3. Health & shield model

Kept deliberately tiny for HUD readability.

| Stat | Value | Notes |
|---|---|---|
| Health | character-set (5–10) | Current HP. Lose at 0. |
| Max Health | character-set | The cap Health heals up to; **items raise it** (`+N Max Health`). Raising it heals by the same amount — a container arrives full — so the item that means an *empty* one says so with its own token (`gain_empty_max_hp`, Hollow Heart). Lowering it is not the mirror: it takes the room and leaves the Health, which only moves when it no longer fits. |
| Temporary Shields (`shields`) | granted per game, **no cap** | **The armour the game you selected granted** (see §3.2). Each stops **one whole instance of damage**, however big, before `health` is touched — and they **expire with the game that granted them**. Losing a run does not spend them. |
| Shields (`bonus_shields`) | gained off the board, **no cap** | The same block, from a pill or a banked game (§4.3) — but they **stay** until something breaks one, and are used only once the Temporary ones are gone. |
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

**THE TWO POOLS ARE NAMED FOR WHETHER THEY SURVIVE THE GAME.** What a game
grants are **Temporary Shields** — they expire when it is reported. What is
gained off the board (a pill, the Barricade card banking a resolved game) are plain
**Shields** — they stay until something breaks one, and are used only once the
temporary ones are gone (§4.3).

The FIELDS behind them keep their older names, `shields` and `bonus_shields`:
those are the keys every save is written with and the stat names authored content
grants (`gain_stat shields 1` is Anchor, `gain_stat bonus_shields 2` is Balls of
Steel), and swapping them would flip the meaning of a word inside every existing
save and every `.tres` that says it. The player-facing words live once, in
`GameState.TEMP_SHIELD_NAME` / `SHIELD_NAME`, and every screen reads them from
there.

Shield sources beyond the per-game grant: items (**Anchor** — "when a game is
selected, gain +1 Temporary Shield"), and future tag routes / scrolls.

### 3.1 Characters, Level Up & the reward loop

**This reuses the current project's level-up mechanic directly** (`CharacterData`
+ `Overworld._resolve_level_up`). In `characters2.0`, **the columns left of `Level
Up` (Health, Bash, Dash, Push, Transmute, Scramble, Bombs, Keys) are the character's
starting stats**; `Level Up` is a per-game challenge and `Reward` is what meeting
it grants.

| Character | Level Up objective (per game) | Reward |
|---|---|---|
| Rodney | Beat a game without meta progression | +1 Max Health, +1 Loot |
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
nothing but armour. And the armour comes in two pools named for the one thing
that separates them — **Temporary Shields** expire with the game that granted
them, **Shields** do not.

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
  logged — it is what the tracker shows.
- **The undo is a restore, not a refund.** A turn walks bodies, burns ground,
  breaks the trinkets that break on a hit (§8.1) and pays out whatever losing
  Health pays out, so `GameLoop2.log_attempt` snapshots the board and the run's
  resources before it resolves and `undo_attempt` puts the whole thing back.
  Those snapshots are **runtime-only** — a save carries the run, not its undo
  history — so a turn taken before a reload cannot be taken back, which is what
  `can_undo_attempt` answers. **There is no undo button**: it spent half its life
  greyed out for exactly that reason, wearing a tooltip to explain itself, and a
  safeguard that is unavailable half the time is not one. The restore stays as the
  loop's own take-back; the tracker is a one-way press.

**A SHIELD STOPS ONE INSTANCE OF DAMAGE.** The whole of it, whatever its size: a
3-damage swing breaks one shield and lands for nothing, and so does a 1-damage
one (`GameLoop2._take_hit`).

- **Selecting a game grants them** — **3** for any game, **5** for a
  **Traditional** roguelike (the long haul); nothing else moves the number, so it
  reads straight off the game's type. Items hooked on *"when a game is selected"*
  add to the grant, which is what **Anchor** now does (+1 Temporary Shield): the
  extra cover
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
- **The ones a game grants are TEMPORARY, and expire when you report it.** They
  never bank into the next game on their own: an easy game cleared first try does
  not arm you for the next. The **Barricade card** ([`cards-design.md`](cards-design.md)
  §5.1) is the exception, and it banks the survivors into the pool that stays
  rather than stopping the expiry — for the next game only, because it is one use.
- **The ones gained off the board are just SHIELDS, and stay** (§4.3) — a pill's,
  a banked game's. A hit breaks a Temporary Shield first, since those are the ones
  about to expire anyway.
- **A shield breaks ON SCREEN.** The run's pools have already been spent by the
  time the board starts drawing the resolve, so for the length of a playback the
  row over the hero is the PLAYBACK's rather than the run's
  (`BattlefieldView._shields_shown`, the same trick the Health line plays) and one
  sprite swells and fades as each blocked blow lands. Without it the armour was
  simply gone before the swing that broke it was drawn — the one thing a shield
  exists to do was the one thing never shown happening.

**ESCAPE OPENS ON THE HIT.** A game you cannot beat is not a run-ender: you may
walk away from the one in play, and the door opens **the moment an enemy's attack
takes Health off you during it** (`GameLoop2.hurt_this_game`, set by `_take_hit`
on the `enemy_attack` source alone). It is open from the first second on a game
this run has **already beaten** — there is nothing left to prove at that one.

- **The hit is the *first* gate, not the only one.** It used to be five lost runs,
  from when a lost run spent a shield and then Health: a counter standing in for
  "this game is hurting you" because nothing else measured it. The board measures
  it directly now — lose runs, the enemies take turns, a Temporary Shield stops
  the first swings outright, and the door opens on the swing that gets past them.
  The way out therefore arrives exactly when the game starts costing the one
  thing you cannot make more of.
- **…and THREE BODIES DOWN is the door the player drives**
  (`Overworld2.ESCAPE_AFTER_DEFEATS`, counted per game by
  `GameLoop2.defeated_this_game`). It used to be an EMPTY BOARD, on the grounds
  that nothing left on the stack means nothing that can ever open the hit gate.
  True, but it asked for the wrong thing: on a stack of six it is unreachable and
  on a stack of one it is a single goal, so the same door cost anywhere between
  one kill and a whole board depending on something the player never chose. A
  fixed count is the same argument at a fixed price, reachable on every board
  including the one that will not stop growing. A BOMBED body does not count —
  it never reaches `GameLoop2._defeat` — so buying a goal away does not also buy
  the door.
- **…and five lost runs is the floor under it** (`Overworld2.ESCAPE_AFTER_LOSSES`).
  The hit is the honest measure, but it is one the player does not control: a board
  of low-damage bodies behind a stack of Temporary Shields can take an evening and
  never land a point of Health, and a player who cannot beat *that* game would be
  held there by the rule written to let them out. Five losses is not a good way out
  — the board has taken five turns to get there — and it is not meant to be. It is
  a way out that always eventually arrives.
- **The button is always on screen, darkened until one of them opens.** Hiding it
  meant the one player who most needed to know there was a door — the one stuck —
  was reading a panel that never mentioned it. Under the greyed button is the
  price, as every route still to be paid: *"3 more losses, Beat 3 Enemies, or Lose
  Health"* (`Overworld2.escape_routes` / `escape_hint_text`). All of them at once
  rather than the nearest, because which is cheapest is a fact about the player's
  board that only the player can see — naming one would be advice, naming all
  three is information. A route already open drops off the line, and an open door
  says nothing at all.
- **A swing only.** Burn's bill and an event's price cost real Health and do not
  open it: they are not the game in front of you refusing to go down.
- **Per game.** Cleared when a game is chosen and when one is reported, saved
  with the run, and rewound by an attempt's undo — taking back the tick whose
  turn drew blood shuts the door again.
- The price is unchanged: escaping resolves the board exactly as a missed report
  does (the goal-enemy follows you, the stack takes its turns), and it banks no
  beat. Only the gate moved.

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
all four change what is on the table — and all four are **buttons**. Dash and
Scramble act on the offering as a whole and fire on the press; Bash and Transmute
need a target, so the press ARMS them and the click on an offered card is what
spends the charge. **Push and Bombs** need no row of their
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
| **Bomb** | Deal 1 damage to an enemy. Normal enemies have **Health 1** (`enemies2.0`), so one bomb removes one (no loot, and no chest points). A **boss is a legal target but takes no bomb damage** (§7.1) — the charge only buys what an item hangs off the throw. Three items change what a bomb does: **Brimstone Bombs** widen the blast to the target's whole row *and* column, **Sticky Bombs** stun whatever the blast fails to destroy (in practice, bosses), and **Blood Bombs** pay +1 Health per bomb via the `bomb_used` trigger. **A bomb is aimed at a SQUARE, not only at a body** (`GameLoop2.bomb_cell`): every cell of the board lights up when the verb is armed, and an empty one is a legal target — which is how **Hot Bombs** lays fire in front of the stack and how **Brimstone** is aimed down a lane rather than off whoever happens to be standing in it. A click on an occupied square still routes through the body-aimed path (`GameLoop2.bomb`), so the target reaches the blast, the boss rule and the `bomb_used` trigger unchanged. |
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

**Identify is a flat 10% of every loot drop, and is not in the scroll pool at
all.** It used to be an ordinary Common carrying a `find_weight` of 1.25
(potions-design decision #20) — 1.25 draws to every other Common's 1 — which,
after the three-way kind split (§4.3) and the rarity ladder had each taken their
cut, worked out at roughly one drop in forty. The scroll whose whole job is
telling you what the other two alphabets *are* cannot be the rarest thing in the
pack: a run that never finds one plays the pill and potion layers blind. So the
odds are now stated where a player can feel them — `GameState.roll_loot_entry`
takes the tenth off the top before the kind is even chosen — and Identify authors
a `find_weight` of **0**, which `Data._pick_by_find_weight` reads as *never*, so
the ordinary scroll roll cannot also produce it and make the tenth an eighth. The
tenth is taken off the kind-blind drop and off an explicit `scroll` one; an
explicit `pill` or `potion` grant still pays what it promised.

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
- **THE MASKED NAME IS A TITLE DEALT PER RUN**, not a flat "Unidentified Scroll".
  A potion's mask is a bottle colour and a pill's is a capsule; a scroll's is the
  writing on it, because a scroll is a sheet of paper and there is nothing else
  about one to vary. So every scroll is dealt a meaningless title at the start of
  a run — **"ZELGO MER"**, **"ah bloto festr"** — which it keeps all run and which
  means something else entirely in the next one.

  The bag is two authored columns of the `scrolls2.0` sheet, generated into
  `data/scroll_names.tres` (a `ScrollNames` resource) and dealt by
  `ScrollSystem.ensure_names`. **A coin per scroll:** half wear one of the 35
  whole authored names, half wear **2-5 syllables joined with spaces** off the
  39-part list. The two look alike in a pack slot and are meant to — the player
  cannot tell an authored label from an assembled one, so neither says anything
  about the scroll underneath. **Every title in a run is distinct**, for the reason
  two potions never share a colour word: two scrolls answering to "TEMOV" make the
  run log ambiguous about the very mystery the player is tracking.

  Without this the pack was nine slots of the identical string, and the Identify
  picker had to **spoil the real names outright** just to be a choice at all
  (`LootSystem.pick_label` returned `ScrollData.display_name`, so opening Scroll of
  Identify answered its own question). Titles make the unknowns tellable apart
  while telling you nothing, which is the trick every roguelike this one is built
  out of plays with its scrolls. The flat "Unidentified Scroll" survives only as
  the fallback for a checkout where the generator has not been run.
- It becomes **identified** by reading one **to some effect** (learn-by-use — a
  scroll whose every clause no-opped teaches nothing, see potions-design §4.5) or
  via **Scroll of Identify**; from then on that type shows its real name and art, and the toast
  names both halves — *"ZELGO MER is Scroll of Fire!"* — because the answer worth
  having is the one that also teaches you to read the other ZELGO MER in the pack.
  **Amnesia** can re-hide (`unidentify`) a known scroll, which puts back **the same
  title**: the writing on the page never changed, you merely stopped knowing.
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
and the card is only the **cover art, the game's name, the Amulet's flag** when
it is the game the run is a search for — and **how far that game stands from the
Amulet**, in its own row under the flag and over the art ("*N* games away from
the Amulet"). That last one is the number the whole run is counting down: the
card says which *way* it goes only once it has been opened, so without it the
offering could be scanned without ever showing how much road was left. It is
blank on the Amulet's own card, where the flag above it has already said it.

The **hover line** under the cards names what is *waiting* — the enemy, its goal,
the shields the game grants — and deliberately **not the game**, whose cover the
mouse is on and whose title is printed under it. The line is one line wide and
the goal is the half that gets truncated.

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
- and the one thing that can be done about the card: **Travel**.

**Bash and Transmute are not on this screen.** They were, on the same action row,
and it was the wrong place for them twice over: this card is opened dozens of
times a run to answer "do I go here", and two destructive verbs beside the Travel
button made that a three-way every time — while the chips that COUNT the charges
could not spend them, and pointed here instead. They are armed from those chips
now and aimed at a card (§4): press ⛏ Bash, the offering becomes a row of targets
in the verb's colour, click the game you want gone. Arming is free; the click is
what spends the charge. The Amulet still refuses a Bash, and refusing leaves the
verb armed rather than eating it.

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
| Full Health | Positive | Heal to full | Heal to full, +3 Shields |
| Balls of Steel | Positive | +2 Shields | +4 Shields |
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

**Shields (the pool that stays).** Shields can be gained **outside a game**
(Balls of Steel, horse Full Health), and those are a separate pool from the
**Temporary Shields** a game grants (§3.2). The name is the rule: a Temporary
Shield expires with the game it came from, and a Shield does not.

- They are drawn **closest to the player** — at the head of the shield row,
  nearest the portrait on the board's hero, and beside the always-visible Health
  chip in the header, because a pool gained on the overworld has to be readable
  when no board is on screen. The header draws them as the **same shield sprite**
  the board does (with no clock, since these never expire); it used to be a `◈`
  glyph, which made the one pool a player meets away from the board the one pool
  nothing had taught them to recognise. Position is one half of the reading: the further
  from the portrait a shield is, the sooner it goes. The **clock badge** is the
  other half — a Temporary Shield wears one and a Shield does not, the same mark
  a borrowed status pip wears (`UITheme.timed_art`), so "expires" is one symbol
  across the whole UI rather than a glyph per surface. There is **no shield
  count in the checklist panel**: the board draws armour as armour, beside the
  character it is protecting, and a captioned copy of it in the paperwork was
  room the checklist wanted.
- They are **used last**: a hit breaks a Temporary Shield first and only reaches
  these once those are gone (§3.2). A lost run breaks neither — it costs a turn
  of the board and nothing else.
- They **never expire.** The temporary pool dies with the game that granted it; a
  Shield stays until something breaks it, which is what makes it worth carrying
  toward a game you expect to hurt.

**Barricade banks into that pool.** It used to stop the temporary shields
expiring, which quietly made them a second non-expiring pool with its own rules.
It now **converts what a resolved game left standing into Shields**, so there is
one pool that persists and one thing that fills it. That is a small buff — banked
shields are used last too, where the old behaviour spent them first — and it is
the right one: it is about the cover you *didn't need*.

**And Barricade is a CARD now, not a relic** ([`cards-design.md`](cards-design.md)
§5.1). The relic held this rule for every game, forever, from the moment it was
picked up; the card arms it for the NEXT game and is spent. `GameState.banks_shields()`
is still the only reader — it reads a run flag instead of the inventory — so
nothing about the rule above changed except how long it lasts.

**Where pills come from.** Two places, and they are the same roll.

**Beating a game pays 1 random piece of loot** — an even FOUR-way split between a
scroll, a pill, a potion and a **card** ([`cards-design.md`](cards-design.md) §4),
and the run's baseline loot income. It is paid for
any game the player actually saw through: **walking away from a game pays
nothing**. It arrives the way a kill drop does — the same asked modal, one queued
behind the other — rather than as a toast, because with a **nine-piece cap** on
the pack, taking a piece of loot is a decision.

**And every body you defeat drops one** (§8.2), on the same split, on the square
it fell in — the run's other loot income, and the one that scales with how much
fighting the evening actually did. It is **on top of** the game's own piece, not
instead of it, and it is kept whatever the report said: the kill is what earned
it.

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
into the slot you want it in** — see the drop modal below. So: **hover reads, drag
moves, the button spends**, and a click does nothing at all.

A piece used to open a read-only card on click (`LootInfoCard`, now gone), on the
argument that a relic answered a click with its card and a pill answered with
nothing. The argument was right about the gesture and wrong about which screen was
missing: the **Use screen** already leads with the art, the kind, the Preference and
what the piece does before it asks whether to spend it, so the reading card was the
same page twice — and it was the copy on which nothing could be decided. The hover
card is the fast read on the way past; Use is where a piece is actually looked at.

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

**So the answer is never a refusal.** A Use button that will not press is a
worse thing than an effect that lands on nothing: it teaches the player the piece
is unusable rather than that this *moment* is wrong for it. Every scroll op lands
perfectly well mid-game: `apply_status` and `apply_tile` reach a board that is
standing right there, `spawn_enemy` and `stun_enemies` act on the stack about to
resolve, and `forget` and `identify_scrolls` never needed a map at all.

**A teleport mid-game ESCAPES the game and then moves you.** This is the one op
in either roster that genuinely needs the map, and `Overworld2.loot_teleport` used
to answer it with *it fizzles, you do not move* on the grounds that shifting the
run while a game is in play is not a thing the loop can mean. It is — the loop has
had a word for it since it shipped, and walking out of a game that will not go down
is the single most useful moment a teleport will ever have. So the op takes the way
out on the player's behalf (`escape_game(true)`) and *then* lands them somewhere
else.

It **forces the exit past `can_escape()`**, which ordinarily wants the game to have
drawn blood first. That gate asks whether the game has hurt you enough to deserve a
way out; spending a piece of loot on the door is a different answer to the same
question. What it does **not** do is discount the price: the goal-enemy still walks
on and follows you, the board still takes the turns finishing a game owes (§7.4),
and the game is still not credited — an escape is not a win. You are buying the
exit, not a pardon. Both consumables that teleport (Scroll of Teleportation and the
Telepill) come through the one function, so both escape; one rule for moving the run
off a game.

**And so does every other teleport.** Ride the Bus (`teleport_to_type`) used to move
the run by hand — `travel_to_game` set the phase back to SELECT and that was that —
which walked the player out of a game in play for free: no goal-enemy following, no
turns for the board, no report. It escapes first and arrives second now, exactly as
the scroll does, so an item that moves you pays the same fare. Its one exception is
the return leg of a `play_game` detour (§10), which is not a teleport: that game has
already been reported by the time the run heads home.

**And the bus runs on the ROADS.** `teleport_to_type` used to draw from
`Data.all_games()` — all 854, the entire catalogue. The run's map is one connected
component (`RunGraph._prune_to_main_component`); everything else is a game this run
cannot walk to, and landing on one leaves the player on a node with no edges, in a
game whose offering is empty and whose only way on is another teleport. Transmute is
the verb for reaching off-map games, and it reaches them from a slot that stays on
the route. So `RunGraph.is_off_map` is the bus's whole filter — the same question the
Scroll of Teleportation asks by taking its pool off the Amulet's BFS — and no route
of that type says so out loud rather than no-opping.

**All of it works with a game in play.** Loot could always be spent mid-game
(`LootGrid.locked` holds the pack still, it does not stop a spend), but an ITEM
could not: `PackStrip.fires_while_reporting` held every non-charged active back
until the game was reported. That is right for an ordinary Usable, which wants an
event around it, and wrong for an **overworld active** — `overworld_usable` marks
an item whose effect needs the map, and the map is mounted for the whole of a game
being played. The one item that can get you off a game you cannot beat was being
refused for exactly as long as you were stuck on it, with *"finish reporting this
game first"* as the reason. It fires from any screen now.

The two relics that made the case — Ride the Bus and the Wand of Wishing — have
both since left the item roster to become **loot** (a card, §4.4, and a wand,
§4.4), and loot was always spendable whenever the player wanted it. The flag and
the rule stay, for the next relic whose effect needs the map.

**AND IT LANDS YOU IN THE GAME, not next to it** (`Overworld2.arrive_at_game`). A
teleport used to leave the run in `Phase.SELECT`: a fresh offering was drawn
around the new node, and the game you had been dropped onto was one more card you
were free to walk past — which made every teleport a free re-roll of the offering
rather than a move. "Teleport to a random space" means you are *somewhere* now,
and being somewhere in this game means playing the game that is there. So an
arrival commits exactly as `pick` does: the destination's enemy is rolled (a boss
if it is a boss round — a scroll is not a way to skip one), the escort comes with
it, the selection shields are granted, and the phase goes to `PLAYING`.

**With the card on top of it.** Committing without a word would drop the player
onto a board with a body already walking at them and no idea what game they are
even looking at, so the arrival raises the same `GameChoiceModal` the offering
opens — cover, type, the enemy and its goal, the shields, and the road on from
here — in `arrival` mode: no *Back* button, one button that only takes it down,
and a **banner across the top saying you were moved**. The banner is the only
thing separating this screen from the card the offering opens, which is otherwise
identical, so it says it twice over: the headline that you have been teleported
and that this is the game you are playing now, then the teleport's own sentence
underneath — where you landed, how far that is from the Amulet, and whether a game
was walked out of on the way. It was one small gold line, which sat between a
title and a cover and read as flavour. **The commit happens first and the card is a
briefing, not a question**, because a dismissible question leaves the run standing
on a game nobody committed to with no offering drawn. It opens on **layer 121**,
under everything the game you left still owes — the `PostCombatScreen` (128), its
event and a boss notice (123) — so those are read first and the arrival is the last
thing on the screen when they are done: the closing words of one game, then the
opening words of the next.

`travel_to_game` — which does land you in `SELECT` — is now only the two moves
that are genuinely about position rather than about a game: the returns from a
`play_game` detour, and the dev panel's jump.

Two dead ends survive, and both say so in full. If the escape is what kills you —
the turns it hands over are real — the run is over and there is nowhere to land. If
the graph has nowhere to put you, the game was still walked out of and still charged
for, so the line carries both halves rather than reading as "nothing happened".

**And the piece is identified either way.** Both `ScrollSystem.read_scroll` and
`PillSystem.take_pill` identify *before* they apply anything, so even a landing that
fizzles still teaches you what the thing was — the gamble paid off even where the
effect did not. That is the whole reason a fizzle is an acceptable answer where one
is left and a refusal was not: the player spent the piece and got the information
they spent it for.

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

### 4.4 Potions, Cards and Wands — the other three kinds

Three more loot consumables share the pack described above, and each has a design
doc of its own rather than a section here, because each is a system rather than a
roster.

**Potions** ([`potions-design.md`](potions-design.md)) are the third kind and the
only one with **two verbs**: every row authors a quaff side and a throw side, and
the player chooses which they are buying when they spend it. Identification is per
type and covers both.

**Cards** ([`cards-design.md`](cards-design.md)) are the fourth, and the one that
breaks the pattern the other three share. **A card is not a gamble**: one use, no
identification, no Preference, and what it does printed on it. Three variations on
"spend it to find out what it was" is two more than a run needs, so the fourth kind
is the other question — *when*, rather than *whether*.

What a card withholds is **which card it is, and only on the floor**: lying on a
battlefield square it draws its DECK'S icon (five icons over thirteen cards) and
turns over for good when it is picked up (§8.2 above, and cards-design §3).

**Wands** ([`wands-design.md`](wands-design.md)) are the fifth, and the only one
that is **not spent in a single use**. Every row authors a charge count — four to
six, one for the Legendary — and zapping one spends a charge rather than the slot.
So a wand asks its question of the PACK rather than of the piece: nine slots, and a
Wand of Fire is four Scrolls of Fire you have to carry all at once and cannot put
half of down.

It is a gamble like the first three — an unknown wand hides behind one of 28
materials, 24 of which the run deals to nothing — and what you win is different in
kind: identification covers **every charge**, so the first zap is the price of the
other five. Two rules fall out of the charges and are written down in wands-design
rather than here: a wand stands **outside Echo Chamber in both directions** (§4.4
there), and **anything that charges items charges wands** while a beaten game
charges only relics (§7 there).

**Beating a game therefore pays an even five-way split** — 20 / 20 / 20 / 20 / 20
across scroll, pill, potion, card and wand (`GameState.LOOT_KINDS`). The Identify
tenth is still taken off the top and did not move: the run that needs the scroll is
the run holding four unknown capsules, and its odds should not depend on how many
cards or wands it drew.

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

**The tier is not decoration** (`GameLoop2._pick_by_type_tier`). A thin bucket
widens **down the tier ladder within the type**, one rung at a time, and never up
or sideways: a run at High meets a High body of the right type whenever one is
authored, and a type with nothing at that rung steps down rather than reaching for
another genre's goal. Insane is empty in the goal-enemy pool, so an Insane run
draws High. Only once a type is exhausted at *and below* the tier asked for does
the type itself give way — which nothing on today's roster reaches. Everything
conjured **by other means** (a curse's bill, a Scroll of Create Monster) rolls
through `roll_conjured_enemy` instead, which is stricter still: the run's tier or
the nearest rung below it, and nothing else.

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
§7.4).

**Staggered** works the other way round, and is the whole game rather than one
turn of it. A goal met deals **one** hit, and one hit does not always finish the
job — an Alien-Baby-buffed body has 2 Health, a Dexterity one spends a shield
instead. A body that takes its goal's hit and is still standing is **Staggered**:
it neither strikes nor steps for the rest of that game, whether the goal was
ticked mid-game or claimed at the report, and whether the turns come from the
Amulet's pull (§7.4) or from a run you lost (§3.2). Only the game is bought — the
body is still there, still owed, still carrying its goal into the next one, which
is what its remaining Health means.

It reads on the board as the art **darkened** with `STAGGERED` across it, in a
threat colour drained toward grey; its hover and its full card say why. There is
no art for the state and it needs none.

`GameLoop2.staggered_this_game` is the record, `is_staggered()` the question, and
it clears with the rest of the per-game record (see §2.1). This grace window is
why bombs, old-goal fulfilment, and Stun are all viable answers rather than
needing to solve an enemy the instant it appears.

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
  two extra turns a game at the high tiers is still a couple of games of warning.
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

### 7.4 Amulet pressure — the extra turns you buy by closing in

The run has two difficulty axes. The tier ladder (§7.1) is the clock: it ticks
up on its own, every `GAMES_PER_TIER` games, and the player only rides it. This
is the other one, and it's the one the player **steers**.

**REPORTING A GAME GIVES THE BOARD NOTHING.** Out in the wilds you can play a
game, hand it in and walk away with the stack exactly where you left it. What
moves the enemies is the runs you **lose** at a game — one turn each (§3.2) — and
what closing on the Amulet buys them is **EXTRA TURNS at the end of every game
you report**, read off how far you are in hops over the run graph:

| Hops to the Amulet | Extra turns | Band |
|---|---|---|
| 5 or more | 0 | Distant |
| 3 – 4 | 1 | Closing |
| 2 – 0 | 2 | Doorstep |

A **turn** is one action, and every enemy takes one on each of them: a body
touching column 1 **strikes**, everything behind it **steps** a column closer. A
turn is exactly the strike-then-advance the loop has always resolved — an extra
turn is that same beat, handed out for finishing a game near the Amulet.

**Zero is the floor, and that is the change.** The ladder used to be the turn
count itself (1 / 2 / 3), so every reported game moved the board whether or not
the player had struggled at it. Now the board moves for two reasons and both are
things that happened: **you failed** (a lost run, §3.2) or **you are close to the
win** (this ladder). A quiet game played far out costs nothing at all, which is
what makes the routing decision a real one rather than a slower rate of decay.

**Why.** The routing decision used to be one-directional: the Amulet is the win
condition, so every step toward it was strictly good and the only reason to take
the long way was to farm. This makes the long way a real option. Route wide and
you fight a slow stack for more games; bum-rush the Amulet and you fight a fast
one for fewer. Neither dominates, and the stack you've accumulated decides which
is right — three followers on your tail is a very different calculation at 2
extra turns than at none.

The consequences fall out of the same rule rather than being special-cased:

- An enemy two columns back is no longer safe. At 2 extra turns it walks into
  range **and** swings before you have picked the next card, so "how far away is
  it" is measured in turns, not columns. The board reads that distance in **lost
  runs** (`GameLoop2.lost_runs_until_strike`), since that is the turn supply the
  player controls.
- **Stun** costs one turn, so it is worth a whole lost run wherever you stand,
  and half of a reported game's cost at the doorstep — the same charge, priced by
  the pace.
- **Old-goal fulfilment** holds a follower's fire for the whole game, so it goes
  the other way and is worth *more* the closer you push (§7.2).
- **Strength** buffs each hit, so a two-extra-turn report is two buffed hits — the
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
  `⏱ EXTRA TURNS N` — `0` out in the wilds, which is a state worth reading as
  calm — with a two-rung ladder, the hop count that put it there, and the board's
  current size and tier on the right, since §7.3 is the other half of the same
  bargain.
- Every **offered card** says what taking it does to the pace — *speeds up — 1
  extra turn*, *slows down*, or *still no extra turns* — next to the route badge
  that says what it does to the distance, because they are the same decision.
- Each **body on the board** carries what **one lost run** would let it do: `⚔3`
  for the swing it would throw, `in 2` for the lost runs of walking it still owes.
  Threat colours follow that number rather than the raw column, because that is
  the threat the player is deciding against — reporting a game out in the wilds
  costs nothing.
- The **resolve plays turn by turn**, counter and all — `EXTRA TURN 1 / 2` at the
  end of a game, `TURN 1 / 1` for a lost run's — instead of collapsing into one
  slide.

`RunDifficulty.extra_turns_for_hops` owns the ladder and `GameLoop2.enemy_turns()`
applies it; both are pure, so the board, the cards and the resolver cannot
disagree about the number. A run with no Amulet picked, or standing somewhere with
no route to it, reads as Distant — nothing is closing in on a goal that isn't
there.

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

**A BOSS ROUND GETS ONE TOO.** It used to be the one carve-out: a tier change
already swaps in the heavier, bomb-immune pool at triple gold (§7.1), and doubling
the bodies on that round looked like merging two difficulty steps into one wall.
What it actually produced was the run's biggest round on its **emptiest board** —
one body, where the ordinary game before it had two — so the capstone read as a
quieter game with a bigger enemy on it. The boss now arrives with an ordinary
escort out of the round's own type and tier (`choose_boss` hands both on, and the
roll widens downward from there, since a boss may be authored at a tier the
goal-enemy roster does not reach). It is a normal body: bombable, worth ordinary
gold, one chest-point tier. Every rule that is the *boss's* stays the boss's.

**One rule still carves out of it**, so the escort cannot be farmed:

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

### 7.6 Abilities — the second half of what an enemy is

Health, Damage, Size and a goal say what a body is *worth* and how much board it
takes. **Abilities say what it DOES**: how far it can strike from, what rides its
swing, what it spends a turn on instead of you, and what it leaves behind when it
dies. They are authored in the **`abilities`** sheet and hung on enemies through
the `Ability` column of `enemies` / `bosses`.

**The catalogue is data; the behaviour is code.** This is the one place in the
project where those come apart, and deliberately. `data/abilities2.0/*.tres`
(`AbilityData`) owns each ability's **name, type, argument shape and sentence** —
generated from the sheet like everything else, so the wording a player reads is
upstream content. What an ability *does* is written once in `GameLoop2`, keyed by
id, because an ability reaches into the turn resolver, the mover, the spawner and
the death path at once, which is more than the per-row effect string `tiles2.0`
and `units2.0` use could express.

The consequence is a rule with teeth: **a row added to the sheet does nothing on
the board until `GameLoop2` learns the id**, and
`test_enemy_abilities.gd::test_every_authored_ability_is_one_the_loop_implements`
fails the suite rather than letting it ship as a promise on an enemy card that
the board never keeps. The reverse assertion is there too.

**The `Ability` column's grammar** is a comma list of names, each optionally
carrying bracketed arguments: `Ranged (2), Fireproof, Infliction (1, Burn)` is
three abilities, while `Split (2, slime tag)` is one with two arguments — so the
split is **paren-aware**, and a plain `split(",")` gets both cases wrong in
opposite directions. The sheet's `Variables` column says how many arguments a
name takes and what they mean, so the parse is checked against the catalogue at
generation time and an unknown name is reported rather than written out.

Each parsed ability is one dictionary on `GoalEnemyData.abilities`:

```
{"id": &"infliction", "amount": 2, "arg": &"burn", "text": "Burn"}
```

`amount` is the numeric argument, `arg` the second one normalised for code, and
`text` the sheet's own wording for it — which is what the cards print, so a
description reads the way it was written. An **omitted count is 1** (a bare
`Hexer` is one curse) but an **omitted or `N/A` grid range is 0, meaning
unlimited**: opposite defaults for the same empty cell, which is why the slot is
read rather than the blank.

An `Enemy Type` argument names a **pool**, and the prefix says which kind:
`tag:slime` (anything with that tag), `tier:medium` (anything at that tier),
`enemy:spider` (that one, by name), `self` (another copy of the summoner).

**Abilities are read off the BODY, never off the sheet row.** `entry["abilities"]`
starts as a copy of the enemy's and can be added to at runtime — an Illusionist
hands `illusion` to what it summons, and a save writes the runtime list, because a
reload that rebuilt from the sheet would resurrect the copies as ordinary enemies
that outlive their maker.

#### The roster, and the rules that are not obvious

**One action per turn**, for abilities as much as for ordinary bodies. An intent
spends the whole turn; so does a strike. A **Ranged** body that shoots from four
columns back does *not* also close — before this the mover ran over everything
that had not reached column 1, which would have let a sniper arrive twice as fast
as §7.4's ladder says anything can.

| Ability | The rule, where it isn't obvious |
|---|---|
| **Ranged (X)** | X is the **gap** it shoots across, so `Ranged (2)` strikes from column 3. `N/A` is the whole lane — dangerous from the moment it spawns, and the card says so in words ("Can Attack from any range") rather than substituting the `0` it is stored as. It shortens `_turns_owed`, so the threat colours and the ⚔ badge agree with the resolver. |
| **Devour Whole** | The hit **ends the run**, whatever your Health. A shield stops the whole instance and therefore stops this — cover is the only answer, and past one nothing else matters. |
| **Tanky (X)** | Health here is **goal completions**, so Transient's `Tanky (8)` is nine goals. That is the joke: you are not meant to kill it, and its `Fading (3)` is the answer. |
| **Bolster (X, Y)** | A **live aura**, not stacks handed out: while it stands, every *other* body carries the status, including ones that walk on later, and killing it takes it off the whole board at once. Derived inside `entry_statuses_effective`, so damage, shields, movement and pips all account for it without knowing it exists. |
| **Theft (X, Y)** | What it takes is **real** — gold leaves the purse, a relic leaves the inventory and stops working. Then it **turns and runs for the back edge**; off the board it goes with the haul. Kill it and everything lands on the square it fell in. |
| **Agile** | Diagonal **only when straight ahead is blocked** — the one exception to §7.3's "enemies never change lanes", and deliberately the smallest one. It exists for the two thieves, so a getaway can get round a wall. |
| **Trample** | Shoves a blocker aside or back **for free** and walks in, using the same geometry the player's Push verb does. A blocker with nowhere to go stays, and the trampler stalls like anything else. |
| **Ruthless** | Only when it **cannot reach you**. With Devour Whole (the two bodies that have it carry both) it clears the lane outright. |
| **Invisibility** | The board draws **nothing** — no node, no badge, no hover, and hovering its checklist row lights no square. Its **goal is still on the checklist**: you were told what walked on, not where. It blocks a lane, it walks, and a bomb aimed at that *square* still finds it. It gives itself away the moment it swings. |
| **Predatory Scent** | An extra turn only when the player **had a status goal and met none of them**. Both halves are the ability. Runs as a turn of its own rather than by bumping the count — it is a free swing for two or three bodies, not the board's pace changing. |
| **Necromancy (X)** | Raises from **this run's graveyard** — the same list the board's ☠ Fallen panel shows. An empty graveyard is an idle turn. Raised bodies gain the `undead` tag. |
| **Entry Summon (X, Y)** | A summoner that is **not a wall**: it spends its *first* turn laying X escorts and every turn after that walking and swinging like anything else. The escorts go on **random free squares adjacent to it** rather than in the single cell in front (which is what `_brood_cell` is, and what makes a boxed-in Nested Spawner idle) — so a full lane slows it down instead of stopping it. Each square is rolled against the board *as it stands*, so escort two goes somewhere escort one left free, and one with nowhere to go is simply not laid. |
| **Drain (X, Y)** | The one rider that takes something **killing the body does not give back**. A thief holds its haul and drops it when it dies; Degradation burns loot the next chest replaces; Drain takes a permanent point off Max Health, Luck, Scramble, Bash, Dash or Transmute. Nothing goes below 0, and **Max Health stops at 1** — a run is lost by Health reaching 0, not by its ceiling doing it. It goes through `grant_run_stat`'s own field map, so `dash` finds `dash_charges`. |
| **Ritual** | Only the **first** turn is spent. Every turn after, the +1 Strength rides a turn the body also walks or swings on — a Ritual that spent every turn stacking would never attack, and the Strength it piled up would never be spent on anything. |
| **Fireproof** | Refused inside `_add_status_to`, so every route a Burn can arrive by is covered at once — a fire tile, a Scroll of Fire, another enemy's Infliction, a Bolster aura lending it. |
| **Fading (X)** | A combat is a **game**, so it ticks with the tiles and the borrowed statuses at the end of a report. Running out is a **death**: its own Aftermath fires and its face joins the graveyard. It pays nothing, because nobody did its goal. |

**A SUMMONED BODY IS AN ORDINARY BODY.** Illusionist, Necromancy, Nested Spawner,
Entry Summon and Split all put real enemies on the board: they carry goals, and clearing one
pays its loot, its gold and its chest point like anything else. That is the trade
a spawner offers — it is printing threats *and* rewards, and which of those it
turns out to be depends entirely on whether you keep up with the goals.

**A BODY KILLED BY ANOTHER BODY PAYS NOTHING**, which is the same rule a bomb
follows (§4): a Ruthless boss eating your stack is a mercy, not a farm. So is an
illusion popping because you killed its maker.

**The death hook hangs off the DAMAGE RESOLVER, not off `_defeat`.** `_defeat` is
the drop path and a bombed body never reaches it — but a bombed Guillatina still
owes the board its next phase and a bombed Spike Slime still splits. Aftermath,
Split, Undying, the Illusion cascade and the graveyard row all fire for every
death however it happened.

#### Phases (`bosses` only)

A boss can be **several bodies deep**. The `Phases` column says how many;
`Goal Type` and `Goal` are then read as `/`-separated lists and `File` as a
comma-separated one, so one sheet row carries three goals and three pictures.
**Undying is what steps between them**: each revive brings the boss back at the
rightmost column at the start of the *next* game, one phase on, with its own goal
and its own portrait. A whole game of respite is the only thing separating a
three-phase boss from a body with three times the Health.

`goal_type` / `goal` / `image` hold **phase 1**, so everything written before
phases still reads correctly; `GameLoop2.entry_goal` / `entry_goal_type` /
`entry_image` are what the screens ask, and they answer for the body actually
standing there.

#### Where the player sees all of it

- **An exclamation mark in the top-right corner** of any body on the grid that
  has an ability, in the same row as the ▸ selection marker — two labels anchored
  to one corner draw over each other, and the one that loses is whichever the
  player was reading. A bare `!` rather than the ⚠ used everywhere the mark gets a
  line of its own: this corner is 11px on a 46px cell at the widest board, where a
  triangle with a stroke inside it is a smudge. Nothing goes over the middle of
  the art; identifying the enemy is the picture's job.
- **The hover names every ability and what it does**, in a line each, under the
  goal. This is where an **Illusion** is named — an illusion that reads like an
  ordinary enemy is a goal the player will go and spend a real evening on.
- **The card spells them out** in an ABILITIES panel: name, type chip, and the
  sheet's sentence with its arguments filled in.
- **☠ Fallen**, beside Push and Bomb above the grid: every enemy this run has put
  down, newest first. Click one for its card; write a note on one and it is filed
  against the (game, enemy) pair in `GameStats.enemy_log` — the same store the
  Atlas's per-game notes use, so it is one fact written once and read in both
  places. The button is hidden until something has died, because the toolbar fits
  its page to about ten spare pixels and a fourth permanent button wraps it. The
  panel closes on a click on its dimmer and **only on a click** — a mouse wheel is
  an `InputEventMouseButton` too, so once the list stopped scrolling the wheel
  fell through and shut the panel under a player reading to the bottom of it.
- **The Collection sorts the Enemies and Bosses tabs by ability**, alongside A-Z,
  Tier and Damage: an ability is the one thing about a body that isn't a number,
  and it is what the roster is browsed for.

---

## 8. Items (`items2.0`)

Every game you beat pays a chest of relics, scaled by the bodies that fell to it
(§8.2), so the item table *is* the reward economy.
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
| `Usable` | Active, player-triggered. **No relic ships as one with an effect that needs the map any more**: Ride the Bus became a **card** ([`cards-design.md`](cards-design.md) §5.1) and the Wand of Wishing became a **wand** ([`wands-design.md`](wands-design.md) §5.2). The kind and the `overworld_usable` flag are both still real and still right for the next relic that wants them. |
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

**The potion five** are the Slay the Spire side of the shelf, and two of them
brought a hook each:

| Relic | | Brought with it |
|---|---|---|
| **Cauldron** | Rare, `shop` | Nothing new: +5 Potions on pickup, `gain_potion` through the loot grant. |
| **Old Coin** | Rare | Nothing new: +6 Gold on pickup. |
| **White Beast Statue** | Uncommon | Nothing new: +1 Potion on `game_beaten`, which is every game seen through, win or lose. |
| **Reptile Trinket** | Uncommon | The **`potion_used`** hook, declared since the potion work and emitted by nothing until this item wanted it. +3 Strength *borrowed for one game* — the first item to hand out a timed status, and what made one row per instance necessary (docs/potions-design.md §5.4). |
| **Ripple Basin** | Uncommon | The **`run_lost`** hook and **`if_goals=`**, the first gate on a run-scope trigger: +1 Temporary Shield for a lost run logged while the game is still blank. |

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
| `health_lost:` | A trigger prefix — the player's Health went **down**, from any source anywhere in the run. Not `damage_taken`: Shields absorb first (§3), so a swing they eat whole is damage taken and no Health lost, and **Piggy Bank** must not pay for it. Emitted once per loss by `GameState.change_hp`, the choke point every drain funnels through, so an event's bill and the swing a failed try bought count exactly as an enemy's swing at the end of a game does. A failed try is the one Health loss that can be **undone**, and `GameLoop2.undo_attempt` restores what the tick's turn moved — the purse it minted included, otherwise the undo would be a coin press. |
| `run_lost:` | A trigger prefix — the player pressed the button that logs a **lost run** at the game in play (§3). Fired once per press by `GameLoop2.log_attempt`, *before* the turn the tick costs is resolved, so what an item hands out here is standing when the board swings. The context carries `goals_met`, how many goals this game has paid out so far, which is what `if_goals=` reads. Inside the snapshot `undo_attempt` restores, like everything else the tick moved. **Ripple Basin** is the item. |
| `potion_used:` | A trigger prefix — a potion was **drunk or thrown**. One event for both, because that is how the wording reads (**Reptile Trinket**: "whenever you drink *or throw* a potion"), and a bottle that fizzled on empty ground was still spent. Emitted once per use by `PotionSystem.notify_used`, the choke point both sides go through. |
| `if_goals=N` | A **gate** on the trigger before it, not a trigger of its own: the hook fires, and the item's effects only run when the context's `goals_met` is exactly N. Ripple Basin's `if_goals=0` is "before completing any goals". A hook that carries no goal count at all **refuses** a gated trigger rather than passing it — a gate is a narrowing, and "this hook can't answer that" is not a free pass. |
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

**The chest is what BEATING A GAME pays**, and its size is what the evening's
fighting was worth. It is asked as a section of the post-game screen (§18),
one `ItemDropModal` per chest — "choose 1 of N" — so a Small chest is one card
and two buttons and a Medium is the same modal offering two.

A boss holding There's Options drops a chest worth one point more. Points past a
Huge overflow into a second chest — a second question, beside the first — so a
stack of copies, or a heavy evening, keeps paying instead of running off the end
of the ladder.

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

#### What a report owes (the kill scaling)

A game **beaten** is worth **one chest point on its own** — a Small chest for a
win with nothing standing on the board — and **every non-boss body defeated since
the last report adds its own difficulty on top**:

| Body defeated | Points |
|---|---|
| Low | +1 |
| Medium | +2 |
| High | +3 |
| Insane | +4 |

…spent on the ladder above, so three High kills on a game you beat is 10 points:
two Huge chests and a Medium. The tier is the enemy's **own authored difficulty**
(`GoalEnemyData.difficulty`), not the tier the run has climbed to — that column is
a *gate*, and a Low enemy in an Insane run is still a Low enemy. Paying for the
run's progress rather than for the thing you actually fought would make the reward
stop describing the fight.

**Only a win pays it.** A missed goal or a walk-away banks nothing from the bodies
— the loot they already dropped on the floor is what a lost evening keeps. The
points are banked at the kill (`GameLoop2.chest_points`, `_defeat`) and spent at
the report (`GameLoop2.claim_chests` → `Overworld2._queue_report_chests`), which
is also the gate: `claim_chests(false)` empties the pool and pays nothing out of
it. A **bombed** body never reaches `_defeat` at all, so buying your way out of a
goal buys no chest either.

**A BOSS is not in that pool.** It banks a chest **of its own**
(`GameLoop2.boss_chests`, 1 point plus There's Options), rolled from the boss pool,
kept beside the kill chest rather than folded into its points, and **paid whether
or not the game went your way** — it was never a reward for the game, it is the
thing that boss drops, and it dropped the moment the boss fell. Two bosses are two
chests, never one bigger one.

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

#### The floor — LOOT lands where the body fell

A defeated body's **loot** is **put on the board, on the square it died in**
(`GameLoop2.drops`, keyed by cell): one piece, rolled on the same four-way
scroll / pill / potion / card split as a game's own payout (§4.3,
`roll_loot_entry`), a boss included. A **card** lands there face down — it draws
its deck's icon until it is picked up ([`cards-design.md`](cards-design.md) §3),
which is the one thing on this board that is still a chest. It stays there until the player takes it or the game is reported.
That is the whole point of clearing a goal *during* a game: the reward is on the
table in front of you rather than banked behind a screen you have not reached yet.

**Why loot rather than a relic.** The floor used to hold the chest, and a chest is
a question the board is not allowed to answer — its card deliberately said nothing
about what was inside, so what stood on the square was a gold glyph standing in
for an offer you could only read by opening it. A scroll, a pill or a potion **is
a thing**: it can be drawn as itself, recognised across the board while a body is
still walking at you, and picked up without a question being asked first. So the
floor kept the half a board can actually depict, and the relics moved to the
reward screen where the choosing belongs.

**A card is the one exception, and it is a deliberate one**
([`cards-design.md`](cards-design.md) §3). It lies there FACE DOWN — the token
draws its deck's icon and the hover names the deck and stops — so the square asks
*"is a Major Arcana worth a slot"* rather than answering it. That is the chest's
question back on the board, in the one form a board can depict, and it is paid for
by the card being fully readable the instant it is picked up.

- **It wears its own art.** The board draws a token carrying the same picture the
  pack and the loot window draw (`BattlefieldView._drop_node` →
  `LootSystem.art_texture`), sized through `LootSystem.art_box` so the **horse
  dose still comes back bigger** here too. A kind with no art falls back to the ✦
  glyph the floor wore before. A **card** is the one kind whose floor picture is
  not its pack picture: it shows its deck's icon and turns over on pickup
  (`art_texture(entry, face_up)`). An **unidentified** piece shows only the
  anonymous vial or capsule it shows everywhere else — the whole point of taking one is
  finding out.
- **You pick it up by picking it up.** The token is a drag HANDLE (`FloorLoot`)
  and there is **no click**: drag it and the pack appears beside the board for as
  long as the piece is in the air, drop it in a slot or the bin, and both the
  carry and the panel end together. See "the drag" below.
- **Its card is the card.** `LootSystem.hover_card`, the same one the pack, the
  loot window and the drop modal show, plus the two things only a piece on a
  battlefield knows: which square it is on, and what leaving it there costs.
- **Loot never blocks anybody.** `fits_at` does not consult the floor, so a
  body walks onto the square and the piece is **shoved out of the way**
  (`_displace_drop`, from `_move_entry`): to the nearest free square, measured in
  squares walked, with ties broken **away from the player** — loot drifts back
  toward the wilds rather than into your lap. A board with no room left for it
  sends it **off field**, where it waits on the haul screen like any unclaimed
  piece.
- **A body that was not standing anywhere leaves nothing on the floor.** One
  waiting in the off-grid queue has no square to fall in
  (`_drop_cell_of` → `OFF_FIELD`), so its loot goes straight to the haul screen.
- **Reporting the game sweeps the floor** (`sweep_drops`, called from
  `Overworld2.report` the moment `beat_game` returns), **whatever the report
  said** — the loot was earned by the kill, which already happened, and only the
  relic chest is a reward for beating the game. What nobody stopped to pick up —
  including whatever the bodies that very report cleared just dropped — goes onto
  the haul screen (§18) as **one table** rather than one question per square,
  rather than vanishing with the board the next game rebuilds.

#### The drag — the pack shows up for as long as you are holding something

Taking a piece off the floor used to be five steps: click the square, wait for a
`LootDropModal` to open over the board, find the pack inside it, drag the piece
into a slot, close the modal. **Four of those five exist to get the pack onto the
screen** — and the pack is nine cells that can simply BE on the screen for as long
as the player is carrying something.

So the token is a **drag handle** (`FloorLoot`), and the pack is **transient**:

- **`NOTIFICATION_DRAG_BEGIN`** reaches every Control the moment a drag starts
  anywhere in the viewport, which is the one signal that means "the player's hand
  is full". `Overworld2._notification` hangs a `DragPackPanel` off it — but only
  when the payload carries a `floor` square, since a drag inside the loot window
  or the drop modal already has a pack in front of it. `DRAG_END` takes it away.
- **It mounts to the LEFT of the board**, vertically centred on it
  (`_place_drag_pack`). The piece is on the board and the pack is where it is
  going, so the drag runs right-to-left and the panel sits at the end of that run
  rather than on top of where it started — covering the square the piece came off,
  and the squares around it, which is where a drag has to be able to end
  harmlessly when the answer is "not this one". It floats: **nothing on the page
  moves** to make room for it.
- **The grid is `LootGrid`**, the same class the loot window and the drop modal
  draw, with the bin (`LootTrash`) under it. Two flags are off that the drop modal
  sets — `show_use`, because nothing can be clicked with the mouse button down,
  and `allow_take`, because there is no modal table here to take *from*. On
  instead is **`allow_floor_take`**.
- **The payload is the pack's own** `{"kind": "loot_take", …}`, plus the square:
  `LootGrid.can_accept` keys off the presence of `floor` rather than off a second
  payload kind, so every rule about taking loot stays in the one place that
  already holds them.

**A full pack is a TRADE, not a wall.** A floor take is the only one with
somewhere to put what it evicts, so it is the only one allowed to land on an
occupied slot: the two pieces swap, and the carried one goes back onto the square
the new one came off (`GameState.swap_loot_entry_at` →
`Overworld2.take_floor_loot`). The pack's count never moves, nothing is conjured
or destroyed, and the square is never left empty — so a mistake costs a drag
rather than a piece. It is also the grammar the grid already speaks: dropping onto
a piece has meant "swap these two" since the pack was allowed to have holes in it.

**The bin asks first** (`LootTrash.confirm`, as it does for a carried piece).
Binning a floor piece is strictly worse than doing nothing — a piece left lying is
swept onto the haul screen and is still yours — so the one gesture on the board
that destroys something and gives nothing back is the one that gets a question.

**A click does nothing, deliberately.** A second way to take a piece would be a
second set of rules about a full pack, and the drag is the one with the good
answer. Reading a piece is still free: the hover card costs no gesture at all.

The floor is saved with the rest of the loop (`_serialize_drops`). A loot entry is
already JSON-safe — it is what the pack itself is saved as — so it rides across
whole rather than as an id to look up again: the roll it carries (a pill's colour,
a horse dose) already happened. A save written while the floor still held relic
chests reads back as a **bare floor**, since no square on the new board means the
same thing.

---

## 9. OBS companion overlay

**Built.** `scripts/autoload/ObsCompanion.gd` + the page in `obs/`. The
architecture this section deferred is settled, and it is **neither** of the two
options it named.

### 9.1 Why it is a browser source and not a second Godot window

The overlay is on screen precisely when the game window is **not**: the player is
off inside a real game for ninety minutes and the run's state is frozen behind
it. Both deferred options — a Godot `Window`, an always-on-top scene — solve that
by adding a second thing to capture, which means window capture, which means
fussy transparency and no way to restyle anything without a rebuild.

So the game does not render the HUD at all. It **writes the run's state to disk**
and OBS renders the page:

```
user://obs/overlay.html   the page          ┐ installed from res://obs/
user://obs/overlay.css    its styling       │ at EVERY boot — a stale copy
user://obs/overlay.js     its ticker        ┘ reads as a broken overlay
user://obs/custom.css     the streamer's own styling, created empty ONCE
user://obs/state.js       window.OBS_STATE = { … }, rewritten as the run moves
user://obs/covers/        covers lifted out of the .pck (exported builds only)
```

In OBS: **Browser Source → Local file → `overlay.html`**. The settings screen
prints the absolute path, because `user://` is somewhere different on every
platform and a streamer who cannot read it off that screen cannot set this up at
all.

**There is no server and no port.** The state travels as a `<script>` rather than
as JSON over `fetch()`, and that is the load-bearing decision: Chromium (which
OBS ships) refuses every `fetch()`/XHR a `file://` page makes at a sibling file —
no origin, so it is an unfixable CORS failure short of launching OBS with
`--allow-file-access-from-files`. A `<script src>` has no such restriction. So
the payload is written as an assignment, and `overlay.js` re-loads it four times
a second with a cache-buster. Covers travel the same way, as `<img src="file://…">`.

Writes are **debounced to 4/sec and deduped on content**, with a **5-second
heartbeat** underneath. The heartbeat is what lets the page tell "the run has not
moved" from "the game is not running" — identical on disk, very different on a
stream — so the overlay dims only when the beat actually stops.

### 9.2 What it renders

§9's original list, grown into the current build. In order down the strip:

- **The hero** — icon, level, and the health bar. Health is the bar's *width*
  first and a number second, and it pulses below 30%.
- **Shields and statuses as SPRITES, under the portrait**, which is where the
  board puts them and what they look like there (`BattlefieldView.refresh_hero`
  → `_fill_shields` / `_status_pip`). One shield sprite per shield — the pool
  that stays nearest and bare, the timed ones after it wearing the clock — then
  one pip per status: its art, its stack count, and the same clock when the
  stacks are on loan. **The tint is the board's rule, not buff/debuff**: a
  `bonus` or a `goal` on the player's side is an opportunity and reads gold,
  anything else taxes you and reads red. A status written out as its *name* is a
  word with no picture behind it, and this page is read at a glance from across
  a room. A status shipped without art falls back to its initial; a test asserts
  the catalogue never needs to.
- **Incoming damage and bodies following** — `incoming` is what the front line
  swings for if the next turn resolves as the board stands. This is the board at
  the resolution an overlay actually has; a 5×3 grid is not readable out of the
  corner of a stream.
- **The game in play**, its cover, the **attempts** spent on it, and the hops
  left to the Amulet.
- **The checklist**, live, and it is the point of the whole thing: a viewer
  watching someone play Hollow Knight has no idea they are doing it to "defeat 3
  bosses without healing". Every row the report panel would draw — body goals,
  bonuses, `instead` rows, the player's own status objectives, event goals,
  curses — each with whether it is ticked. It **scrolls itself** when there is
  more of it than there is room, and a row flashes green at the moment it ticks.
  Goal text is always `GameLoop2.goal_text_for`, never `enemy.goal` (§13).
- **Statuses on the player** as chips, borrowed ones carrying their clock.
- **The road** — `RunOverScreen`'s route strip drawn live: every stop walked,
  replays numbered, **ending on the Amulet whether or not the run got there**,
  drawn dashed until it does. Without that terminus the strip is a list rather
  than progress.
- **A ticker** of what just happened (beat a game, took damage, lost a run, found
  an item), which is also what stops the overlay reading as a dead PNG during the
  long stretches when nothing in the run changes.

**There is no headline goal line, because a game has no goal of its own** (§7.2).
The goals are the *bodies'* goals — every body following the run, not only the one
that arrived with the game in play — plus whatever a status, an event or a curse
is asking of the player. The checklist is the whole of it, and each row belongs to
the body or the clause that owns it and says so.

The rows are read from `GameLoop2` and `GameState` **directly, never from
`ReportChecklist`** — that is a Control tree which only exists while the
overworld is on screen, and being right when that window is behind a stream is
the entire job.

Everything must still read at a glance → keep all numbers single-digit where
possible.

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
- **Shields are ARMOUR, and a lost run is a TURN** (§3.2). Shields were once the
  *tries* at a game — granted on selection, one spent per lost run — which made
  one resource do two jobs and punished a bad evening twice. Now: a lost run costs
  **one enemy turn** and no shields (it was a flat 1 Health before that, which
  billed a number the board could not see), and a shield stops **one whole
  instance of damage**. The pool a game grants is **Temporary** and expires with
  it; what is gained off the board **stays** (§4.3). This replaced the earlier
  "Block carries over between games, no cap" rule. **Anchor** moved to the
  **`game_selected`** trigger so its +1 Temporary Shield arrives before you go and
  play rather than as a reward after the fact, and its wording now says so in the
  player's terms — "At the start of combat" rather than "When a game is selected",
  which was describing the menu action instead of the moment.
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
| Strength | `goal "the difficulty is increased {X} times or as much as possible" -> gain_chest reward {X}; gain_stat bash 1` | `clause "the difficulty must be increased {X} times or as much as possible"` |
| Speed | `goal "beaten in {1+(1/2)^(X-2):hours} or less" -> gain_chest reward {X}; gain_stat dash 1` | `clause "must be beaten in {1+(1/2)^(X-2):hours} or less"` |
| Marked | `demand "get {X} achievements" else -> take_damage 3` | `bonus "you get {X} achievements" decay -> gain_chest reward {X}` |
| Dexterity | `goal "{X} or all bosses were beaten without getting hit" -> gain_chest reward {X}` | `clause "you must beat {X} or all bosses without getting hit"` |
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

**Burn eats the paper you are carrying.** Every time Burn actually lands on the
player there is a **25% chance a random carried scroll is destroyed**
(`GameState._burn_a_carried_scroll`). Rolled once per application rather than
once per stack — Scroll of Fire's `+3 Burn` is one fire, not three chances at one
— on the gain only, and only on a gain that moved the number, so a decay and a
fourth stack the `Max: 3` ceiling eats both set nothing alight. It is scrolls and
not loot generally on purpose: a pill is a capsule, a potion is a bottle and a
card is a card, and this is the first rule that tells the four kinds sharing one
pack (§4.3) apart while they are still *in* the pack. It gives Burn a cost that is felt the
moment it lands rather than only at the next checklist. The scroll is named in
the toast by the mask the pack draws, so an unread one burns as "ZELGO MER" and
the player is left one mystery lighter with no idea which one it was.

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
| **Strength** | Buff | Slay the Spire | the difficulty is increased X times or as much as possible | [chest reward X], +1 Bash | deals +X damage |
| **Speed** | Buff | Mewgenics | beaten in 1+(1/2)^(X-2) hours or less | [chest reward X], +1 Dash | closes +X tiles per turn |
| **Dexterity** | Buff | Slay the Spire | X or all bosses were beaten without getting hit | [chest reward X] | +X Shields |
| **Marked** | Debuff | Mewgenics | you get X achievements | [chest reward X] on an enemy; on the player it charges 3 Damage for being missed | takes double damage, ignoring Shields |
| **Burn** | Debuff | Brutal Orchestra | skip or trash X items/upgrades (4-X on an enemy) | *nothing* — it charges 3 Damage for being missed | deals half damage |
| **Bleed** | Debuff | Mewgenics | don't heal intentionally | *nothing* on the player — it charges 3 Damage for being missed; [chest reward X] on an enemy | X separate 50% rolls of 1 damage **to itself** when it attacks |
| **Stun** | Debuff | Slay the Spire | beat a game twice in a row to set it as Completed | *nothing* on the player — it charges 5 Damage for being missed; [chest reward X] on an enemy | loses its turn |

**Bleed and Stun are the first two statuses whose clock is the BOARD.** Every
status above them either never depletes or depletes by having a side *completed*
(`Decrease: On Completion`); these two deplete by something HAPPENING —
`On Trigger` for Bleed, a stack per attack, and `Each Turn` for Stun, a stack per
turn the body takes. That is `StatusData.wear`, and it is why the Decrease column
is a table rather than a bool.

**On the player both of them mean *per game*.** The player neither swings nor takes
turns — the game *is* their turn — which is what "This lasts for X games" on both
player sides is saying, and why one column can carry a rule for each end of the
board. It is shed by *elapsing*, so a game you lost still spends a stack, where a
`clause` is shed only by being satisfied.

**Bleed rolls once per stack, not once for X.** Three Bleed is three coin flips for
1 damage each rather than one flip for 3, which is `StatusData.recoil_rolls` and
the reason `recoil` is the one additive combat field whose stack count is not in
its expression. A debuff the player is supposed to want to shed should bite little
and often; a single roll for X does nothing four games running and then takes a run.
The damage goes through `_damage_enemy`, so a body that bleeds out pays out and
fires its death abilities exactly as one killed by a bomb does.

**EVERYTHING THAT STUNS ANYTHING IS THIS STATUS.** The board used to keep a bare
`entry["stun"]` counter of its own — Stun the mechanic predated Stun the status by a
long way — and the two then sat side by side doing the same thing under one name,
with two countdowns, two save fields and two ways to be drawn. The counter is gone.
`GameLoop2.stun(instance)` applies the status, `is_stunned` asks the `skip_turn`
flag and nothing else, `Decrease: Each Turn` is the only countdown, and the ETA
arithmetic (`_turns_owed`) reads the stacks. A save written before the change folds
its counter in as stacks on load.

Three things fall out of that, and each is worth knowing:

- **A stunned body is drawn like any other status holder** — its own art in the
  status strip under the token, no ❄ badge and no pip of its own. The token still
  *cools toward blue*, because that is a property of the token rather than a second
  listing of the same fact.
- **Stunning a body hands it Stun's enemy side too**: the claimable bonus row "and
  if you beat the game twice in a row, Gain a [chest reward]". So Scroll of Scare
  Monster is now *skip its turn AND open a chest reward on it*, which is what the
  sheet's Stun row says applied consistently.
- **Sticky Bombs' `bomb_stun` is deleted**, not merely unauthored: the field, the
  `GameState.bombs_stun()` reader and the `_explode` branch are all gone, and
  `generate_item_tres.py` refuses the token out loud pointing at `bomb_tile web`.
  A bomb stuns by laying Web now.

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
  no "beaten in \<game\>" tally, no note (its confirm does not ask for one, the
  way a goal row's does), and no player `clause` ticks off it either, since a goal nobody met
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

**A BONUS ROW IS ARMED, NOT CLAIMED.** An optional objective hangs off a BODY, and
the body's own row is what says the body is finished with — so ticking a bonus says
*"I did that"* and pays nothing yet, and the reward lands when the enemy it belongs
to is cleared (either way: its goal row, or the `instead` that clears it the other
way). `GameLoop2.arm_bonus` / `claim_armed_bonuses` are the holding pen, and
`body_finished_this_game` is the question they wait on.

Paying at the tick let a player bank every optional reward on the board without
ticking a single enemy, and split one body's two halves across two moments. It also
means **a bonus row asks for no confirmation**: `_arm_row`'s *"did you really?"* is
the safeguard on a row that RESOLVES when answered — a body that cannot be
un-killed — and an armed bonus has done nothing, so unticking it simply disarms it.
The confirm comes back on the enemy's own row, where the irreversible thing happens.
A bonus ticked against a body that is already down pays on the spot; there is
nothing left for it to wait for.

**The rows are indented under the body they belong to.** An `instead`, a bonus and
a boss's nullified alternative are all one body's business, and drawn flush with the
enemy rows they read as top-level objectives that happen to be listed nearby.

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
  `apply_status` / `remove_status` / `status_objectives` (the claimable rows —
  **one per instance**, the owned stacks and each borrowed application separately;
  see docs/potions-design.md §5.4) / `status_clauses` (the taxes, which stay
  summed). Run-scope: cleared by `reset_run`, saved under
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
- **…and `GameLoop2.goal_addons_for(entry)` is the same thing as ROWS.** The
  sentence form runs every clause together — *"Defeat 10+ bugs and you must beat
  2 bosses without getting hit or instead skip or trash 3 items/upgrades"* — which
  is three different things joined by two conjunctions, in one colour, saying
  nothing about which of them makes the goal **harder**. So the parts are also
  available separately: `{status, stacks, games, kind, source, required, joiner,
  text}`, where `kind` is `clause` / `instead` / `bonus` and `required` is the bit
  the screens colour on. A **clause is a condition added** to the goal and reads
  RED; an **`instead` or a `bonus` is offered** — a way out, a free reward — and
  reads GREEN. `UITheme.addon_row` draws one, indented under the goal and led by
  the status's own symbol (clock badge included, so a borrowed clause still says
  how long it lasts); `UITheme.addon_color` is the rule on its own, for the
  offering's hover line, which has only the one line and so tints the words in
  place instead. `goal_text_for` is written from the same list, minus the
  `bonus` rows — optional was never part of the sentence of what is asked — so
  the row form and the sentence form cannot word an add-on differently.
- **The CHECKLIST draws rows too, in its own furniture.** Its enemy row carries
  `GameLoop2.entry_goal` and the enemy's name and nothing else
  (`ReportChecklist._goal_row_text`); each add-on hangs under it, indented, in the
  colour for its kind — `_add_clause_rows` red, `_add_instead_rows` and
  `_add_bonus_rows` gold. It used to print `goal_text_for` whole, which both left
  the half that HURTS unmarked and said the `instead` twice, since the instead
  rows have always been drawn separately. A clause row has **no tick box**: it is
  not something you claim, it is part of what has to be true before the row above
  it can be ticked. The **record** still takes the full sentence — a line in the
  completed-goals log has no rows under it to carry the clauses.
- **A body's statuses ride its checklist portrait**, as a strip of small chips
  under the picture (`ReportChecklist._buff_strip`), in the same place the board
  puts its pips. The clause rows only ever show a status whose goal-facing side
  did something; a Strength on the front-line body changes no goal and so said
  nothing on the one screen the player reads while deciding what to do about it.
  Capped at `BUFF_STRIP_MAX` with a `+N` chip past that, and flowed to the
  portrait's own width, because these rows have a 625px page to fit inside.
- **The winning-run REVIEW mirrors those pictures too.** The confirm behind
  "✓ Completed Game" is the last screen before the claim is irreversible, and it
  used to be the one place the leading symbol was dropped — so each row now
  carries a `mark` (which status at what stack, or which character), and
  `_review_mark` builds a second chip from it rather than reparenting the list's.
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
- a **unit** — something standing on it.

They **layer**: a unit stands on top of a tile effect, which is why they are two
sheets and two resources rather than one with a flag. What happens when a
particular pair meets is authored in the content, not in the code.

**A UNIT IS ANYTHING STANDING ON A CELL — an enemy and a boss included.** The word
used to mean only the player's own bodies, and `units2.0` is still the sheet of
*those*: a Landmine is the only row it has, and the dictionary called `units` in
`GameLoop2` is still that layer and not the stack. What changed is the **word**,
because the content started using it. Every wand in the roster is written about a
"Target Unit" (§5.5 of the wands design) and a player reading "Target Unit is
instantly killed" off a card has just pointed a stick at the thing they mean. So:

- **content and UI say Unit** when either kind will do, and say *enemy*, *boss* or
  *the player's units* when they mean one of them in particular;
- the wand verbs in `GameLoop2` (`kill_instance`, `cancel_abilities`,
  `polymorph_instance`, `split_unit`, `teleport_unit`) take an **enemy instance**,
  and `unit_kind_at` is how a caller holding a cell asks which kind is on it;
- **a boss is a Unit like any other**, with the one rule that keeps it a boss:
  nothing but its goal takes its last point of Health off it (§7.1). Damage from
  outside — a thrown potion, a zapped wand — chips it and floors at 1. **Wand of
  Death is the single authored exception**, which is what its Legendary rung and
  its one charge are paying for. A bomb still refuses a boss outright.

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
second grammar for the same triggers would only be a second thing to keep in
step.

(`TileEffectData`, not `TileData` — Godot already ships a native `TileData` for
TileMaps, and a `class_name` that shadows one is a parse error. The sheet, the
data folder and every id stay "tile".)

**Effect DSL** — `trigger: effect; effect; …`, the item sheet's shape:

| Trigger | When |
|---|---|
| `enemy_enters` | a body's footprint newly covered the cell — it stepped in, spawned onto it, was pushed into it, or the board grew and reseated it there |
| `enemy_turn_start` | a body was **already** standing here when an enemy turn began |
| `damaged` | the thing standing on the cell has taken enough damage to spend its `Health` |

The first two cover "walked into it" and "stayed in it", which is what a tile
effect has to be able to say to be worth putting down: a cell that only bit on
entry would be free to park on, and one that only bit at turn start would be free
to walk through.

**`damaged` belongs to the things with a `Health`** (`docs/potions-design.md`
§4.7, decision #24). The Landmine authors `damaged: detonate`, so a mine caught in
a thrown Explosive Ampoule's row goes up — and so does one caught in a bomb blast,
or in anything else that ever damages ground. It used to go off only under
somebody who stepped on it, which made its `Health 1` a number carried for
decoration. It is a **trigger** rather than a rule hardcoded to "0 Health runs
your `detonate`" because the next unit will want to react to damage differently: a
barrel that simply breaks, a totem that fires something off when shot. The trigger
says *what* happens; the `Health` column says *how much it takes*.

**Nobody triggered it**, so a `damaged` effect runs with no body attached: an
`apply_status` on that list has nobody to land on, which is the honest answer
rather than a guess at who was standing nearby. The list runs **with the unit
still on the cell** and it is cleared afterwards, because `detonate` goes back
through `detonate_unit`, which is what spends the unit, guards the chain and
carries the bomb modifiers — and which refuses a cell with nothing on it. A unit
whose `Health` ran out and whose list did not remove it is destroyed all the
same.

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

| | Fire (tile) | Web (tile) | Landmine (unit) |
|---|---|---|---|
| From | Brutal Orchestra's burn | *(spiders, everywhere)* | Brotato |
| Does | +1 Burn to anything that enters or starts its turn on it | +1 Stun to anything that enters or starts its turn on it | on contact with an enemy, destroys itself and explodes |
| Lasts | 3 games | **until it catches something** | Health 1 — going off spends the whole of it |
| Meeting a Landmine | the mine goes off and the fire goes out | *(nothing authored)* | — |

**WEB IS THE FIRST TILE WHOSE CLOCK IS MEASURED IN BITES**, and that is why
`decay_on_trigger` is a field rather than "1 Game" written differently. A web
nobody steps in is still there three games later; a fire nobody steps in is not.
It goes out inside `_fire_cell_triggers`, the moment it fires, rather than in
`_decay_tiles` where everything counted in games ticks.

It is also where the **Stun status** meets the board (§13.2): the tile applies
Stun, Stun's combat side is `skip_turn`, and its `Decrease: Each Turn` is what
counts the stacks back down. **Sticky Bombs lays it** — the relic's card has said
"Bombs Apply the Web Tile" since the sheet was rewritten, and the item does that
now instead of setting a `bomb_stun` flag, so it reaches Stun through the tile
layer like everything else. That flag no longer exists anywhere.

**A body pays per cell.** A 2x2 standing on two fire tiles takes two stacks a
turn — the same rule footprints follow everywhere else on this board (§7.3).

**A Landmine is a PROXY BOMB, and that is the whole reason it is a unit rather
than a one-off trap.** It spends none of the player's Bombs, but everything that
modifies a bomb modifies it, because there is one blast in `GameLoop2._explode`
and both go through it: **Brimstone** widens it to the row and column,
**Blood Bombs** pays its Health, and **Hot Bombs** and **Sticky Bombs** leave a
tile behind — Fire and Web respectively, off the same `bomb_tile` field. (Sticky
Bombs stunning survivors directly is gone with the counter it wrote to; the Web it
lays does the same job through the status, §13.2.) A mine is worth exactly what the pack has made bombs worth.
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
others: one `ItemDropModal` per defeated body (the drops were relic chests then,
one Small chest per kill), then the `LootDropModal`, then the
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
| **The verdict** | the game's cover and name, which of the three reports this was — beaten, goal missed, or walked away (they are three different things; see §2) — and **★ Rate this game**, beside the cover |
| **The fight** | damage taken and blocked, goals cleared, what is still following, shields left over or banked, the difficulty tier, and the board's growth if it just stepped (§7.3) |
| **The spoils** | every relic chest down the left — what *beating* the game paid, sized by the bodies that fell to it (§8.2) — **with the sum that sized it** — and the loot payout down the right: the game's own piece, plus everything the bodies dropped on the board and nobody stopped to pick up. **All of it at once** rather than one question after another |
| **The warning** | the boss notice as a banner rather than a sixth popup (§7.1) |

**AND EVERY CHEST THE GAME EARNED WHILE IT WAS STILL ON.** The checklist can pay a
chest at any tick — a goal cleared mid-game, a level-up taken, a status objective
answered — and each of those used to throw a full-screen `RewardScreen` over the
list the player was working down. A run of five rows meant four interruptions, each
one hiding the list behind the decision it was interrupting, and each one dropping
the player back to find their place again.

They are the same haul as the drop the game itself pays, so they wait for this
screen. `Overworld2._redeem_pending_chests` holds the queue while the phase is
`PLAYING` and `_open_post_game` hands it over on the way in — `pending_chests` is
run state and survives a save, so nothing is lost by waiting. A chest banked while
the haul screen is ALREADY up still lands on it, which is what that path always
did.

**★ Rate is here and nowhere else in the run.** It used to sit on the play
panel's checklist, under the Play button — offered while the game was still in
front of the player, which is the one moment they have not finished forming the
opinion it is asking for. Here the evening is over and its cover is right there.
It saves the score and stays put rather than opening the tier-list board the way
the select screen's own "★ Rate \<game\>" does: that board over a haul the player
has not finished taking is a screen in the way of a decision.

**The chest says why it is the size it is.** It used to arrive as an assertion —
a Large one under "what the evening earned", with nothing anywhere saying why it
was Large rather than Small, so the one reward that scales with how hard you
fought was also the one that could not be read as a consequence of your fighting.
The rule is simple enough to show, so the screen shows it as a sum under the
heading **ITEM CHEST SIZE**: a row of the faces that paid, each with its value
**under it**, `+` between them and the chest at the end. One small row above the
chest, wrapping rather than scrolling. The values sit under the pictures rather
than beside them because at 22px a number to the right of a face reads as part of
the next face along; underneath, each is unmistakably the caption of the thing
above it. The heading is there for the same reason a column needs one — a line of
faces and numbers is arithmetic without a subject until something names the
quantity it totals to.

The terms are `GameLoop2.chest_point_breakdown()`, banked at each kill beside the
points themselves and read *before* `claim_chests` empties the pool. They are
recorded rather than reconstructed from the report's own defeat list, because a
body a mine killed during a lost run is defeated inside `attempt_turn` and never
appears there — its points do land in the pool, so a screen that re-derived the
sum would under-count exactly the bodies the player is proudest of.

And **one button out, which names where it goes**: **"Go to Event"** when the
node owes one (clicking it is what opens the event, so the player leaves this
screen *into* the next thing rather than having the next thing dropped on them),
**"Go to Shop"** at a hub that owes no event, and **"Travel on"** when it owes
neither. The event wins when both are owed, because the event is what actually
opens next and the shelf is still under the board on the far side of it. It
counts what it is about to bin (`exit_text`), because a Legendary left on the
ground should be a decision and not a side effect of pressing Continue.

**The shelf is not a section of this screen**, and briefly was: a hub's shop was
mounted into the left column and handed back to the page on the way out, on the
reasoning that §14's "a shop blocks nothing and stays for the whole visit" was
right but the moment of *arrival* was never seen. What that produced was four
sections competing for a 720p canvas and a way out that could not honestly name
itself — a button reading "Go to Shop" beside a shelf the player is already
looking at describes nothing. So the shelf stays where §14 put it, under the
board, and this screen keeps only the hub's id to know that is where its exit
leads (`PostCombatScreen.shop_id`).

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

**The floor arrives here too.** A chest a body left on the board (§8.2) can be
opened mid-game, on the square it fell in; the ones nobody stopped for are swept
onto this screen the moment the game is reported
(`Overworld2._sweep_floor_into_the_queue`, straight after `beat_game`). So the
spoils column is the whole haul either way, and picking a relic up during the
game is a matter of *when* you answer for it, never of whether you get to.

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
