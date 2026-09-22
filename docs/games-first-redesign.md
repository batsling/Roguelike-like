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
2. The game presents what its **node kind** says it does (§19.1): an Enemies node
   stands **two** bodies on the board, each with its own goal and its own
   guaranteed loot drop, neither of which beating the game answers for on its
   own; a Champion node stands **one** boss; an Event or a Shop node stands
   nothing and hands over an event or a shelf instead. All four are a real game
   you go and play.
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

All eleven, as the sheet has them — the wordings all say "Beat a game…" now
because a level-up is settled by the run being won, and the `goals` sheet's pass
made every goal say when it is answered (§7.7):

| Character | Level Up objective | Reward |
|---|---|---|
| Rodney | Beat a game without meta progression | +1 Max Health, +1 Loot |
| Isaac | Beat a game while having used sorrow or self-inflicted pain as a weapon | +1 Small Chest, +1 Scramble |
| Zoe | Perfect a game by beating it without losing | +1 Dash |
| Minä | Beat a game while having crafted or combined a spell or weapon | +1 Transmute |
| Ironclad | Beat a game while having made a Faustian bargain | +1 Small Chest |
| Manager | Beat a game while having collected 3 different types of currency | +1 Push, +1 Gold |
| Regent | Beat a game while having made a friend | +1 Small Chest |
| Zagreus | Beat a game with the help of a God | +1 Large Chest |
| Poe Ratcho | Beat a game while being stinky | +1 Random Sized Chest |
| Antonio Belpaese | Beat a game while having used a whip as a weapon | +1 Random Sized Chest |
| Erratic Deck | Beat a game while having selected a random starting build | +1 Random Card |

How it already works in the project (to be kept):
- After each game, the **post-game verification modal** asks the character's
  `level_up_condition` as an honour-system **Yes/No**. Yes → apply `level_up_stats`
  and grant the reward (`_level_up_once`). So **each game is a fresh chance** to
  hit the challenge and level again — exactly as requested.
- **Crown** already exists as `bonus_level_up_chance` (roll an extra level-up);
  **Snowball** as `stat_gain_bonus` (+1 on a keyed stat gain). Both need only the
  new stat ids (transmute, bash, …) added.
- **Zoe's is the perfected-game one** and feeds the `perfect_aware` /
  `perfect_effects` verification path. It reads **"Perfect a game by beating it
  without losing"**, and it is worded that way on purpose: the flag is set by
  matching the condition's PROSE (`Overworld2._means_perfected`), because the
  condition has no machine-readable side. The match used to be a bare
  `contains("perfect")`, and the goals rewrite briefly took the word out — the
  flag stopped being set, nothing errored, and the symptom would have been a
  perfect-aware relic that never fires for the one character built around it.
  The goal now carries BOTH wordings `PERFECTED_WORDINGS` looks for, so neither
  is load-bearing alone, and `test_redesign2.gd` fails if a later pass drops
  them both. Giving the condition a real field is the durable fix and is a
  column on the sheet, not a change to make in passing.
- Rewards draw from the same resource vocabulary as drops (Max Health, Dash,
  Transmute, Scroll, Small Chest — see §8.1 Chests).

### 3.2 Shields, and the attempt tracker

These were one mechanic and are now two, which is the whole of this section.
Losing a run of the real game moves the **board**; shields are **armour** and
nothing but armour. And the armour comes in two pools named for the one thing
that separates them — **Temporary Shields** expire with the game that granted
them, **Shields** do not.

**A LOST RUN GIVES THE ENEMIES A TURN** — and, if you have defeated nothing at
this game, **a body as well** (§19.5). Every run of the game in play you lose
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
- **A board with nothing in reach charges nothing** *as a turn*, and that is the
  design rather than an oversight: the turn *is* the cost, so a cleared stack has
  nothing to take and a body still walking in merely walks. The tick is still
  logged — it is what the tracker shows. **This is the hole §19.5 fills**: an
  empty board used to mean the player having the worst evening paid the least,
  so a lost run at a game where you have defeated nothing now also *spawns*. The
  turn is free on an empty board; the body is not.
- **The gate is the GAME, never the board.** `can_log_attempt` asks
  `GameLoop2.game_in_play` — chosen and not yet reported — and nothing about what
  is standing. It used to ask `arrivals`, the record of which bodies walked on
  with the game (§7.2), which is the same answer right up until a body leaves the
  board some way other than the report: a wand, a bomb, a mine, a goal ticked
  mid-game. Clear the two bodies a game arrived with — one Magic Missile does it —
  and the tracker went dead mid-game with nothing said, which also made the rule
  above unreachable: the one board that charges nothing was the one board that
  refused the press. Clearing the board is not handing the game in.
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
| **Dash** | **As in the current project: a total select, not a skip** — pick *any* connected game and move to it (bypassing the normal limited offering). Costs 1 dash charge. See `Overworld._try_dash`. **Earned by going back**: beat a game **this run has already played** — cleared, failed, or walked away from — and it pays **+1 Dash** (`Overworld2._grant_repeat_dash`). The trip back is what earns it; the goal still has to be met on the return. The offering flags such a card with `⚡ +1 DASH`. **The Dash panel is a LIST, and it has the controls a list wants** — see *Searching the Dash panel* below. |
| **Scramble** | **Reroll the offering** — re-draw the games filling the (base three) choice slots, each with a freshly-rolled enemy/goal. At a node with no spare neighbours the slots hold and only the enemies change. Granted by the **D6** item. |
| **Push** | **Shove a following enemy one cell, in any cardinal direction.** Spends 1 push charge. *Back* is the classic use — delay its next attack by a game (§7.2), riding the same per-enemy delay counter as Stun but player-triggered. *Up / down* is a **lane change**, the one move enemies can never make for themselves, so it is how a blocked lane is opened or a clear one is plugged. *Forward* is legal too, and the player's own business. The verb is armed first and aimed second: press **⇤ Push** on the board's toolbar, click the enemy, then pick one of the arrows that appear on every side it could actually move to. Nothing is spent until an arrow is pressed. The **Manager**'s signature verb (gained on level-up: "Beat a game while having collected 3 different types of currency" → +1 Push). |

#### Searching the Dash panel

An ordinary offering is **three cards** and needs no controls at all. A Dash is a
**menu**: a hub has twenty connections, so the question stops being *which of these
three* and becomes *is the game I have in mind in here*. That is why the list has
been sorted A-Z rather than shuffled for as long as it has existed, and it is why
it now carries a **search box, a type filter and three sort orders**
(`Overworld2._rebuild_dash_bar`, `_dash_list`) — the Collection's controls, so a
player who has used the search there already knows how this one works.

The sort worth naming is **Closest to Amulet**. Every dash target is one hop from
where you stand, so "how far away" can only mean how much road is **left** after
taking it — the number the whole run is counting down. A game the distance map has
no answer for sorts to the **back**, not the front: "unknown" is not "nearly there".

Two rules keep a filter from ever becoming a lie:

- **Narrowing is not bashing.** What is filtered out is still connected, still
  reachable, and back the instant the box is cleared. `_dash_list` decides what is
  *drawn*; `_sorted_neighbors`, which the ordinary offering draws from, never sees
  a filter.
- **A filter never outlives the Dash that set it** (`_reset_dash_filters`, called
  when a Dash opens *and* when one is put down). A search left standing would
  silently shorten the next panel, and a silently shortened offering is the one
  thing an offering must never be.

