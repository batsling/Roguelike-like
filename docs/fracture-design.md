# Fracture — design

**Status: designed, nothing built.** Agreed with the owner on 15 October 2026.
The build order is at the end. Section numbers (§7.4, §19.6, …) refer to
`docs/games-first-redesign.md`; rift sections refer to `docs/rifts-design.md`.

## 1. What a Fracture is

Fractures are the game's **Ascension**: ten extra difficulty levels on top of a
normal run, in the shape Slay the Spire gave the idea.

- **Fracture 0 is the game as it is today.** Fractures 1–10 each add one change,
  and **each level carries every level below it**: Fracture 6 is Fractures 1–6
  together.
- **Unlocked per character.** Winning a run as a character at their highest
  unlocked Fracture unlocks the next one **for that character only**. Twelve
  characters with ten levels each makes 120 wins to finish the ladder, which is
  deliberate: it gives every character a long life of their own.
- **Chosen on the character select**, under the character (§4).
- **Fracture 10 changes the shape of the run**: carry the Amulet back to the
  start (§7). Every other level is a number turned up.

## 2. The ladder

| # | Change | What it touches |
|---|---|---|
| 1 | **Escorts +1**: everything that spawns brings one more companion | §7.5 |
| 2 | **Shield gain −1**: normal 3 → 2, Traditional 5 → 4 | `GameLoop2.shields_for_game` |
| 3 | **Enemies hit harder, +1 per tier**: Low +1, Medium +2, High +3, Insane +4 | the swing, `GameLoop2._take_hit` |
| 4 | **Shield gain −1**: normal 2 → 1, Traditional 4 → 3 | as 2 |
| 5 | **+1 starting row**: the board starts one row taller, so more bodies can stand in the front column and hit at once. Columns are unchanged, so nothing spawns closer or farther | `GameLoop2.grid_growth` (rows only) |
| 6 | **Difficulty rises 1 spawn faster**: the tier steps, and a boss comes, every 3rd spawn event instead of every 4th | `RunDifficulty.GAMES_PER_TIER` |
| 7 | **Shield gain −1**: normal stays at 1 (the floor), Traditional 3 → 2 | as 2 |
| 8 | **Enemies take 1 extra turn after each completed game** | `_resolve_enemy_turn`'s `extra` beat |
| 9 | **+1 hop at the start**: every start is one game farther from the Amulet | `RunGraph` path band |
| 10 | **The Collapse**: beat the Amulet, then carry it back to the start | §7 |

Where a game's shields land at each level:

| Fracture | Normal game | Traditional |
|---|---|---|
| 0–1 | 3 | 5 |
| 2–3 | 2 | 4 |
| 4–6 | 1 | 3 |
| 7–10 | 1 | 2 |

The order is the owner's to move. It is written down here so a change to it is a
change to this table first.

## 3. Notes on each change

**Escorts (1).** One more body in every escort the board already rolls (§7.5),
so it rides the escort's own rules (type, tier, footprint, "a body with no room
does not spawn"). It does not touch the end-of-game pressure count (§7.4).

**Shields (2, 4, 7).** A flat cut to the per-game grant, applied inside
`shields_for_game`, so the selection screen, the card and the grant cannot
disagree. Normal games floor at 1: a game that grants nothing would be a game
with no armour at all, and the third cut is the one that only reaches
Traditional. Items that add to the grant (Anchor's +1 Temporary Shield) add on
top as they do now.

**Damage (3).** A shield stops one whole hit whatever its size (§3.2), so this
level only bites once the shields are gone. That is why it sits right after the
first shield cut. Bosses take it too: the tier is the enemy's own.

**Starting row (5).** Rows only. The owner's intent is "more enemies can hit you
at once", and a deeper board would have made them spawn farther away, which is
not wanted. The tier's own growth (`RunDifficulty.grid_growth_for`) still adds
on top.

**Faster difficulty (6).** `GAMES_PER_TIER` goes from 4 to 3 for the run. The
board grows with the tier (§7.3), so it grows sooner too, and the strip's
`boss in N spawns` reads it from the same place.

**The extra turn (8).** The game had a version of this once and removed it (§7.4,
*This replaced the extra turns*), because it punished the thing the player is
trying to do. On a difficulty level that punishment is the point. It goes
through the same `extra` beat of `_resolve_enemy_turn` that Predatory Scent
already uses, so:
- the Censer holds the two front columns out of it, as it does for any extra turn;
- `GameLoop2.strike_countdown_text` and `attacks_in_turns` have to count it, or
  each body's "N lost runs until it reaches you" lies. That is the one place this
  level needs care.

**+1 hop (9).** The run's path band moves up one: 4–8 hops becomes 5–9 (runs of
six to ten games instead of five to nine). **This does not break the router.**
Custom runs already route bands up to 20 (`RunConfig.PATH_CEILING`). Two things
to measure when it is built, the same way the rifts doc measured its effect
(rifts §5):
- the three start cards want three different distances (`_random_spread`), and
  the ceiling of 8 was chosen to give them room; a band of 5–9 has the same five
  rungs, so this should hold, but check it;
- how much of the Amulet pool stays reachable at the longer distances, on the
  full catalogue and on the owned one.

A custom run's band is the player's own and is not shifted (custom runs earn
nothing from Fractures anyway, §5).

## 4. Choosing a Fracture

- On the **character select** (`scripts/menu/CharacterPicker.gd`), under the
  character: a row 0–10, the unlocked ones clickable and the rest greyed out.
- It **stays on whatever the player last picked for that character** until they
  change it. Per character, since the unlocks are per character.
- A character with nothing unlocked past 0 still shows the row, so the ladder is
  visible from the first run.

## 5. Rewards

**XP.** Only the base repeat-win XP moves: `GameRanks.XP_REPEAT_WIN` (50) gets
**+10% per Fracture level**, so +5 per level and 100 at Fracture 10. The first-
win 100, the Amulet 200 and the perfect 100 do not change, "for now" in the
owner's words.

Game XP is derived, never stored (§20.3), so **each recorded win has to carry the
Fracture it was won at**. That one record also feeds the trophies and the unlocks,
so it is the first thing to build.

**Trophies.**
- A **game's 🏆** (beaten as the Amulet) shows the **highest Fracture** it has
  been beaten at.
- A **character's 🏆** in the Collection shows the highest Fracture they have
  won at.
- No number means Fracture 0. Every trophy earned before this is built reads
  that way, which is correct: those runs were at Fracture 0.

**Custom runs** (filters, seed, a named target, a moved band): still give game
and character XP, as now. They **do not unlock Fractures and do not award
trophies**. This is a change from today, where an Amulet win is recorded
whatever the run was (`Overworld2.gd`, the two `record_amulet_win` calls).
Trophies already earned in custom runs cannot be told apart and stay.

## 6. Display

- **The header**: the Fracture level to the left of the player icon at the top of
  the screen. Nothing on Fracture 0.
- **The OBS overlay** does not show it.
- **The Continue list** shows it on each save's row.
- **The Collection**: the character's 🏆 with its number (§5).

## 7. Fracture 10 — the Collapse

### 7.1 The rule

Beating the Amulet game no longer wins the run. The player picks the Amulet up,
the run turns around, and **the run is won by arriving back at the starting
game**. Arriving is enough; the start is not played again.

### 7.2 What happens when the Amulet is beaten

One sequence, shown in full, because it is the most stream-worthy moment in the
game:

1. **The map turns round.** The optimal-path screen redraws running from the
   Amulet on the right to the start on the left.
2. **Every game played this run crumbles**, with a crumble animation, and is
   **transmuted** into a game the player has not played. The start is the one
   game that is not.
3. **The new road forms**: the optimal path from the Amulet back to the start,
   drawn over the transmuted games.

### 7.3 Why transmuting rather than bashing (the owner's call)