A search that matches nothing says so in words, because an empty strip and a dead
end look identical and are opposite facts: the panel prints *"No game here matches
that — clear the search to see all N"* where the offering would print *"No
reachable games — dead end."*

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
existing `images2.0/scrolls/Unidentified.png`. Scrolls get the identical treatment:

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
and the card is only the **cover art, the game's name, its NODE KIND** (§19.1 —
Enemies, Event, Champion or Shop, as a badge, because what a card does to the
board is the same decision as what it does to the distance), **the Amulet's flag**
when it is the game the run is a search for — and **how far that game stands from
the Amulet**, in its own row under the flag and over the art ("*N* games away from
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
question. What it does **not** do is discount what the escape costs you on the far
side: the goal-enemy still walks on and follows you, and the game is still not
credited — an escape is not a win. You are buying the exit, not a pardon. Both
consumables that teleport (Scroll of Teleportation and the Telepill) come through
the one function, so both escape; one rule for moving the run off a game.

**But the road's extra turns (§7.4) are waived.** Those are the price of *finishing*
a game, and being carried off one by a scroll is not finishing it — the run already
paid, with the piece of loot. Charging them on top made the one thing a teleport can
do that nothing else can, getting you out of a game that is killing you, the use
most likely to kill you: on the Amulet's doorstep it handed the board two free
swings at a player who had just spent a consumable to get away from it. So
`escape_game` takes a `free_exit` flag, every teleport off a game in play passes it
(the scroll, the pill, Ride the Bus, the card teleports), and it reaches the model as
the last argument of `GameLoop2.beat_game` — `road_turns: false`. Everything else
still pays, and the one report that does not has to say so at the call site. It does
**not** touch Predatory Scent (§7.6): that is a body's own ability reacting to an
evening you did nothing with, not the road's price for the road.

**And so does every other teleport.** Ride the Bus (`teleport_to_type`) used to move
the run by hand — `travel_to_game` set the phase back to SELECT and that was that —
which walked the player out of a game in play for nothing at all: no goal-enemy
following, no report, no game left uncredited. It escapes first and arrives second
now, exactly as the scroll does, so an item that moves you pays the same fare — and,
being a teleport, is free of the road's extra turns on the same terms. Its one exception is
the return leg of a `play_game` detour (§10), which is not a teleport: that game has
already been reported by the time the run heads home.

**And the bus runs on the ROADS.** `teleport_to_type` used to draw from
`Data.all_games()` — all 882, the entire catalogue. The run's map is one connected
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

**A use ends by writing what it did and closing** (`LootUseModal._report_outcome`).

There used to be one more screen here — the art, the name, the effect lines, the
Health, and a **Done** button — and it is gone. It existed for a real reason: a use
that closed on the spot put the answer to *what did that do to me* into the run log
on the far side of the page, and on an **unidentified** capsule that answer is the
whole minigame. But the cure was worse than the complaint. Reading a scroll is one
decision, and it was costing two clicks and a full-screen panel drawn **over the
board the scroll had just changed** — the fire it lit, the body it stunned and the
square it teleported you to were all behind the report describing them.

So the account goes where the run's other accounts already go, and nothing is lost
in the move: **every effect line was already written to the log by `_on_read`**
before that screen drew it a second time. `_report_outcome` adds only what the log
did not already carry — Echo Chamber's attribution, and a wand's remaining charges
— and then closes.

Two facts get a **toast** instead of a log line, because a toast is on screen and
the log is not:

- **What it turned out to be**, when this use is what identified the piece. This is
  the case the old screen was really built for, and it is the one thing a player may
  act on immediately, so it is the one thing that must not be buried.
- **"Nothing happens"**, for a piece whose ops *all* no-opped. Silence after a click
  reads as a click that did not register, and that piece wrote nothing to the log to
  say otherwise.

The **pickers come first and the report last**: a request is part of what the piece
did, so a Scroll of Identify has nothing to report until you have chosen and a
Telepill has already moved you by the time it does. **Cancel is not a use** and
reports nothing at all.

**Every piece has to have something to say, and three of them didn't.** The log
can only carry what it is handed, and `read_scroll` / `take_pill` return their
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

> **THE CADENCE BELOW IS SUPERSEDED BY §19.6.** A boss is no longer the last
> *game* of a band. It arrives from a **Champion node** (§19.1), or on **every
> third spawn event** — where it lands on top of whatever else was spawning, a
> failure spawn included. Bands, tiers and the table below still describe which
> tier a boss rolls at; what changed is what counts the three.
> Everything else in this section — the heavier bomb-immune pool, triple gold,
> the boss's own chest — is unchanged.

**A boss is the LAST GAME OF EACH DIFFICULTY BAND.** A band is
`RunDifficulty.GAMES_PER_TIER` games — three — and the boss closes it, so the run
reads:

| | | |
|---|---|---|
| **Low** enemy | **Low** enemy | **LOW BOSS** |
| **Medium** enemy | **Medium** enemy | **MEDIUM BOSS** |
| **High** enemy | **High** enemy | **HIGH BOSS** |
| **Insane** enemy | **Insane** enemy | **INSANE BOSS** |

…and the Insane band repeats once the ladder caps. **Every third encounter is a
boss**, the first of them on encounter 3, and a boss rolls at **its own band's
tier** (`RunDifficulty.is_boss_game`, `Overworld2._current_tier`).

It used to be the game that CROSSED the gate — the boss stood *between* two bands
rather than inside one, which made the opening band four games long where every
later band was three, and put the first boss on encounter 4. Every band is the
same three games now, which is what makes the climb quicker: encounter 4 is a
Medium enemy where it used to be the Low boss, and every rung after it arrives a
game sooner. It also removed a special case — a boss on a crossing had to be
rolled at `tier_for(games_played - 1)`, one below the normal formula, because the
plain formula already reads the *next* tier there; a boss inside its band just
takes `tier_for`.

A boss is a heavier enemy that:

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

An enemy **spawns onto the battlefield the moment you choose its game** — if that
game is an **Enemies** or a **Champion** node (§19.1); an Event or a Shop node
stands nothing. **A body can also arrive mid-game**, off a run you lost or a game
you handed in having defeated nothing (§19.5), and it walks on at the same back
column on the same terms as everything else here.

Whichever way it arrived, from that moment it is an ordinary body on the board
with **no tie to the game that rolled it**: it takes its turns, it is drawn like the rest,
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

| Hops to the Amulet | Extra turns | Bodies per failure (§19.5) | Band |
|---|---|---|---|
| 5 or more | 0 | 1 | Distant |
| 3 – 4 | 1 | 2 | Closing |
| 2 – 0 | 2 | 3 | Doorstep |

**The ladder has two columns now.** The second is §19.5's — how many bodies a run
finished without defeating anything puts on the board — and it is read off these
same bands on purpose, so the board, the cards and the resolver cannot disagree
about either number. Everything below is about the first column; the second
follows the same logic, priced per failure rather than per report.

A **turn** is one action, and every enemy takes one on each of them: a body
touching column 1 **strikes**, everything behind it **steps** a column closer. A
turn is exactly the strike-then-advance the loop has always resolved — an extra
turn is that same beat, handed out for finishing a game near the Amulet.

**Finishing a game is what buys them, so a TELEPORT buys none.** Walking out of a
game on your own decision is finishing it as far as the road is concerned and pays
the full ladder; being carried off one by a scroll, a pill or the bus is not, and
the run already paid for that with the piece of loot. `escape_game(force,
free_exit)` carries the waiver and it reaches here as `GameLoop2.beat_game`'s
`road_turns: false` — see §4.1 for the whole of the reasoning. The turns a **lost
run** buys the board (§3.2) are a different ledger and are never waived.

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

> **SUPERSEDED BY §19.4.** The escort is retired as a concept: an Enemies node
> lands **two bodies** flat, neither of them the game's, and a Champion node
> lands **one** (the boss). The reasoning below is kept because §19 inherits its
> argument — the stack must be the baseline rather than the punishment — and
> because the boss-escort decision it records is one §19.4 explicitly overrules
> rather than forgets.

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

**The sheet says WHEN and WHAT; the loop says HOW.** `data/abilities2.0/*.tres`
(`AbilityData`) owns each ability's name, type, argument shape and sentence, and
its **`Effect`** column — the same `trigger: op args` DSL `tiles2.0` and
`units2.0` use — parsed into `AbilityData.triggers`. `GameLoop2` **dispatches on
that**, not on the id.

It did not always, and the old arrangement is worth recording because it is what
this replaced: the `Effect` column was empty in all 31 rows and every ability was
a hardcoded branch keyed by id. That made abilities the one content type whose
behaviour was not authored upstream — adding a row to the sheet gave you a name,
a type and a sentence, and nothing happened on the board until someone edited a
6869-line GDScript file, while every other system here (tiles, units, pills,
scrolls, potions, items) reads its behaviour out of its own `Effect` column.

The **triggers** are the points a turn actually has:

| trigger | when |
|---|---|
| `spawn` | true from the moment the body lands |
| `first_turn` | spends only its FIRST turn on this |
| `turn` | spends EVERY turn on this |
| `hit` | rides a swing that LANDS — a shield eats the rider with the damage |
| `death` | fires as the body comes off the board |
| `passive` | a rule the resolver QUERIES rather than an event it runs |

**`X` and `Y` are the row's own arguments**, spelled as the `Description` column
spells them: `X` is the numeric slot and `Y` the named one. Writing them as
tokens is what keeps one row good for every enemy carrying the ability —
`Infliction (2, Burn)` and `Infliction (1, Stun)` are the same effect with
different arguments, and the substitution happens at the **body**
(`BodyFacts.resolve_op_args`) because the catalogue cannot know the answer.

**The op vocabulary is the seam.** An ability built out of ops that already
exist is a sheet row and nothing else — author `hit: apply_status burn 2` and it
works. One that needs a new primitive adds the op to `GameLoop2.ABILITY_OPS`
with its implementation and to the generator's `OPS`, which is a much smaller and
better-marked surface than "somewhere in the turn resolver". The generator
**refuses to write** a row naming an op outside its list, and
`test_enemy_abilities.gd` checks the two lists agree from the engine's side too,
so an unimplemented op is caught at generation time rather than shipping as a
silent no-op while the card goes on promising it.

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

### 7.7 When a goal can be answered, and how many times

**Every goal in the game is authored in one place now.** The workbook's `goals`
sheet was built as a read-only VIEW — six owning sheets in five column shapes,
gathered so the roster could be counted — and it has been promoted to the
**source**. `tools/apply_goals_sheet.py` writes it out into the sheets the
generators read (`enemies`, `bosses`, `characters`' `Level Up`, `curses`'
`Condition`, and `statuses`' `On Player` prose); `--check` is what CI runs, and
an edit made to an owner sheet's goal column is lost on the next push.

That promotion is what made a consistent pass over the goals possible: 34 of the
134 were rewritten into one voice, and the counting ones were given honest
numbers. Two columns came out of it.

**`Ticked` — WHEN the goal can be answered.** Two values:

| Value | Rows | What the checklist does |
|---|---|---|
| `any time` | 99 | The box resolves **on the spot** (`ReportChecklist._resolve_goal_now`): the body takes its hit, its loot lands on the square, and there are no take-backs. What every goal used to be. |
| `game beaten` | 35 | The box **arms and disarms freely** and the **report** is what cashes it — the same shape the status goals and the level-up have always had, and it is mirrored into the review inside the ✓ Completed Game confirm. |

The distinction is not cosmetic. "Beat a game without using magic" is not true
until the game is beaten, so the old behaviour asked the player for a **promise**
where every other row on that list asks for a **report** — a box you could tick
in the first five minutes and then go and use magic. A `game beaten` claim that
is still ticked when the player reports a LOSS or an ESCAPE is dropped rather
than honoured (`Overworld2._honoured_fulfilments`), because neither is a game
beaten. The row is tinted like the level-up row; its own wording is what says so
out loud, which is exactly what the rewrite made true of all 35.

**`Count` — HOW MANY answers finish it.** Blank on 127 goals, and 2 or more on
the seven that count something ("Defeat 3 bugs", "Shoot down 2 flying enemies").
A counted goal is drawn as a **`−  2 / 3  +` counter instead of a tick box**, and:

- **Only the press that reaches the target confirms.** Every irreversible row on
  the checklist is guarded by one "did you really?"; a counted goal has exactly
  one irreversible moment, and asking three times would train the player to click
  through the question that matters.
- **`−` takes a press back**, up until the target is reached. It is the one
  answer on the list that can be walked back, because it is the only one that has
  spent nothing yet — a stray press on a row you are going to press three times
  is a misclick, not a decision.
- **The tally persists across games and reloads.** It lives on the body
  (`progress` in `GameLoop2.BODY_KEYS`), because the body is what persists: a
  goal can be answered in any later game (§2), so three bugs need not all be in
  one, and a counter that reset on the walk to the next game could never be
  finished. The standing checklist prints it too, since "2 of 3 done" is what
  decides whether this is the body worth finishing next.
- **It starts over when the goal resolves.** `health` is how many more goal
  completions a body needs, so a 2-Health body carrying "Defeat 3 bugs" is six
  bugs in two rounds of three.

Never `1`: a counter finished on its first press is a tick box with extra steps,
and the sheet rejects it rather than letting one through.

#### An enemy-side clause has to survive being bolted onto someone else's goal

A status's enemy-side `clause` is **ANDed onto whatever goal the body is
carrying** (`GameLoop2.goal_text_for`), and the body can be any of the 111 —
`any time`, `game beaten` or counted. So the clause is not a sentence of its
own: it is a phrase that has to read correctly after an arbitrary goal.

**Give it a subject.** The two that do compose everywhere:

| Status | Clause | Composed |
|---|---|---|
| Dexterity | "**you** must beat {X} or all bosses without getting hit" | "Become undetectable and you must beat 2 or all bosses without getting hit" |
| Strength | "**the difficulty** must be increased {X} …" | "Defeat 3 bugs and the difficulty must be increased 2 times…" |

Speed did not, and shipped as "must be beaten in {…} or less" — which composed
into **"Become undetectable and must be beaten in 2 hours or less"**, reading as
though the disguise is what has to be beaten. It is worst on an `any time` body,
where the sentence contains no game for a reader to recover the subject from,
and least bad on a `game beaten` one, which is why it survived. It now says
"**the game** must be beaten in …".

The three enemy-side **`bonus`** sides (Bleed, Marked, Stun) are exempt from this
rule: a bonus is drawn as a row of its own rather than joined to the goal, so it
never has to survive the composition. A **`instead`** (Burn) joins with "or
instead" and needs no subject either, because it replaces the goal rather than
qualifying it.

**A `instead` on a `game beaten` body is a genuine mixed row, and the box shapes
say so**: the goal's box is round (it waits for the win) while the `instead`
below it is square (it resolves on the spot), which is exactly right — the way
out really is available now even though the goal is not. Bosses refuse
`instead` entirely (§7.1), and 10 of the 14 `game beaten` bodies are bosses, so
this pairing only arises on the other four.

#### A `game beaten` BOSS is a hard gate, and that is deliberate

**10 of the 14 `game beaten` bodies are bosses**, and a boss is bomb-immune and
refuses `instead` clauses (§7.1) — so the only thing that removes one is beating
a game. On a losing streak it follows you and hits you after every game with no
way to clear it.

That is the intended reading, not an oversight. Before `Ticked` existed, a
boss's "Beat a game without using magic" was tickable in the first five minutes
of a game you then lost, which made the wall optional on the honour system. It
is a wall again: the pressure rises the longer you go without winning, which is
exactly the direction the run is supposed to push you.

Worth knowing before authoring more of them — a `game beaten` boss is the
strongest gate the game has, and there is no way past it but the front door.

#### What the checklist looks like, and why

**The two sections ARE the two `Ticked` values.** The report checklist splits by
**when a row settles**, not by what owns it:

| Header | Holds | Its boxes |
|---|---|---|
| `When beating a game:` | status goals, the level-up, event and curse rows, and every `game beaten` body | **arm** — on and off freely, nothing spent, the report cashes them |
| `Any time:` | the bodies whose goals resolve on the spot | **resolve** — a confirm, then the hit lands and there are no take-backs |

That head used to say `Enemies`, which grouped by OWNER. It picked out the same
rows only while every body resolved instantly, and stopped doing so the moment
`Ticked` made 14 of the 111 bodies settle on the win — those rows then sat under
a header about bodies, a few lines below the header naming the exact moment they
were answered, with nothing on them saying which one they obeyed. A body loses
nothing by moving: `bind_row_to_body` does not care where a row lives, and a
body's clauses, `instead`s and bonuses travel with it (`_add_body_rows`).

**Three signals carry the difference**, and they were added together because one
alone was doing too much work:

- **The section**, above.
- **The box shape** — `UITheme.check_icon`'s `armed` variant. A **square** box
  resolves; a **round** one holds a claim. Applied in `_arm_winning_row`, which
  *is* the set of rows that arm, so the rule cannot drift from the behaviour.
- **A drawn pennant** (`UITheme.finish_flag`) badged into a `game beaten` body's
  portrait. Drawn rather than a glyph, so it needs no
  `tools/build_glyph_font.py` rebuild and cannot fall through to a host font
  search.

**A goal row leads with the goal, not with "Cleared:".** The prefix used to open
every body row and it was a claim the row had not earned — an unticked row said
"Cleared: Defeat 3 bugs", an arming row said it about something that will not
resolve until the report, and a counter at 1 of 3 said it about two bugs still
alive. Whether a row is done is already said three times over by the box, the
green wash and the sink to the bottom of the list. **The ledger keeps the word**
(`record_completed_goal`), because a line is only written there once the goal
has actually been met.

**A counted goal's controls stack**: `+` over `−`, to the left of the tally, so
the pair reads as a spinner and costs the narrowest column on the page half the
width two side-by-side buttons took.

**Every row in a section leads with ONE thing, in a fixed-width slot**
(`LEAD_COLUMN_W`). A status leads with its symbol, the level-up with the
character's face, a body with its portrait — three different widths, which put
three boxes doing the same job at three different x. The badge therefore rides
**on** the portrait rather than beside it. Both numbers here are **measured off
a 1280×720 render**, not guessed: see the standing note in
[`layout-review-backlog.md`](layout-review-backlog.md) about judging colour and
position by sampling the rendered pixel, which is what caught the first two
attempts at this (a box 16px right of its neighbours, then one 10px left of
them, then a 26px portrait stretched to 44).

#### "run" means two different things, so it is no longer the word for either

A goal settled by beating a game and an enemy-side status clause were both
saying "run", and they are not the same run:

- **A GOAL's run is the one you WIN.** All 35 `game beaten` goals now say "beat
  a game" / "when beating a game", and so does the checklist section they live
  under — `When beating a game:` (was `On a winning run:`) — and both ledger
  lines that record one. Those are three separate literals on purpose, because
  the loop does not get to depend on the checklist and the checklist must not
  reach into the loop for a word; `test_overworld2.gd` asserts they agree, so
  drift is a failing test rather than one moment described three ways.
- **AN ENEMY-SIDE STATUS CLAUSE's run is the one you do the goal in**, which may
  never be won at all. A clause rides whatever body it is on, and 99 of the 134
  goals are `any time`. So those keep the word and say which run they mean —
  "in the run you complete the goal in".

**One authored string cannot be right for both**, which is the thing worth
knowing before touching this: a status's `On Enemy` clause is written ONCE and
attaches to any body. On a `game beaten` body the run it names IS the winning
run; on an `any time` body it is not. Wording it for the `any time` case is
correct under BOTH readings — "the run you complete the goal in" is the winning
run when the goal is completed by winning — whereas wording it for the winning
run would be wrong on 99 goals out of 134. So the general phrasing wins and no
per-enemy rendering is needed. If that prose is ever put ON SCREEN it would need
one: a placeholder in the clause resolved from the body's `ticked` at draw time.

**It is not on screen today.** What a player reads is built from the
`On Player Effect` / `On Enemy Effect` columns (`StatusData.condition`, via
`condition_text`), and none of those contain the word "run" at all.
`on_player_text` / `on_enemy_text` carry the prose and are exported but read by
nothing — so this pass corrected the SOURCE, not the build. Marked's
`achivements` typo lived in exactly the same place and never reached a player
either; the effect column had always spelled it `[achievement|achievements]`.

**Three sheets carry neither column** — `characters`, `curses` and `statuses` —
because a level-up, a curse and a status clause are already settled by the run
being won. Authoring a `Ticked` or a `Count` on one is a **hard error** in
`apply_goals_sheet.py` rather than a silent drop, since the value would otherwise
vanish on the way through and the goal would keep behaving the way it always did
with the sheet saying otherwise.

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

**The Slay the Spire 2 pair** are one relic each on a hook the loop had never
named, and the pair is the reason both hooks exist: **Dragon Fruit** (Rare,
`shop`, +1 Max Health whenever you obtain any amount of gold) and **Lucky Fysh**
(Uncommon, +1 Gold whenever you obtain a Card). Between them they close the two
obvious "whenever" moments the run was still silent about — the purse going up
and the pack taking a card — and they chain in one direction: a card pays a
coin, and the coin pays a point of Max Health. See `gold_gained:` and
`card_obtained:` below for where each fires and, just as importantly, where it
does not.

**The Risk of Rain 2 trio** are three relics about the Health pool and the
ground, and only one of them needed a hook that already existed. **Infusion**
(Uncommon, +1 *empty* Max Health per body defeated) is two existing halves put
together — `enemy_killed` has been a run-scope trigger since Charm of the
Vampire, and `gain_empty_max_hp` since Hollow Heart — so it is a pool that grows
all run and never fills itself, which is exactly what makes it a relic that wants
a healer beside it. **Rejuvenation Rack** (Rare, "double the effect of all
Healing") is the healer, on the new `heal_multiplier:` flag below, and the two are
deliberately the halves of one pool: the Rack doubles the heal that fills the room
Infusion made. **Gasoline** (Common, Fire on the square a body fell in) is the
odd one out — it is about the *ground* rather than the pool, and its
`death_tile` flag is documented where the rest of the ground content lives
(§17.3).

**Censer and Fanny Pack** are the two Isaac relics added after the seven, and
each is an answer to being hit rather than a way of hitting back. **Censer**
(Uncommon, `angel_room`) takes one of the road's extra turns off every body in the
**front column**, so the closer the board gets to you the more it is holding back
— armour that is worth nothing while the front line is empty and most when it is
full. **Fanny Pack** (Uncommon) pays the other way round: half the times you
actually lose Health, a piece of loot lands **on the battlefield floor**, which
turns a hit into a reason to go and stand somewhere. Both needed a word the sheet
did not have (`front_column_slow`, `drop_loot N`), and both are in the table below.

Three more run-scope hooks and four more flags carry the Isaac relics, and they
are listed here because each is a *moment* or a *rule* the 2.0 loop did not
previously name:

| Token | What it is |
|---|---|
| `health_lost:` | A trigger prefix — the player's Health went **down**, from any source anywhere in the run. Not `damage_taken`: Shields absorb first (§3), so a swing they eat whole is damage taken and no Health lost, and **Piggy Bank** must not pay for it. Emitted once per loss by `GameState.change_hp`, the choke point every drain funnels through, so an event's bill and the swing a failed try bought count exactly as an enemy's swing at the end of a game does. A failed try is the one Health loss that can be **undone**, and `GameLoop2.undo_attempt` restores what the tick's turn moved — the purse it minted included, otherwise the undo would be a coin press. |
| `run_lost:` | A trigger prefix — the player pressed the button that logs a **lost run** at the game in play (§3). Fired once per press by `GameLoop2.log_attempt`, *before* the turn the tick costs is resolved, so what an item hands out here is standing when the board swings. The context carries `goals_met`, how many goals this game has paid out so far, which is what `if_goals=` reads. Inside the snapshot `undo_attempt` restores, like everything else the tick moved. **Ripple Basin** is the item. |
| `gold_gained:` | A trigger prefix — the player's purse went **up**, from any source anywhere in the run: a report's payout, an event, another relic, a body's coins. The mirror of `health_lost` in every respect, including where it is fired from: `GameState.change_gold`, on what the purse **actually took**, so one payout is one event whatever its size. Deliberately NOT on `set_gold` — the run's opening purse (§14) is not gold you obtained, and the number an undo puts back is not a payout. **Dragon Fruit** is the item, and it is the one hook that can pay in its own currency, so `_on_gold_gained` refuses to re-enter: a relic answering gold with gold pays once and stops. |
| `card_obtained:` | A trigger prefix — a **card** of the loot kind (docs/cards-design.md) **entered the pack**: rolled off a report's payout, dragged off the battlefield floor, bought, traded in. The pickup twin of the `card_used` hook, and neither one has anything to do with the retired combat deck's `card_played`. Fired once per card by `GameState._note_loot_gained`, the choke point every take funnels through — so a card the pack had **no room for** pays nothing (the cap is a refusal, not a silent drop, §4.3) and a save load, which rebuilds `loot_items` directly, never re-pays a run's pickups. **Lucky Fysh** is the item. |
| `potion_used:` | A trigger prefix — a potion was **drunk or thrown**. One event for both, because that is how the wording reads (**Reptile Trinket**: "whenever you drink *or throw* a potion"), and a bottle that fizzled on empty ground was still spent. Emitted once per use by `PotionSystem.notify_used`, the choke point both sides go through. |
| `if_goals=N` | A **gate** on the trigger before it, not a trigger of its own: the hook fires, and the item's effects only run when the context's `goals_met` is exactly N. Ripple Basin's `if_goals=0` is "before completing any goals". A hook that carries no goal count at all **refuses** a gated trigger rather than passing it — a gate is a narrowing, and "this hook can't answer that" is not a free pass. |
| `enemy_killed:` | A body was **defeated** (`GameLoop2._defeat`). A bombed enemy is destroyed rather than defeated and never reaches it, the same rule that decides whether the body pays gold (§14). **Charm of the Vampire** counts them. |
| `counter key=K every=N -> …` | The **incremental** wrapper: fire the inner effects on every Nth time, then roll the count back to zero. The count lives on the inventory slot, not on the run — see the `Incremental` row above. |
| `boss_chest_bonus: N` | **There's Options.** Chest points added to a boss's drop; see §8.2. |
| `heal_multiplier: N` | **Rejuvenation Rack.** Every **heal** lands at this multiple. Read at `GameState.change_hp` — the one choke point every gain in the run funnels through — so a pill, a potion, an event's payment and a relic's report payout all double without any of them knowing the Rack exists, exactly as `health_lost` is fired from that same point. **A heal is Health arriving in a container that already exists**, and that is the line the flag draws: the fill that comes *with* a bigger container is not one, so "+2 Max Health" still pays 2 and not 4 (`_h_gain_max_hp` says so out loud by tagging it `HEALTH_SOURCE_MAX_HP_FILL`, the one `source` ever read on a gain). Multiplies across copies like `loot_multiplier`, because "double the effect" applied twice is quadruple. |
| `death_tile <tile>` | **Gasoline.** The tile effect left on the square a **defeated** body fell in (§17.3) — the twin of `bomb_tile`, and its own field precisely so the two can disagree about bombs. |
| `front_column_slow` | **Censer.** Every body standing in the **front column** — the ones already in reach of you — sits out one of the extra turns the road hands the board at a report (§7.4). It touches that column and no other on purpose: a body further back spends its turns *walking*, so draining one there would only slow the approach, while in the front line a turn is a hit, which makes this armour that stops mattering the moment the front line is empty. Read off each body's **live** column inside the turn loop, so something that steps up mid-resolve is held off on the turn it arrives; stacks like `grid_grow` (`GameState.front_column_turn_drain` counts the copies). The turns a **lost run** buys the board (§3.2) are untouched — those are the ones you paid for by failing, and "Extra Turns" names the road's. |
| `drop_loot N` | **Fanny Pack.** N pieces of loot rolled onto the **battlefield floor** rather than into the pack — the twin of `gain_loot`, and the difference is the whole item. A relic that paid into the pack on every hit would be flat income; one that puts the piece on a random free square turns being hit into a reason to walk somewhere, on exactly the terms loot dropped by a defeated body is on (it lies there until picked up, and the report sweeps what is left, §18). A floor with no free square pays nothing rather than stacking two pieces on one cell. |
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
user://obs/covers/        every picture the page shows, staged beside it
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
a second with a cache-buster.

**And every URL the page uses is RELATIVE to it**, which is the same decision
seen from the other side. An absolute `file://` URL is a local resource load, and
Chromium refuses one from any document that is not itself `file://` — which is
what OBS gives the page. The covers were the only absolute thing here, and so
were the only thing that broke, invisibly, on every stream. They are staged into
`user://obs/covers/` beside the page now and travel as `<img src="covers/…">`.

Writes are **debounced to 4/sec and deduped on content**, with a **5-second
heartbeat** underneath. The heartbeat is what lets the page tell "the run has not
moved" from "the game is not running" — identical on disk, very different on a
stream — so the overlay dims only when the beat actually stops.

### 9.2 What it renders

§9's original list, grown into the current build. In order down the strip:

- **The hero** — icon, level, and the health bar. Health is the bar's *width*
  first and a number second, and it pulses below 30%.
- **What a lost run costs, as a SENTENCE** — the line the hero card is *for*.
  A lost run is not an abstract penalty: the enemies take a turn (§3.2), every
  body that can reach you swings once, **one shield stops one hit outright
  whatever that hit was for** (`_take_hit`), and the swings past your last shield
  are what reaches Health. That rule is invisible in a summed "12 incoming" — two
  shields against three small swings is a completely different position from two
  shields against one enormous one — so the overlay states it: **"2 shields
  break, −12 Health"**, saying *Health* rather than *damage* because the bar
  directly above reads `7 / 20` and the two numbers a viewer has to connect
  should have the same name. The same forecast is hatched onto the health bar
  over the HP that would go, and a forecast that would end the run says so in
  words.

  **WHO is throwing each swing is answered on the checklist now, not here.** This
  line used to draw one mark per swing — the body's own art at 28px, badged with
  a shield when the swing was eaten whole (the face behind it desaturated) or
  with the damage when it was not — because it was the only place the page said
  *who*, and the boss's swing and the fly's are not the same problem. Every body
  now has a checklist row carrying its face and its own damage, so the identity
  sits beside the sentence that names it rather than in a parallel strip the
  viewer had to align against the real list by eye. The art still survives being
  drawn small — checked by rendering the widest range in the set (a 19×10 sprite
  through a 734×841 painting) at 22 / 28 / 34 / 40 rather than assumed — and a
  row with no art falls back to an initial, which a test asserts never comes up.

  It **mirrors `_take_hit` rather than re-deriving it**: the player's damage-taken
  mods first (Marked doubles what lands), a swing modded to nothing spends no
  shield, Pierce takes both pools past, and the timed pool blocks first (§4.3).
  Bodies that are staggered, stunned or still out of reach are excluded, and
  reach is `can_strike` rather than `in_front` — a Ranged body hits from further
  back (§7.6) and counting only the front column understated the cost for every
  one of them. It is a **forecast and not a promise** (an ability can spend a
  body's turn on something else) and nothing in it mutates.
- **The cost line is a label and two numbers**: `On next loss  −2 Shields,
  −12 Health`, or `N/A` when nothing lands. It never hides — a row that
  disappears moves everything under it, and this line sits at the top of the card
  — and it goes blue rather than red on an empty forecast.

  It has been three things. A strip of one mark per swing, then a sentence ("2
  shields break, −12 Health", and on an empty forecast *"nothing reaches you for
  at least 2 more lost runs"*), and now the total alone. Each cut moved
  information to where it was already being drawn: the swings' identities to the
  checklist rows, and now the quiet count off the page. `threat.turns_away` is
  still computed and still in the payload — from `GameLoop2.turns_until_strike`,
  which is `can_strike`'s own inequality (`_front_col <= 1 + strike_range`)
  rearranged so the two cannot drift apart, **measured against each body's own
  reach and never against column 1** (counting steps to the front line would
  promise a quiet turn to somebody a Host can already shoot, which is the one lie
  this page must not tell), and a **floor**, since a blocked lane, a stun or a
  turn spent on an ability all make the real wait longer and never shorter. It is
  one line of `overlay.js` for anyone restyling the page who wants it back.
- **Shields as SPRITES, on the health bar's own line** — the same art the board
  draws (`BattlefieldView.refresh_hero` → `_fill_shields`). One sprite per shield:
  the pool that stays nearest the bar and bare, the timed ones after it wearing
  the clock. They had a labelled row of their own while the statuses had another
  beside it, and the labels were there to stop the two strips being read as one;
  with the statuses gone to the checklist there is nothing left to confuse them
  with, so the label was a word doing no work above a whole line of the page spent
  on a handful of 22px sprites. Beside the bar they read as what they are: the
  armour standing in front of that health, and what the cost line above spends.
  **The statuses no longer have a strip here.** Every player-side status on the
  roster is `is_claimable` (3 `goal`, 4 `demand`), so every one of them already
  had a checklist row saying what it wants — and the strip was saying the same
  thing a second time with a picture but no sentence, while the row had the
  sentence and no picture. The row now has both.
- **The run, in ONE card.** It was two — a hero card and a headline — and the
  hero card led with a portrait and a name, which is the thing on this page a
  viewer needs least: which character is being played is a detail of the run, not
  the premise of it. What was left of it after the statuses moved to the checklist
  was a health bar, which is not a card. So the premise leads and the stake sits
  under it: the game in play, where it leads, then health, armour and what one
  lost run costs.
- **The headline: the game in play, and the game the whole run is for.** Two
  columns on one line, each with its cover to the left of its name, each under
  its own label: CURRENT GAME, and *"3 games to Amulet"*. This pair **is the
  premise**, and it is the one thing a viewer who has just tuned in cannot get
  from a health bar and a checklist. The Amulet used to be legible only off the
  right-hand end of the road strip, which scrolls: measured on a 22-stop run it
  was fully on screen 12% of the time. **A destination cannot live inside
  something that scrolls away from it.**

  It was a full-width line UNDER the game in play, on the reasoning that two
  columns do not fit: 440px less the covers and the hop count left ~224px to
  split between two real game titles, and both truncate. Three changes paid for
  the column. **The hop count left the line** — it is the destination's label
  now, above the cover it belongs to, which is also where it stopped needing the
  words "to the" spelled out. **The covers came down** (46×62 → 38×51, and the
  Amulet's 22×30 → 30×40, the two now peers). And **both titles clamp to two
  lines** rather than the destination taking one ellipsised line, so whichever
  wraps, the halves bound each other and the card is the same height either way.
  The truncation the old reasoning warned about is real and accepted: a long
  title takes two lines and then ellipsises. What it buys is 71px off `#top`,
  which is what lets the road into a scene column at full camera size. The
  attempts already spent ride under the current game.
- **The speedrun clock** (`RunTimer`). A run here is a stack of real games played
  one after another, which is a speedrun with unusually long splits, so it is
  timed like one: this game's split with tenths on it, the run's total behind it,
  and one banked split per game finished — tinted by how the board closed
  (beaten / missed / escaped) and carrying how many tries it took.

  **It starts on the game the run STANDS ON**, not on the "▶ Play" button: that
  button only exists where a launch target is authored, so a clock hung off it
  would read zero for most of a run. It stops when the game is reported, on all
  three outcomes — an escape that left the clock running would run forever. A
  reported loss does *not* pause it (a speedrun clock counts your failures); it
  banks the attempt as its own split, and an undo hands that time straight back.

  Time accumulates while the game is OPEN rather than between two wall-clock
  stamps, so a run left overnight comes back where it was, and it rides the save.
  The page counts the running seconds forward itself between writes — they are
  excluded from the payload's dedupe, or `state.js` would be rewritten four times
  a second for a run in which nothing else moved. It is on the default page and
  has a source of its own (`timer.html`), and the same numbers are drawn beside
  the cover in the game's own Now Playing panel.
- **The checklist**, live, and it is the point of the whole thing: a viewer
  watching someone play Hollow Knight has no idea they are doing it to "defeat 3
  bosses without healing". Every row the report panel would draw — body goals,
  bonuses, `instead` rows, the player's own status objectives, event goals,
  curses — each with whether it is ticked, and the card's label carrying **how
  many of them are done**, because the list scrolls and a viewer should not have
  to watch a whole cycle and count. It **scrolls itself** when there is more of it
  than there is room, and a row flashes green at the moment it ticks. Goal text is
  always `GameLoop2.goal_text_for`, never `enemy.goal` (§13).

  **THE CHARACTER'S OWN GOAL LEADS IT** — `Level up — <condition>`, wearing the
  portrait, with `Isaac · Level 3` beneath. `ReportChecklist` has always drawn
  that row and this page never did, so the one goal belonging to the CHARACTER
  was the one goal a viewer could not see; the portrait and the name live there
  now instead of on a hero card of their own. It goes FIRST here where the
  checklist files it after the statuses, and the departure is deliberate: the
  report panel does not scroll, so a row's position costs nothing there, while
  this list does — and on a fifteen-body run a row near the end is a row nobody
  watching ever sees. Keyed on `ReportChecklist.LEVELUP_KEY`, never on the string
  spelled again, so a row the overlay calls done is one the checklist has locked.

  **HEADED BY THE CHAT COMMAND, THEN "THE GOALS".** The header was cut once, on
  the grounds that a list of ticked and unticked rows is self-evidently a
  checklist — true of a viewer who has been watching ten minutes, and false of
  one who arrived four seconds ago, which is most of them. What the label
  actually names is the BOUNDARY between the two cards: the run card above is
  about the streamer, this one is a list of demands, and unlabelled the page
  reads as one column of facts. It comes back as the label alone; the "3 / 9"
  that used to sit beside it does not, because that really was a second way of
  counting rows the viewer can already see.

  **The chat command sits above the label** — `!roguelikelike for challenge
  details` — because it answers the question these rows provoke. A viewer reads
  "Reach the second boss without spending a healing item", wants to know what
  the run's challenge *is*, and the overlay is a status readout with no way in;
  this is the way in, and it belongs on the card that raises the question. It is
  the only text on the page addressed to the VIEWER rather than describing the
  run, which is why it is accent-coloured and the heaviest small text here: a
  command has to look like something you can do. It was drafted in a monospace,
  on the reasoning that a command is typed character by character — and the
  measurement killed it, because a monospaced 12px line filled the column
  exactly and dropping to 11px to buy slack put it at 4.55 against the
  sampler's 4.5 floor. Legible over a bright capture beats uniform advance
  widths; `check_overlay.js` samples this line and asserts its slack.

  It is **text in the page, not payload** — the game does not know what anyone's
  bot is called — so it is edited in `obs/overlay.html` or hidden from
  `custom.css`. The two lines cost the card 42px, which is why the source the
  README recommends went from 640 to 680 tall.

  **EVERY ROW WEARS ITS OWN ART**, and this is the layout's one big idea. A goal
  *is* an enemy (§7.2), and a column of sentences never said so; with the face on
  the row the checklist reads as the board. A body's row carries its face and, on
  the corner of it, the damage that body lands if the run is lost. A status's row
  carries its pip art and, on the corner, **the stack total** — `status_objectives`
  is one row per instance (a permanent Strength 1 and a borrowed Strength 3 are
  two offers with two deadlines) while what a stack *does* is felt as a total, and
  the hero card's strip was the only thing carrying that. A curse's and an event's
  rows carry theirs. A `bonus` or an `instead` deliberately carries none: it hangs
  off the body whose row is directly above, so repeating that face would draw one
  enemy two and three times running and read as two and three enemies — it is
  indented under its parent instead.

  It also fixes the weakest encoding on the page. The six kinds of row used to be
  told apart by **text colour alone**, on an identical checkbox at an identical
  weight, with nothing anywhere saying what a colour meant — purple-curse against
  blue-status is not a distinction that survives being read across a room through
  a lossy encode. The art says it first now and the colour agrees, which is the
  same "say it twice" rule the road's stops already followed.

  **AND THE CHECKBOX IS GONE, so the art is the row's left edge.** Every row used
  to open with a `□` or a `✓` in a column of its own, which spent 21px of every
  row saying what the row already said three ways over: a finished goal is struck
  through, dimmed and drained to greyscale, and it flashes green at the moment it
  is crossed off. At 15px a `□` and a `✓` differ by about six pixels anyway,
  which is not a distinction this page can rely on — the same argument the colour
  encoding lost above. The art took the space and grew from 24px to 32px, and
  what the box's red used to say (**the body in your face right now**) is a red
  ring around that body's picture instead: louder, and on the thing it is about.
  The column paid for the widening out of the same 21px and still came out ahead,
  which is what let it narrow from 380 to 352.
- **The road**, at `road.html` — **its own source, off the default
  column.** `RunOverScreen`'s route strip drawn live: every stop walked, a game
  stood on twice drawn twice (the road is a sequence, not a set — a badge saying
  "2" made two visits look like one), each stop **green if it was beaten on that
  visit and orange if the run walked away from it** — a missed goal, an escape
  (§3.2) or a teleport straight through are one colour because to the road they
  are one fact — **ending on the Amulet whether or not the run got there**, drawn
  dashed until it does.

  It is opt-in because **at the column's width it could not be read**. It scrolls sideways on
  the same walker the checklist uses, and measured on a 22-stop run (1008px of
  strip in a 390px window) the stop the player was standing on was fully visible
  for **6 seconds in every 50**, took 42 seconds to first appear, and every change
  to the road reset the walk to the *start* of the run — which is exactly when a
  viewer looks up. No styling fixes that; the strip is simply wider than the
  column. What it uniquely says — which games were beaten and which the run walked
  away from — earns a source of its own on a between-games scene, at a width where
  it does not have to scroll at all. The **distance** it was carrying moved to the
  headline, into a number that never moves.
- **The route map**, at `map.html` — **the road's opposite number, and
  the second source you toggle.** The road is where the run has *been*; this is
  where it can *go*: every optimal road from the game in play to the Amulet.

  **IT IS A GRAPH AND NOT A STRIP, and that is the whole design.**
  `RunGraph.shortest_path_dag` answers in LAYERS two or three games wide — there
  is usually more than one equally short way on, and choosing between them (same
  distance, different goals, different loot) is the run's core decision (§6).
  Flattening that to a line would draw a forced march and hide the only
  interesting thing on the map. So it is `RunMapModal`'s ladder, drawn live:
  rungs in layers, green arrows between them — STRAIGHT lines carrying heads,
  since a wire lives entirely within the gap between two layers and no box is in
  that gap, so the cubic curves this shipped with were avoiding a collision that
  cannot occur and read as wobble rather than as a road; the head is what says
  the graph runs one way — in `RouteLadder`'s own colours —
  blue for where you are, ember for the Amulet, purple for a pin — so the map on
  the stream and the map on the streamer's screen are visibly one object.

  **IT HONOURS THE PIN.** With a `route_waypoint` set, the road being walked is
  the FORCED one, so that is what is drawn — `route_dag_via`, exactly as the two
  in-game maps ask for it. Drawing the shortest path instead would show a route
  the player has already decided against.

  **NODES ARE KEYED (depth, id), NEVER id**, in the payload and on the page, for
  the reason `RouteLadder.node_key` gives: a forced route walks to the waypoint
  and then walks on, and the way on is free to come straight back over the games
  that led in, so one game legitimately holds two rungs at two depths. Keying by
  id merges them and draws arrows into a step of the route that does not exist.

  **FULL SCREEN, LEFT TO RIGHT, AND OFF THE DEFAULT PAGE.** A ladder needs width
  per layer and height per step, which the 352 column has none of. It runs left
  to right — you on the left, the Amulet on the right, each layer's choices
  stacked — because DISTANCE BELONGS ON THE LONG AXIS: a 14-layer route gets
  137px per layer across 1920 and 77px down 1080. The in-game `RunMapModal` runs
  the other way and should, being a tall modal in a 16:9 window; this is a 16:9
  source and reads as the road strip does. Past 14 layers the payload trims the
  far end and the page says how much it dropped.

  **EVERY DIMENSION IS A FRACTION OF ONE SOLVED NUMBER**, the rung's width, which
  the page solves from the room the source gives it on BOTH axes (a shallow wide
  route is bound by its tallest layer, a deep narrow one by its length). Covers,
  type, gaps and arrow weight all ride on it, so the ladder is the same object at
  100px and at 300px, and it grows into whatever source it is given.

  **THE FIRST VERSION DID NOT, AND THAT IS THE LESSON.** The rung was a flat
  152px and the fit only ever scaled DOWN, so a full-screen source drew exactly
  the ladder a 640-wide one did and put a thousand pixels of empty card around
  it — going full screen made the map WORSE. Nothing caught it, because every
  assertion was about the ladder fitting INSIDE its panel, and an under-sized
  ladder satisfies that perfectly. "It fits" is not "it fills"; a layout check
  that only bounds a thing from above cannot see it shrink.

  Every rung is a cover AND a name — the cover is what a viewer recognises, the
  name is what they can search — with the name held to three lines at a fixed
  height so a layer reads as one rank of equal choices. A game already beaten is
  drained and tagged, because a revisit is legal and rolls a fresh goal but you
  know the game.

  **THE TWO EMPTY STATES SAY DIFFERENT THINGS.** Standing on the Amulet is the
  run's best moment; no road at all is a dead end. Neither may draw the blank
  panel that a viewer reads as a broken source.

**IT RENDERS IN PIECES, AND EACH PIECE IS A FILE.** OBS cannot interleave scene
items with the inside of a browser source, so the page renders part of itself and
a scene points several sources at the pieces: `top.html` (the run card),
`bottom.html` (checklist and ticker), `goals.html` (the checklist alone),
`road.html`, `map.html`, and `overlay.html`, which is everything but the last two.

**THE PIECES ARE GENERATED FROM overlay.html AT EVERY BOOT** — each is the page
with one line in front of it, `window.OBS_VIEW = "map"`, written by
`ObsCompanion._install_views`. There is one copy of the markup and five pages that
cannot drift from it.

**AND THE FRAGMENT THEY REPLACE IS A LESSON WORTH KEEPING.** The original
mechanism was `overlay.html#map`, and it is unusable in the only program it is
for: with "Local file" ticked OBS's field is a PATH, so the `#` is escaped and
never becomes a fragment, and unticking it to paste a `file:///…#map` URL does not
arrive either. It worked in a browser, was asserted in `check_overlay.js`, and was
documented in three places — every one of which tested the PAGE and none of which
tested the PROGRAM. A mechanism the user cannot express is not a mechanism, and
"it renders correctly in headless Chromium" says nothing about that. The hash is
still read and still unions with the baked view, so `map.html#fill` is both, and
`#fill` — a modifier rather than a choice — is the one worth typing. They read the same `state.js` and stay in step for free.

`#goals` differs from `#bottom` by the ticker alone, and that is why it exists:
the ticker is pinned to the **bottom of the browser source** and grows upward, so
on a source sized to the checklist a burst of toasts lands on the checklist. That
is fine on the full column, where they float over the foot of a page with slack
under it, and wrong on a source that *is* the list.

**IT STRETCHES.** The page fills whatever canvas the Browser Source gives it
rather than rendering a fixed column with dead space beside it — the covers,
the art and the type keep their own size and the TEXT COLUMNS take the slack,
which is what "wider" should mean for a page that is mostly sentences. (Wider is
not bigger: the type size does not change, so a viewer who finds the overlay small
wants `zoom`, not width.) Vertically it stays CONTENT-HEIGHT by default, which is
what makes the layout tables promises rather than samples; `overlay.html#fill`
takes the whole source instead and gives the slack to the checklist, the one part
of the page that can use it. `#fill` is a modifier and combines with the fragments
above, so the hash is parsed as a set of words rather than matched whole.

**THE CARDS ARE A TINT.** They sit at **0.30** alpha, so **70% of the capture
survives** — this page spends its life on top of somebody's gameplay, and a panel
is a hole punched in their capture. It has been four things: all but opaque
(0.95), "glass" (0.45 over a backdrop filter), a near-nothing 0.12 leaning on that
filter, and now an honest alpha.

**`backdrop-filter` IS NOT PART OF THIS PAGE, AND NEVER WORKED WHERE IT RUNS.**
An OBS browser source renders to a **transparent texture** and OBS composites the
scene behind it afterwards, so inside the page there is nothing behind a card to
filter. Measured: screenshot with `omitBackground` and the card pixels come back
at the card's own alpha to three decimals. The filter only ever darkened the white
page behind a **double-clicked** `overlay.html` — which is why every check of it,
by hand or by harness, was made in the one environment where it appears to work.

**EVERY CONTRAST FIGURE THIS PAGE HAS CARRIED WAS MEASURED THAT WRONG WAY.** The
**4.73** in three documents and the **4.96** that briefly replaced it both put the
capture *inside* the page. Composited the way OBS does it, the 4.96 page scored
**3.00** and the old 0.45 glass scored **3.90**. The design has been below AA on
every real stream it has ever run on, and looked correct on every desk it was
checked from.

So the filter is **gone** rather than kept as decoration: a declaration that does
nothing where the page runs and something where it is previewed is how this
survived two redesigns. Three things carry legibility now, all of which behave
identically in a preview and on a stream — an **alpha** (0.30, swept against the
sampler: 0.25 lands at 4.2, 0.20 at 3.9), a **halo** of hard dark shadows on every
glyph, and **one real scrim** on the cost line, the single element the sampler
said the halo could not carry.

**AND THE HARNESS COMPOSITES THE WAY OBS DOES.** `check_overlay.js` screenshots
with `omitBackground`, composites over a dark, a mid and a bright capture
*outside* the page, and splits each line of text into glyph and ground by
luminance. Worst text: **4.81:1** against an AA bar of 4.5. It also asserts
`backdrop-filter` stays `none`, so re-adding one fails there rather than looking
right on somebody's desk.

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

> **SUPERSEDED BY §19.1.** A shop stands at a **Shop node**, not at a hub. The
> degree measurements and the "second routing axis" argument below are kept
> because §19.2 is that argument carried through — the kinds are frozen at run
> start for exactly the reason given here, and the road ahead can now be routed
> on because of it. §14.3's shelf is unchanged.

A shop stands at each of the run's **ten best-connected games**
(`RunGraph.hub_ids`). On the full catalog those are the genre's landmarks — Slay
the Spire (147 connections), Vampire Survivors (91), The Binding of Isaac (71),
Balatro (53), Hades (49), FTL (38), Spelunky Classic (37), NetHack (31), Dead
Cells (28), Enter the Gungeon (27) — and the degree curve falls away steeply
across the top of that list, with a long flat tail behind it. The shoulder at the
tenth place is no longer clean, though: the eleventh game now ties the tenth at
27, so which game takes the last hub is decided by the tiebreak rather than by a
gap in the curve. Counts drift upward as the sheet grows; re-measure rather than
quoting these.

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

The shop appears **after a Shop node's game is beaten** (§19.1 — it was the ten
hubs, and that is §14.2's superseded half), queued behind the board's
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

**What a shelf row says, and what the header does not.** The panel led with the
hub game's name and a sentence explaining that what you don't buy stays here.
Neither earned its line: the panel is mounted on that game's page, under that
game's board, beside that game's card, so naming it again is the screen saying
where you are for the third time — and the rule about the shelf persisting is
something you learn once, not something worth re-reading at every hub. The header
is `🛒 Shop`, flat, and the rule is the panel's tooltip.

The row those two lines paid for carries **the art, the name, the price, and the
item's own description** across its full width. The description is the only one of
the four that answers *is this worth the gold*, and it used to be the one thing
you had to open a card to see. It wraps to `ShopPanel2.DESC_LINES` and ellipsizes
after them — the card behind a click still has the untrimmed text and the Buy
button, which is what the row is a summary of. **Rarity is the outline**: the row
is tinted toward `UITheme.item_color` and edged in it, the same two lines the pack
uses on its tokens (`PackStrip._item_token`), so a Legendary on a shelf and the
same Legendary in your bag are recognisably one thing. It used to be said in the
colour of the *name*, which is the one thing on a row allowed to trim away.

**Where the height for that came from**, because it is not where you would look.
The board is at its floor while it shares its column
(`BattlefieldView.FIELD_HEIGHT_BUDGET_SHARED` clamps a 4x4 to `CELL_MIN`), so it
had nothing to give. But a page's height is the taller of its two columns, and on
a hub's page that is the **left** one — the report checklist, whose goal text
wraps — by about sixty pixels. This panel is in the right column, so the room was
already sitting there unspent. The row went 58 → 98px and the page did not move.
`test_the_page_still_fits_the_window_with_a_shop_on_it` walks all ten hubs and is
what holds the arrangement honest.

### 14.5 What is still to come

**The shopkeepers.** `data/encounters/` already carries two combat-era ones (P
Mart's Tracy from Mewgenics, Trorc from Enter the Gungeon) with pools and
discounts. A `shopkeeper` field is read by `ShopPanel2` and is what a named
shop would put in the header in place of the flat `Shop`, so an authored roster
drops in without reshaping anything.

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

### 17.3 The five pieces of content that reach them

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
- **Gasoline** (Common, Risk of Rain 2) — `death_tile fire`. The twin of Hot
  Bombs, and the pair is only interesting because of what separates them: one
  reads the **blast**, this one reads the **defeat**. `death_tile` is its own
  field rather than a second use of `bomb_tile` precisely so the two can
  disagree — a bomb is an escape from a goal (§8.2) and never reaches
  `GameLoop2._defeat` at all, so Gasoline **cannot be farmed by spending
  charges**, and nothing in `_defeat` had to be written to say so. What it lays
  is laid through `apply_tile` like any other ground, so it bites a neighbour
  standing in the square it lit and annihilates with a mine already there for
  free. A body that fell **off** the board (§7.3) was never standing anywhere and
  leaves nothing. Read off the inventory by `GameState.death_tile`, first one
  owned winning, exactly as `bomb_tile` is.
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

**The board plays, then the haul, then the next table.** Nothing is dropped over
the resolve: it is the one moment the board gets — the front line striking, the
field closing a column — and a screen over it turns that into a thing that
happened behind a panel. The haul was opened on the press for one build, because
the page had been sitting on the overworld for the length of the playback with the
game already reported and nothing to do on it, and that read as a flash. **The
flash was the offering**, not the animation filling the window: see below.

**And the next offering waits for the haul.** The offering is *built* the instant
the game is reported — a Scramble or a Dash taken off the haul screen needs a table
to act on, and the cards are dealt off the run as it stands the moment it moved —
but it is not put on the page until the player has walked off the haul
(`Overworld2._refresh_stage` holds it while `_post_snapshot` or `_post_screen` is
set). It used to come back with the report, so a full table of games was dealt in
front of a player who had not yet been shown what the last game paid. The order is
now the order it happens in — the report, what it paid, then the next table — and
there is still no Continue step anywhere in the chain.

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

---

## 19. Node kinds, and where the enemies come from

Two changes that only work together. **A game on the map is now one of four
kinds**, and **enemies no longer arrive only because you chose to fight them**.
The first makes routing a decision about what kind of evening you want; the
second makes sure the second and third kinds are not simply a way of never
fighting at all.

This section supersedes **§7.5** (the escort) and **§14.2** (shops at the ten
hubs) outright, and amends **§2**, **§3.2**, **§7.1**, **§7.2** and **§7.4**.
Where it disagrees with them, this section is the build.

### 19.1 The four kinds

| Kind | What it does | When | Bodies | Also |
|---|---|---|---|---|
| **Enemies** | the ordinary game | on arrival | **2** | nothing extra — see below |
| **Event** | an event fires | **on arrival**, before you play | 0 | the game's own post-report event still rolls ([`event-sheet-authoring.md`](event-sheet-authoring.md)) |
| **Champion** | a boss of the run's current tier | on arrival | **1** | the boss's ordinary chest (§8.2), nothing extra |
| **Shop** | a shelf under the board | **after the game is beaten** | 0 | three items, persistent for the run (§14.3) |

**The Event and the Shop deliberately land at opposite ends of the game**, and the
reason is the purse. An event is a decision, and a decision is worth more before
you have committed an evening to the game it sits on. A shop is a *purchase*, and
the gold to make one is what the game you just played pays out (§14.1) — open the
shelf on arrival and the player shops broke, on a run that earns 8–15 gold in
total. So the shop keeps §14.4's timing exactly: queued behind the resolve on the
`Overworld2._pending_shop` path, mounted under the board, staying for the visit.

**All four are a real video game.** Every one of them grants the selection
shields (§3.2), ticks `GameState.games_played`, needs **✓ Completed Game** to
advance, and pays the game's own loot. The kind decides what stands on the board
and what you are handed — not whether you go and play. A run is still the thing
§1 says it is, and a shop is not a square you walk over.

**AN ENEMIES NODE PAYS NOTHING EXTRA, AND THAT IS THE POINT.** It carried a
bonus for a while — two gold and a piece of loot for taking the harder card —
and the bonus was redundant twice over. The bodies already pay: **+1 gold each**
on a cleared goal (§14.1) and **a piece of loot on the square they fell in**
(§8.2), plus their difficulty banked toward the report's chest. An Enemies node
is therefore *already* the node that pays most, in proportion to how much of it
you actually answered, which is a better shape than a flat fee for arriving.
The flat fee was also a real economy change nobody asked for: a run earns
**8–15 gold** in total (§14.1) and two gold across 60% of a 6–12 game run is
another 7–14, roughly doubling it and undoing the "two to four purchases in a
whole run" the whole price list is built around.

So the four kinds differ in **what happens**, not in what you are handed. An
Enemies node's reward is the two bodies standing on it.

**AN EVENT NODE ALWAYS FINDS AN EVENT, and the pool makes that nearly free.**
Measured against the shipping content: **all 16 events have a blank `where` and
empty `tiers`**, so nothing is placement-gated or tier-gated at all today —
`_where_allows` returns true for every one of them. The only live gate is the
stat `requirement`, and **7 of the 16 carry none whatsoever** (`abyssal_baths`,
`battleworn_dummy`, `golden_idol`, `golden_monkey`, `jungle_maze_adventure`,
`potion_lab`, `scrap_ooze`). "No eligible event" is therefore a content state
that does not currently exist. Re-measure rather than trusting this.

**If it ever does, the node re-shows an event the run has already had** rather
than relaxing anything. The two relaxations that suggest themselves are both
worse:

- **Relaxing the placement gate does nothing**, because no event is placed. An
  earlier draft of this section specified exactly that, which would have been a
  fallback that could never fire against a pool that could never empty — the two
  errors cancelling out and leaving the section saying nothing true.
- **Relaxing the stat requirements breaks the offer.** Those gates are what keep
  an event *affordable*: nine of the sixteen ask for gold, keys, potions or a
  Health band before they will stage. Firing "pay 5 gold" at a player holding
  none produces an event whose interesting choices are all greyed out, which is
  a worse answer than a repeat.

A repeat is affordable, playable, and does what the badge promised. And the
badge is the whole reason there is a rule here at all: a node whose kind said
*event* and then delivered silence is the badge telling a lie, which §19.2
exists to prevent.

**`games_played` keeps ticking on all four** even though the difficulty tier
stops reading it (§19.6). It is not vestigial: `RunOverScreen` and the OBS
overlay report it, `EventSystem` gates requirements on `"games"`, and
`SaveSystem` derives the autosave seed from it.

**The distribution is 60 / 20 / 10 / 10**, enemies / event / champion / shop,
with two overrides: **the run's opening game is always Enemies**, and **the
Amulet is always Champion**.

The Amulet's champion is **atmosphere and not a gate**. Reaching the Amulet game
and beating it wins the run whether or not the boss standing there ever went
down — that is the existing rule (`Overworld2.beat_game`'s `was_amulet` branch,
which records the win even when the goal went unmet) and it is deliberate: a
player who walked the whole road should not be held at the door by a goal they
cannot do. The boss is there because the last game of a run should not be its
emptiest board.

### 19.2 The kind belongs to the NODE, and it is frozen at run start

**Every game on the run's graph is assigned its kind when the run begins**, and
it never changes. This is the same rule, for the same reason, as the ten hubs
were frozen onto `GameState.hub_games` (§14.2): *a flag on an offered card that
could change under the player is a lie, and every badge in this build is
designed around not telling one.*

Three things fall out of it, and all three are the point:

- **Scramble is unaffected.** It supersedes the bodies that arrived with the
  game in play (`GameLoop2.choose_game` → `_clear_arrivals`), and the kind is a
  fact about the node rather than about what is standing on it. A Scramble
  re-rolls goals, exactly as it always did, and is not a way to buy your way out
  of a fight.
- **Bash and Transmute are unaffected.** Bash takes a game out of the
  **offering**, not out of the map, and Transmute "repaints which game sits on a
  node without touching a single edge" (`RunGraph.shortest_path_dag`'s note). The
  kind rides the **slot**, so a transmuted card plays a different game at the
  same kind.
- **The road ahead can be read.** The 🗺 map and the route ladder already draw
  real nodes, so they draw the kinds too. Routing stops being only "closer or
  further from the Amulet" and becomes "the long way takes in two shops and a
  champion" — which is the second routing axis §14.2 wanted and never quite got.

**Every node on the map gets a kind, not only the ones on a route.** A teleport,
Ride the Bus and a `play_game` detour (§10) can all land the run somewhere off
the optimal path, and those nodes have to answer the same question.

**THE GUARANTEE IS A RUN-START PROMISE, AND BASH CAN BREAK IT.** §19.3's budget
describes the map the run was *dealt*, not one the player has since edited. A
Bash takes a game off the board for the rest of the run (`GameLoop2.bashed`), and
nothing stops it taking the only Event on the road ahead. That is allowed: a
charge spent to delete a node is a choice, and its consequences are the player's.
The alternative — refusing the Bash the way the Amulet does — would be a verb
saying no for a reason the card cannot show, and re-laying the kinds to repair
the promise would make a badge change under the player, which this section exists
to prevent.

One wrinkle worth knowing before drawing any of this: **`shortest_path_dag` is
built from `neighbors()`, which does not filter bashed games** — only
`open_degree` and the offering do. So a bashed node still draws on the route
ladder while being unreachable. That is pre-existing, and §19 makes it visible
rather than causing it, since the node it strands may now be a guaranteed one.

### 19.3 What the road is guaranteed to hold

A start is only offered if **its whole shortest-path DAG to the Amulet** — every
node the route ladder draws on the start screen, not one route through it —
carries all of:

- at least **one Event** and **one Shop**, with at least one route through the
  DAG collecting both, so the variety is reachable without leaving the optimal
  path;
- at least **`hops − 1` Enemies**, the forced-Enemies start node counting as one
  of them;
- and **at least one split** — more than one route to the Amulet. No start may be
  offered whose DAG is a single linear chain.

**There is no Champion clause, and there was one.** An earlier draft required a
Champion *other than the Amulet* on every guaranteed route — the Amulet being a
Champion itself (§19.1) and always the DAG's terminal node, so a plain "one
Champion" would have been satisfied by the destination and guaranteed nothing
about the road. The requirement is dropped rather than fixed: the Amulet is the
Champion the road is *for*, a 10% roll puts more of them about anyway, and every
node the guarantee claims is a node the ordinary distribution does not get to
speak for. The terminal Champion is the only one promised.

**The budget, then, is `hops + 2` nodes**: `hops − 1` Enemies, one Event, one
Shop, and the Amulet. **The floor is `hops + 5`** — that budget plus **three**
spare nodes. It is a MINIMUM and not a target: most routes clear it comfortably,
and every count in this section is "Amulets with at least one route that clears
it".

`slack` here is `DAG nodes − hops`, and the offset is not arbitrary: a single-file
corridor already carries `hops + 1` nodes, one more than its own length, so
**slack 1 IS the corridor** and everything above it is games standing on
alternative routes at the same distance. On a 4-hop run — where only the three
middle layers can widen, the start and the Amulet being one node each — the floor
puts **seven games across those three layers**:

```
slack 1   5 nodes    S — a — b — c — A         one route, no choices
slack 4   8 nodes    S — a — b — c — A         ~2 ways on per step
                         a'  b'  c'
slack 5   9 nodes    S — a — b — c — A         the floor
                         a'  b'  c'
                         a"
```

Two spares rather than one, because one spare only buys the guarantee room to
*not repeat itself*; two buy the player somewhere to go.

**A FIXED OFFSET IS NOT A FIXED BRANCHINESS, and the long routes are the thin
ones.** The spares spread over however many middle layers the route has, so the
same floor reads very differently at each end of the band:

| Route | middle games / layers at `hops + 5` | ways on per step |
|---|---|---|
| 4 hops | 7 across 3 | **2.3** |
| 8 hops | 11 across 7 | **1.6** |

An earlier draft of this section claimed the offset "scales" so that a long route
is about as branchy as a short one. It is the reverse. The rule is kept as an
offset anyway — it is one number, it is what was measured, and a long run trading
density for length is defensible — but a floor that held branchiness constant
would have to scale with `hops`, and that is a different rule nobody has measured.

**The budget implies the split, and NOT the other way round.** This is worth
stating because the intuition runs backwards. A linear chain has `hops + 1`
nodes and cannot reach `hops + 5`, so any start that satisfies the budget
necessarily branches somewhere — the split comes free. But a start that merely
*has* a split is not thereby able to hold the kinds: one split is `hops + 2`
nodes, three short of the floor. **Measured: 15 of 240 options (6.2%) sat at
exactly one split and could not carry the required nodes even at the old
`hops + 4`.** So the split
is written down as its own guarantee — it is the thing that was actually wanted,
and a future loosening of the budget must not silently retire it — but it is the
budget that does the work.

> **STALE — re-measure before quoting.** The table below sampled 120 runs of
> `pick_amulet_and_starts` as it stood *before* this section: three random
> reference starts, and `MIN_START_CONNECTIONS = 3`. §19.9 retires the first and
> the rule below retires the second, so both columns describe a selection that no
> longer exists. It is kept because the shape of the trade is still the argument —
> and because the last column is the number to read, not the first.

| Floor | What it buys | Options rejected | Runs where **both** starts fail |
|---|---|---|---|
| `hops + 2` | one split, kinds not guaranteed | 15.0% | 1.7% |
| `hops + 3` | kinds fit, every node pinned | 21.2% | 3.3% |
| `hops + 4` | kinds fit, one node free | 27.1% | 5.0% |

**A rejected option costs almost nothing**, which is why the right-hand column is
the one that matters: it is re-drawn against the same Amulet, and only when
*both* of a run's starts fail does the Amulet itself change — against
`RunGraph.AMULET_ATTEMPTS`'s eight tries.

### 19.3.1 A START NEEDS TWO CONNECTIONS, AND BOTH MUST LEAD ON

`MIN_START_CONNECTIONS` drops from **3 to 2**, with one condition: a game with
exactly two connections may open a run **only if both of its neighbours are
themselves onward** (degree ≥ 2). So the opening offering may be two cards rather
than three, but neither of them is ever a dead end.

**The condition is free.** Measured across both catalogues and every slack floor,
the degree-2 games whose neighbour is a dead end contribute **no Amulet coverage
that the rest of the pool does not already provide** — the "onward" and "plain"
columns below are identical at every row. Excluding them costs starts and nothing
else.

| Start pool | Eligible starts (full / owned) |
|---|---|
| `degree ≥ 3` (the old rule) | 246 / 124 |
| `degree ≥ 2`, plain | 456 / 232 |
| **`degree ≥ 2`, both neighbours onward** | **419 / 207** |

**And the loosening is what makes a higher floor affordable.** The two rules look
opposed — one widens the pool, the other narrows what a route may be — and they
are not: more eligible starts means more chances that one of them has a genuinely
wide route, so the stricter floor stops biting. Measured at the **4–7** band, so
the trade is visible against the old numbers; Amulets able to field a full
three-genre panel:

| Floor | `degree ≥ 3` (full / owned) | `degree ≥ 2` onward (full / owned) |
|---|---|---|
| `hops + 4` | 786 / 454 | 786 / 455 |
| `hops + 5` | 784 / **430** | 784 / **452** |
| `hops + 6` | 782 / 423 | 782 / 445 |
| `hops + 7` | 781 / 355 | 782 / 375 |

Read the owned column: at `degree ≥ 3`, moving the floor from 4 to 5 costs **24**
Amulets. At `degree ≥ 2` onward it costs **3**. `hops + 7` is the cliff — 375 —
and `hops + 5` sits two rungs clear of it, which matters because the catalogue
grows and these numbers move under the rule.

**THE DEGREE-2 POOL FIXES DARKEST DUNGEON ON ITS OWN.** It is the section's own
worked example of the paragraph above, and it corrects an earlier finding. At
`degree ≥ 3` it was one of two owned games that could not field three genres — a
hub whose deckbuilder neighbours all sit *inside* the 4-hop floor, so no wider
band could ever reach them. With degree-2 starts admitted it reads **Action 11,
Traditional 7, Strategy 6, Deckbuilder 1**: three genres clear `hops + 5` outright.
The fix was never a wider band or a bought game; it was a bigger start pool.

**The two-card opening is accepted, not solved.** `BASE_OFFER_COUNT` is 3 and
`Overworld2._offered_ids` draws from the node's neighbours, so a degree-2 start
opens the run one card short of every later turn. The onward condition fixes the
*quality* of those two cards and not their number. Two real choices is still a
choice, and the alternative — topping the offering up from two hops out — would
put a card on the table that taking it cannot reach in one move.

### 19.3.2 THREE START CARDS, AND A BAND OF 4–8

`NUM_START_OPTIONS` goes from **2 to 3**, and `MAX_PATH_LENGTH` from **7 to 8**
with it. The two belong together: the panel wants its cards at **different
distances** as well as different genres (`_spread_across_band`), and three cards
drawn from a four-rung band leave that preference very little room. A fifth rung
is what makes three distinct distances an ordinary outcome rather than a lucky one.

Everything below is the agreed rule set — start pool `degree ≥ 2` onward, floor
`hops + 5`, three cards — measured at both bands:

| | Full 4–7 | **Full 4–8** | Owned 4–7 | **Owned 4–8** |
|---|---|---|---|---|
| Component | 790 | 790 | 458 | 458 |
| Start pool | 419 | 419 | 207 | 207 |
| Can fill 3 genres (hard) | 784 | **788** | 452 | **454** |
| …at 3 distinct lengths (soft) | 760 | **771** | 413 | **425** |

**The wider band earns its place on the soft column, not the hard one.** Three
genres was already all but universal; what 4–8 buys is **+11 full and +12 owned**
games whose panel can offer three genuinely different run lengths instead of
repeating a distance. That is exactly the preference the third card puts under
pressure, so the two changes pay for each other.

A repeated distance is still the documented fallback, not a failure: 33 owned
Amulets (458 − 425) field three genres at two distances. The panel keeps its
three cards.

**A longer ceiling is a longer evening.** A hop is a *game* — the route is
`hops + 1` nodes and the run plays one at each, so a 4-hop card is five games and
an 8-hop card is nine. 4–8 therefore raises the longest possible run from eight
games to nine, and §7.4's pressure ladder (5+ / 3–4 / 2–0 hops) opens one rung
further out. The band's position was always the run-length control; widening it
is a pacing change as much as a graph one.

**AND THE BAND IS ABSOLUTE.** Three cards, all inside 4–8, or the Amulet is not
used. There is no distance relaxation: `pick_amulet_and_starts` today fills a
genre-short panel with the best reachable start of that genre at *any* distance
(the `in_window: false` path), and that path is retired here — an Amulet that
would need it is dropped instead.

It is retired because it quietly undoes the paragraph above. The relaxation has
no reach limit, so the card it produces can sit anywhere: measured on the owned
catalogue, it would have offered Serpentcoil Island a start at **10 or 11 hops**
— a twelve-game evening, on a rule set whose stated ceiling is nine. A control
that stops applying exactly when it is doing the most work is not a control.

**So a short panel never happens**: any Amulet that reaches the panel already has
its three genres, and any that does not is not an Amulet. §19.9 counts the cost.

**A CUSTOM RUN IS HELD TO THE SAME RULE, AND MAY BE REFUSED.** `RunConfig` lets a
run name its Amulet outright, and `pick_amulet_and_starts` carries a carve-out for
exactly that — *"a named target that no reference can reach is still the run the
player asked for: take it directly and let the start search route to it."* That
carve-out goes. A named Amulet that cannot field three genres is **refused at the
setup screen, with the reason**, rather than silently handing over a run whose
road is worse than the rules promise. Telling someone their choice will not work
is better than giving them a quietly degraded version of it.

**Measured against the band the run will actually use** — `RunConfig.path_band()`
when a custom run has set one, the default 4–8 otherwise. Checking the guarantee
against a band the run is not going to run at would make it mean nothing, and a
custom run that widens its band should get the Amulets that band opens up. Note
the custom defaults are **5–8**, already not the standard pair.

**THE BUDGET COSTS NO GAME ITS PLACE ON THE MAP**, which is the question to ask
of any rule that narrows what the run generator may pick. Measured exhaustively
— every in-component game tested against every other as a (start, amulet) pair,
at both game filters:

| | Full catalogue | Owned |
|---|---|---|
| Games in the catalogue | 882 | 532 |
| In the main component | 790 | 458 |
| **Pruned off-map** (can never appear at all) | **92** | **74** |
| **Can be a start** (§19.3.1's pool) | **419** | **207** |
| …of those, with no Amulet clearing the floor | **0** | **0** |
| Cannot field 2 genres | **1** | **1** |
| Cannot field 3 genres (the panel) | **2** | **4** |

**Not one startable game is lost.** Every game in the start pool finds some
Amulet in the hop band whose DAG clears the floor — 419 and 207, the pool size
exactly. What limits the pool is the degree condition, not the budget.

Measured at the **agreed rules**: start pool `degree ≥ 2` onward, floor
`hops + 5`, band **4–8**. They supersede the `degree ≥ 3` / `hops + 4` / 4–7
figures this section carried before (246 / 124 startable, 3 / 2 unusable).

The **92 and 74 off-map games** are the real answer to "can any game never be
reached": they are pruned by `_prune_to_main_component` and have been all along.
Note the owned catalogue loses proportionally *more* of them (13.9% against
10.4%) — filtering the map removes edges as well as nodes, so a narrower
catalogue fragments rather than merely shrinking.

**A handful of Amulets have no route good enough** — 2 in the full catalogue and
4 in the owned one, against a component of 790 and 458. With no fallback (§19.9)
those are **not Amulets**; they stay ordinary nodes the run can route through and
fight at. §19.9 names them and explains why the two catalogues exclude for
opposite reasons — leaves in one, hub-adjacent games in the other.

**Serpentcoil Island is the one to know about**, and it is the rule set's hardest
case. At the agreed rules its best route anywhere is **slack 3** — two under the
floor — and that holds in the FULL catalogue as well as the owned one, so **no
amount of buying games fixes it**. It is also the only game that cannot field
even two genres. A ceiling of 9 clears it on the current library with no
purchases; the cheaper answer is an edge in the `connections` sheet out to the
wider mystery-dungeon cluster rather than only to its own sequels.

**The kinds are laid down AFTER the Amulet and the starts are picked.** The
budget is a filter on a start, never an input to choosing one — otherwise the
panel's cards would be picked for their node kinds rather than for genre and
distance, which is what `RunGraph.pick_amulet_and_starts` exists to balance.

The order is:

1. **Pick the Amulet and the start cards** exactly as today. Stamp the Amulet
   **Champion** and every start **Enemies**.
2. **For each offered start's DAG, place its required kinds on RANDOM nodes**,
   excluding the start and the Amulet — they already have kinds, and a guarantee
   that could land on the terminal node would guarantee nothing.
3. **Roll every remaining node** at 60/20/10/10.

**A shared node usually helps rather than conflicting.** Three cards mean three
DAGs over one Amulet, and they overlap heavily near it, because every route
converges there. When step 2 makes a shared node the Event for one route, the
other routes that contain it are *already satisfied* — so check before placing,
and only place what a route still lacks. The conflicting case — a route whose
last free node is already spoken for by another kind — is what the three spare
nodes are for; a route that genuinely cannot be satisfied sends its start back to
be re-picked, the same answer §19.3 gives any start that fails the budget.

**The guaranteed placements COUNT against the 60/20/10/10**, rather than sitting
on top of it: step 3 rolls the remainder to hit the target across the map as a
whole. So a guaranteed route reads slightly richer in Event and Shop than
average and the rest of the map slightly poorer, which is the honest way round —
the odds on the tin stay true of the map, and the guarantee is visibly paid for
somewhere.

### 19.4 The spawn model

**An Enemies node lands exactly two bodies, at every tier.** This is §7.5's
enemy-and-escort, kept as a number instead of as a rule — and the escort as a
*concept* is retired with it. There is no named enemy and no companion: two
bodies walk on at the back column (§7.2), both carry their own goal, both are
old goals from the moment they land, and beating the game answers for neither of
them on its own.

**A Champion node lands one body: the boss.** This reverses §7.5's boss-escort
decision, which was taken when every ordinary game put two bodies down and a solo
boss made the run's biggest round its emptiest board. That argument is noted and
overruled — a boss of the current tier is a heavy enough board on its own, and
the every-third-spawn capstone below already puts bosses onto boards that are
carrying other things.

**Event and Shop nodes land nothing.**

### 19.5 …and the enemies you get for not fighting

**Every run you finish without defeating anything spawns bodies.** This is the
other half, and without it the three non-Enemies kinds would simply be a way to
play the whole run on an empty board.

It fires on:

- **every lost run** at the game in play, where nothing has been defeated this
  game (`GameLoop2.log_attempt`);
- **every game handed in** with nothing defeated — whether the goal was met or
  missed.

It does **not** fire on an **escape** (the player walked away and already paid
the price §3.2 sets for it), on the **Amulet** (there is no next game for
anything to walk into), or on a **Shop or Event node** — nothing spawned there,
so nothing is owed, and those two kinds are genuine breathing room.

**How many, read off the same ladder §7.4 uses for extra turns:**

| Hops to the Amulet | Extra turns (§7.4) | Bodies per failure | Band |
|---|---|---|---|
| 5 or more | 0 | **1** | Distant |
| 3 – 4 | 1 | **2** | Closing |
| 2 – 0 | 2 | **3** | Doorstep |

One ladder with two columns, on the same bands, so the strip, the cards and the
resolver cannot disagree about either number.

**They roll from the game in play's type, at the run's current tier** — the same
`GameLoop2.roll_enemy(game_type_key(game), tier)` an Enemies node makes, with the
same widening. A body that turns up because you keep losing at a Deckbuilder is a
Deckbuilder body: the board goes on describing where you are standing, and the
failure changes how *many* walk on rather than what kind of place this is.

**`defeated_this_game` is the counter, and the distinction it draws is load-
bearing.** It is incremented in `GameLoop2._defeat` and nowhere else, which means
two things that look like progress are correctly *not* progress here:

- **Stepping a counted goal up by one is not a defeat** (§7.7). `advance_goal`
  moves a tally and never reaches `_defeat`; only the press that reaches the
  target resolves anything.
- **Finishing a counted goal is not always a defeat either.** A goal met deals
  **one** hit, and a body with more Health than that takes the hit, survives, and
  is **Staggered** (§7.2). It is answered but not down, so the tap stays open.

`goals_met_this_game` is the tempting field here and it is the wrong one: it ticks
for both of the above.

**The escape hatch is the only brake, and that is on purpose.** Five lost runs
opens the door (`Overworld2.ESCAPE_AFTER_LOSSES`), and three bodies down opens it
sooner (`ESCAPE_AFTER_DEFEATS`) — and defeating even one body shuts the spawn tap
for that game entirely. A player with no answer to the game in front of them has
two exits and a way to stop the bleeding; one who takes none of them is meant to
lose the run.

**What makes that survivable is that the rate is flat.** An earlier draft of this
scaled the failure spawn with the **tier**, and because failure spawns also raise
the tier, losing made the next loss bigger — five losses ran to thirteen bodies
and a boss. Reading the count off **hops to the Amulet** cuts that loop: losing
does not move you, so a player stuck at a game faces the same price every time
until they leave or win. The tier still climbs, but it no longer sizes anything
that spawns — it picks heavier bodies and **grows the board** (§7.3), which on the
crowding axis is help rather than harm.

It also gives the run a shape it did not have. Both pressures now converge on the
same place: at the doorstep a reported game hands the board two extra turns *and*
every failure lands three bodies. And **routing away from the Amulet lowers your
failure cost**, so "back off, clear the stack, come back" is a real plan rather
than a slower way to lose — which is the long way round finally paying for itself
the way §7.4 says it should.

**Failure-spawned bodies never join `arrivals`.** They did not come with the game,
so a Scramble cannot scrub them off the board. The undo needs nothing new: the
spawn happens after `log_attempt` has already taken its `_run_snapshot`, so
taking a turn back takes the body with it.

**A body spawned AT THE REPORT lands after the resolve**, so it does not take the
turns that report was paying for. It walked on as the game was handed in; it acts
from the next one, on §7.2's ordinary terms. The lost-run spawn is the same shape
one beat earlier — it lands with the tick, and the turn that tick buys is
resolved around it.

### 19.6 Difficulty is now a consequence

**`GameState.spawn_events` counts SPAWN EVENTS** — one per node arrival that
landed bodies, one per failure spawn, regardless of how many bodies each put down
— and the tier ladder reads that instead of `GameState.games_played`
(`RunDifficulty.tier_for`). Event and Shop nodes never tick it. The Amulet's own
Champion ticks it like any other arrival that lands a body; nothing reads the
result, because the run ends there.

**THE TIER CAN NOW STEP MID-GAME, AND THE BOARD GROWS WITH IT.** A failure spawn
is a spawn event, and a failure spawn happens on a *lost run* — so the counter
can cross a tier boundary with a game still in play, which `games_played` never
could. `GameLoop2.sync_grid_bounds` runs at the spawn rather than waiting for the
report: the extra column and row appear immediately, under the bodies that just
walked on.

Growing it late would be the worse of the two. The tier is what *sized* that
spawn's arrivals in the first place, and holding the board at its old size until
the report would crowd the new bodies onto a grid that the rule says has already
grown — which is the one state §7.3's off-grid queue exists to avoid rather than
to absorb. Board resizing has only ever happened between games
(`Overworld2._announce_difficulty_step`); this is the first thing that moves it
mid-game, and the announcement follows it there.

**Every third spawn event puts a boss on the board ON TOP of whatever else was
spawning**, replacing `RunDifficulty.is_boss_game`'s every-third-*game* capstone.
Champions are a second and independent source, so a fighting run meets bosses
more often than the old ladder allowed — that is the intent.

**A failure spawn can be the third one**, and then a boss walks on mid-game, off a
lost run. A boss takes no bomb damage and leaves only by its goal (§7.1), so this
is the sharpest thing in the section and it is aimed squarely at the player who
keeps losing without ever clearing a body.

**AND A CHAMPION NODE CAN BE THE THIRD ONE TOO, FOR TWO BOSSES.** The rules
compose rather than absorbing each other: the Champion node lands its boss, the
capstone lands another on top, and the run's hardest node occasionally doubles.
"On top of whatever else was spawning" is meant literally and the Champion is not
an exception to it — a rule that quietly cancelled itself on the one node where
it would hurt most would be the rule not meaning what it says.

The consequence worth stating plainly: a player who routes through events and
shops and clears goals promptly keeps a **small board and a low tier** for much
longer than the old clock allowed, and one who fights everything climbs faster
than it ever did. The ladder used to be a clock the player only rode. It is
something they steer now, in both directions.

### 19.7 What this retires

- **The escort (§7.5)** — absorbed into the Enemies node's count of two.
  `GameLoop2._spawn_escort`, `current_escort`, `escort_enemy` and
  `escort_instance` go with it, along with the card's *"One more enemy spawns with
  it"* line, which now says how many.
- **Shops at the ten hubs (§14.2)** — a shop is a Shop node. `ShopSystem.is_hub`,
  `GameState.hub_games` and `RunGraph.hub_ids` stop deciding where a shelf
  stands. §14.3's shelf itself is unchanged: three items, rolled once, persistent
  for the run, rerolled for a Scramble.
- **`RunDifficulty.is_boss_game`** and the `_boss_round` threading through
  `Overworld2._build_choices`, `arrive_at_game` and `_slot_enemy_key` — a boss is
  a Champion node or the third spawn event, and neither is a property of the
  game count.
- **The per-slot enemy cache** (`_slot_enemies` / `_slot_enemy_key`) keeps doing
  its job for enemies, but it no longer has to hold the kind: the node does.
- **`pick_amulet_and_starts`'s named-target carve-out** — see §19.3.2. A named
  Amulet is refused rather than routed to by a relaxed search.
- **Runs saved before this section.** `SAVE_VERSION` goes to **3** and a
  version-2 run cannot be continued, the way version 1 was retired at the 2.0
  cut. A run already under way has no node kinds and no `spawn_events`, and
  kinds cannot be derived after the fact: they are frozen at run start (§19.2),
  so any value invented at load is a badge appearing on a map the player was
  already walking. Retiring the run keeps "frozen at run start" literally true
  rather than true-except-once. The save FILE is not lost — only the in-flight
  run inside it.

### 19.8 Where the player sees it

- **On every offered card**: the kind, as a badge, beside the route badge and the
  pace note (§4.2). What a card does to the board is part of the same decision as
  what it does to the distance.
- **On the battlefield strip** (§7.4): beside `⏱ EXTRA TURNS N`, the failure
  price at this distance and the count to the next boss. The player cannot decide
  whether one more attempt is worth it without both.
- **On the 🗺 map and the route ladder**: the kind of every node drawn, so the
  road ahead can be routed on.
- **In the log and a notification** when a failure spawn lands, naming what walked
  on and why — the escort's old notice generalised. A body that appears because of
  something the player did needs saying out loud; it is the one arrival they did
  not choose.

### 19.9 Amulet selection — every start is a reference, and there is no fallback

§19.3's budget is a filter on the **route**, and it costs almost nothing (see the
table there). What *does* narrow the Amulet pool, and always has, is the two
steps before it. **Both go.**

**THE THREE REFERENCE STARTS GO.** `pick_amulet_and_starts` drew
`AMULET_REFERENCE_STARTS = 3` random eligible starts and kept every game sitting
4–7 hops from at least one of them. Three measuring sticks is a lottery, and the
problem is not the average but the **floor**:

| | Full catalogue | Owned |
|---|---|---|
| In the main component | 790 | 458 |
| Eligible starts | 246 | 124 |
| Candidates per run, 3 references (avg of 40) | 642 — 81% | 374 — 82% |
| **…worst run seen** | **407 — 52%** | **219 — 48%** |
| **Scoring against every eligible start** | **789 — 99.9%** | **458 — 100%** |

*(Measured before §19.3.1 lowered `MIN_START_CONNECTIONS` to 2, so the start pool
is the degree-3 one — 419 on the full catalogue now, not 246. That widening only
sharpens the argument: more sticks to draw three of, so a narrow draw is no rarer
and the map it sees is no wider. The shipped pool is 790 of 790.)*

One draw in forty left barely half the map eligible. And because *which* half
moves every run, a game is not reliably excluded so much as **unreliably
included** — the worst shape for a rule nobody can see. Scoring against all
eligible starts makes it deterministic: every in-component game is a candidate,
every run.

**AND `AMULET_SCORE_SLACK` GOES WITH IT**, having become nearly a no-op. It
exists to drop candidates more than 2 below the best early-branching score, which
bites hard when the best is drawn from three references. Measured against every
eligible start, every game finds a good reference and the cut takes **one game
out of 790**, and none at all in the owned catalogue. Dropping it recovers that one and removes
a constant that would otherwise look load-bearing and not be.

**MEASURED, AND IT IS FREE.** The worry was cost: a BFS plus a
`dag_branch_scores_from` sweep per eligible start per generation, in a file whose
own notes record a naive per-candidate BFS at **868 ms a roll**. Both halves of
the way out in the original draft turned out to be the right ones, and together
they leave the generation exactly where it was.

| | ms per generation |
|---|---|
| Three random reference starts (before) | **269** |
| Every eligible start, naively | 605 |
| Every eligible start, as shipped | **270** |

The first saving is the one the draft predicted: **dropping the slack removes the
only reason to compute branching scores at all**, so a reference now costs one
memoized BFS and a walk of its result rather than that plus a whole-catalogue
sweep. The second is an **early exit**, and it is worth being precise about why
it is not a sample. The loop stops when every game that *could* be a candidate is
one — past that point no remaining start can change the answer, so it is the same
set, not an approximation of it. On the shipping catalogue that arrives after
**27 of the 419** eligible starts, because a hub sees most of the map at 4–8 hops
by itself. If a future catalogue has a game no start can reach in band, the exit
never fires and the sweep simply runs to the end, still correct.

The pool this produces is **790 of 790** — the whole main component, every run,
rather than the 789 predicted at the old 4–7 band. `test_amulet_pool.gd` asserts
that against the live graph rather than sampling runs, which is the only way to
tell a stable pool from a lucky one. It also pins the trap this rewrite had to
step around: the old code excluded its three references from candidacy, which is
harmless at three sticks and, at all of them, would quietly take **the entire
start pool** out of the amulet draw.

**THERE IS NO FALLBACK, AND A FEW GAMES ARE THEREFORE NOT AMULETS.** An Amulet
that cannot supply the panel under §19.3's rules is simply not offered as one. It
stays an ordinary node — it can be routed through, fought at, bashed, transmuted
— it just is not a goal.

This is a reversal, recorded because it was argued the other way first. An
earlier draft of this section had such an Amulet fall back to the best route
available, on the grounds that the guarantee should degrade in the corner cases
rather than exclude them. The decision is to keep the guarantee absolute for now:
a rule with an escape hatch is a rule nobody can read off the screen, and four
games out of 458 is a cheaper price than a promise that quietly stops holding.
The fallback is the known answer if the exclusions ever start to matter.

**What it costs, at the agreed rules** (start pool `degree ≥ 2` onward, floor
`hops + 5`, band 4–8, three cards):

| Catalogue | Excluded | Which |
|---|---|---|
| Full (790) | **2** | Serpentcoil Island; Touhou Genso Wanderer: Lotus Labyrinth R |
| Owned (458) | **4** | Serpentcoil Island; Dice & Fold; Ember Knights; Everything is Crab |

**And the two catalogues exclude for entirely different reasons.** The full
catalogue's two are **leaves**: degree 1, every route funnelling through a single
neighbour, nothing to be done short of an edge or a wider ceiling.

**The owned catalogue's other three are one node short, on one genre.** Not
structurally broken at all — Dice & Fold, Ember Knights and Everything is Crab
each have eligible starts in **all four genres** inside the band, clear Action and
Traditional with slack to spare (9 to 28), and then come up **slack 4 against a
floor of 5 on Strategy**. All three:

| | Action | Strategy | Deckbuilder | Traditional |
|---|---|---|---|---|
| Dice & Fold | 9 | **4** | 1 | 28 |
| Ember Knights | 16 | **4** | 1 | 21 |
| Everything is Crab | 9 | **4** | 3 | 19 |
| *Darkest Dungeon (passes)* | *11* | ***6*** | *1* | *7* |

So **these three ARE the three Amulets the floor's last rung costs** — the
`455 → 452` in §19.3.1's table, named. At `hops + 4` all of them qualify. Darkest
Dungeon sits in the same neighbourhood with the same shape and passes on one
node's difference in one genre.

**The hub effect is real but it is the second constraint, not the first.** All
three neighbour **Slay the Spire** (degree 91), and each has exactly *one*
eligible Deckbuilder start in the entire band, at slack 1–3, because the
deckbuilders cluster within 1–2 hops of that hub — **inside** the 4-hop floor. A
mega-hub does pull its own genre out of reach. That is why there is no fourth
genre to fall back on when Strategy comes up short; it is not why Strategy comes
up short.

Only **Serpentcoil Island** cannot field even *two* genres, in either catalogue.

**ALL FOUR ARE THE BAND'S PRICE, NOT A MAP DEFECT**, and this is the thing to
know before anyone reintroduces a distance relaxation to "fix" them. Measured at
every distance rather than only inside the band, each of them has the genre it is
missing, clearing the floor comfortably — just outside 4–8:

| | Missing genre, inside 4–8 | …at its best distance anywhere |
|---|---|---|
| Dice & Fold | Strategy, slack 4 | **slack 10 at 3 hops** |
| Ember Knights | Strategy, slack 4 | **slack 9 at 3 hops** |
| Everything is Crab | Strategy, slack 4 | **slack 9 at 3 hops** |
| Serpentcoil Island | nothing clears | Action **21 at 11h**, Deckbuilder **17 at 10h**, Strategy **15 at 11h** |

Three of them are rescued by a single hop under the floor; Serpentcoil by going
two to three hops over the ceiling. §19.3.2 refuses both, and the refusal is the
point — a 3-hop card is a four-game run and an 11-hop card is a twelve-game one,
and the band exists to say what a run is.

The consequence for the sheet: a **leaf** needs an edge reaching *outward*. A
**one-node-short** game needs no edge at all — it needs the floor at 4, a wider
band, or one more Strategy game somewhere inside 4–8. Adding another
Slay-the-Spire-adjacent neighbour helps none of them.

`Settings.exclude_beaten_amulets` still narrows the pool on top of all this, and
still keeps its no-softlock fallback. That one is a player's preference rather
than a property of the map, which is exactly why it is the only narrowing left.