The first design bashed every played game and patched the holes with rifts.
Transmuting is simpler, because **it keeps the map's shape**:

- A transmuted node keeps its connections; only the game in it changes
  (`GameLoop2.transmuted`, `game_at`). So the graph is exactly what it was, and
  the optimal path back has **the same length as the original optimal path
  out**: a full mirror for free, with no rifts needed and no way to shortcut.
- "Don't go back through games you played" holds automatically: every node you
  played now holds a game you haven't.
- Rift slots stay rift slots. A transmuted rift game draws from the rift pool, as
  Transmute already does (rifts §7).
- A node's kind (shop, hub, …) belongs to the node, so shops stay where they
  spawned, the owner's rule.

### 7.4 The one real problem: running out of games to transmute into

Transmute draws from the **off-map pool**. That pool used to be split by type,
and by type it was tiny (owned: Deckbuilder 5, Traditional 7), so a Collapse
that transmutes ten or more games at once, after the run's world rifts have
taken their share, could have emptied it. Two decisions answer that:

- **Transmute no longer keeps the type, everywhere** (owner, October 2026): the
  verb rolls flat across every off-map game. That is built, and the Traditional
  transmute setting went with it.
- **The owner is adding more unconnected games** to the catalogue.

The Collapse's transmute still must not refuse the way the verb does when the
pool is dry, so for each game it takes the first of these that has anything left:

1. an **off-map** game (the verb's own pool);
2. a game inside the run's filter that is **not on the map and not played**.

Both exclude games played this run and games already handed out by this
Collapse, so no two nodes end up holding the same game.

It is **free**: it spends no Transmute charges and is not the verb. It needs its
own entry point beside `transmute_game` rather than a charge handed in and taken
back.

### 7.5 On the way home

- **The board carries over** through the turnaround: whatever is standing when
  the Amulet falls is standing on the first game home.
- **Amulet pressure (§7.4) counts hops to the start** instead of hops to the
  Amulet. Same ladder, new destination.
- **On the map**, the player icon sits on the game the player is on, with the
  **Amulet beside it** while it is carried. The optimal-path screen gets the
  same icon on the current game. That icon is worth having at Fracture 0 too.
- Every "N games from the Amulet" line in the UI (the offered cards, the start
  picker's wording) reads "N games from the start" on the way home.
- **Dying on the way home is an ordinary loss**: no trophy, no unlock.

### 7.6 When the run is recorded

- Beating the Amulet game is a **win for that game** (its XP, its goals) at the
  moment it happens, like any game beaten.
- The **Amulet win** (the trophy, its number and the Amulet XP) and the
  character's win are recorded **when the player reaches the start**, because
  that is when the run is won.

## 8. Old saves

- Every character starts at Fracture 0 with Fracture 1 unlocked.
- A run saved before this is built loads as Fracture 0.
- The run's Fracture is saved with the run, so a Continue resumes at the same
  level.

## 9. Dev tools

A Fracture setting in the dev panel (`DevTools.gd`), so any level, the Collapse
included, can be tested without climbing to it. The Collapse also wants a "beat
the Amulet now" button.

## 10. Still open

- **Fracture 3's numbers**: +1 per tier, starting at +1 for Low. If Low should
  start at +0, it is one constant.
- **What a Fracture-0 player sees of the ladder** before their first win: the
  greyed row (§4) is the current answer.

## 11. Build order

1. **The record**: the run's Fracture level, saved with it; each win and Amulet
   win stores its level; per-character unlocks and last pick in the profile. The
   XP bonus and the custom-run rule (§5).
2. **The simple modifiers**, Fractures 1–9, each behind a single
   `Fracture.at_least(n)` check so the tests can stand a run at any level.
3. **The UI**: the picker row, the header, the trophy numbers, the Continue row,
   the dev setting.
4. **The Collapse** (§7): the free transmute with its fallbacks, the turnaround,
   pressure toward the start, the map's player icon with the Amulet, the sequence
   and its crumble animation, and the end-of-run record at the start.
