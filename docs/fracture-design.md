# Fracture — design

**Status: steps 1–4 built; step 5 (how to play) was folded into step 3.** The
record, the nine changes of Fractures 1–9 (one table in
`scripts/runtime/Fracture.gd`), everything that shows a Fracture, and Fracture
10's Collapse (`GameLoop2.begin_collapse`, `scripts/redesign2/CollapseScreen.gd`,
`GameState.goal_game_id`). Tests: `test/test_fracture.gd`.
Agreed with the owner on 15
October 2026.
The build order is at the end. Section numbers (§7.4, §19.6, …) refer to
`docs/games-first-redesign.md`; rift sections refer to `docs/rifts-design.md`.

## 1. What a Fracture is

Fractures are the game's **Ascension**: ten extra difficulty levels on top of a
normal run, in the shape Slay the Spire gave the idea.

- **Fracture 0 is the game as it is today.** Fractures 1–10 each add one change,
  and **each level carries every level below it**: Fracture 6 is Fractures 1–6
  together.
- **Unlocked per character.** Fracture 1 opens with a character's **first win
  at Fracture 0**; after that, winning at their highest unlocked Fracture unlocks
  the next one, **for that character only**. Twelve
  characters with ten levels each makes 120 wins to finish the ladder, which is
  deliberate: it gives every character a long life of their own.
- **Chosen on the character select**, under the character (§4).
- **Fracture 10 changes the shape of the run**: carry the Amulet back to the
  start (§7). Every other level is a number turned up.

## 2. The ladder

| # | Change | What it touches |
|---|---|---|
| 1 | **Shield gain −1**: normal 3 → 2, Traditional 5 → 4 | `GameLoop2.shields_for_game` |
| 2 | **Shops are dearer: every price +1 gold**, items and loot alike | `ShopSystem.price_for` / `loot_price_for` |
| 3 | **Shield gain −1**: normal 2 → 1, Traditional 4 → 3 | as 1 |
| 4 | **One more body on every arrival**, the capstone boss's included (bosses too) | `GameLoop2.choose_game`, `_land_capstone_boss` |
| 5 | **Shield gain −1**: normal stays at 1 (the floor), Traditional 3 → 2 | as 1 |
| 6 | **Difficulty rises 1 spawn faster**: the tier steps, and a boss comes, every 3rd spawn event instead of every 4th | `RunDifficulty.GAMES_PER_TIER` |
| 7 | **+1 starting row**: the board starts one row taller, so more bodies can stand in the front column and hit at once. Columns are unchanged, so nothing spawns closer or farther | `GameLoop2.grid_growth` (rows only) |
| 8 | **Enemies take 1 extra turn after each game beaten or escaped** | `_resolve_enemy_turn`'s `extra` beat |
| 9 | **Enemies hit harder, ×2** | the swing, `GameLoop2.enemy_damage` |
| 10 | **The Collapse**: beat the Amulet, then carry it back to the start | §7 |

Where a game's shields land at each level:

| Fracture | Normal game | Traditional |
|---|---|---|
| 0 | 3 | 5 |
| 1–2 | 2 | 4 |
| 3–4 | 1 | 3 |
| 5–10 | 1 | 2 |

What a swing does at each level. Authored damage today is the enemy's tier
(Low 1 … Insane 4) and, for bosses, 3 / 5 / 7 / 9:

| | Fracture 0–8 | Fracture 9–10 |
|---|---|---|
| Low enemy | 1 | 2 |
| Medium enemy | 2 | 4 |
| High enemy | 3 | 6 |
| Insane enemy | 4 | 8 |
| Low boss | 3 | 6 |
| Medium boss | 5 | 10 |
| High boss | 7 | 14 |
| Insane boss | 9 | 18 |

What a shelf costs (`docs/games-first-redesign.md` §14):

| | Item | Loot | Item, Fracture 2+ | Loot, Fracture 2+ |
|---|---|---|---|---|
| Common | 3 | 1 | 4 | 2 |
| Uncommon | 5 | 3 | 6 | 4 |
| Rare | 7 | 5 | 8 | 6 |
| Legendary | 9 | 7 | 10 | 8 |

Reordered by the owner on 16 October 2026 (1↔4, 2↔3, 5↔7 of the first draft).
On 17 October 2026 the owner folded the two ×1.5 damage steps (2 and 9) into one
×2 at Fracture 9 and gave Fracture 2 to the shops.
The order is the owner's to move. It is written down here so a change to it is a
change to this table first.

## 3. Notes on each change

**Extra body (4).** Written as "escorts +1", but the escort had already been
retired by the time this was built: §19.4 replaced it with an Enemies node's
SECOND BODY, and a Champion node stands its boss alone. So it is built as **one
more body on every arrival**, rolled the way the second body is: an Enemies node
stands three, a Champion's boss gets one beside it, and the every-fourth-spawn
capstone boss (every third, from Fracture 6) brings one too. It does not touch
the end-of-game pressure count (§7.4).

**Shields (1, 3, 5).** A flat cut to the per-game grant, applied inside
`shields_for_game`, so the selection screen, the card and the grant cannot
disagree. Normal games floor at 1: a game that grants nothing would be a game
with no armour at all, and the third cut is the one that only reaches
Traditional. Items that add to the grant (Anchor's +1 Temporary Shield) add on
top as they do now.

**Dearer shops (2).** +1 gold on every price a shelf is rolled with, the items
row and the loot row alike, on top of whatever a shopkeeper's sale does. It is
added when the shelf is rolled (`Fracture.shop_surcharge`), and the level is fixed
for the run, so the price saved on a shelf is already the right one. It sits
early because it bites from the first shop: the 3-gold starting purse no longer
buys a Common item at the first shop on the road.

**Starting row (7).** Rows only. The owner's intent is "more enemies can hit you
at once", and a deeper board would have made them spawn farther away, which is
not wanted. The tier's own growth (`RunDifficulty.grid_growth_for`) still adds
on top.

**Faster difficulty (6).** `GAMES_PER_TIER` goes from 4 to 3 for the run. The
board grows with the tier (§7.3), so it grows sooner too, and the strip's
`boss in N spawns` reads it from the same place.

**The extra turn (8).** It follows a game that was **beaten or escaped**, not one
that was lost or abandoned. The game had a version of this once and removed it (§7.4,
*This replaced the extra turns*), because it punished the thing the player is
trying to do. On a difficulty level that punishment is the point. It goes
through the same `extra` beat of `_resolve_enemy_turn` that Predatory Scent
already uses, so:
- the Censer holds the two front columns out of it, as it does for any extra turn;
- each body's "N lost runs until it reaches you" is still right: it counts lost
  runs in THIS game, and the extra turn comes when the game is handed in. What
  the player needs told is the price of handing it in, so step 3 puts "+1 enemy
  turn" beside the strip's "+N when this game ends";
- a teleport out of a game skips it, the same way it skips the end-of-game
  spawn: it is not a game handed in.

**Damage (9).** The enemy's **authored** damage is doubled; statuses that add
damage (Strength and the rest) add on top of the result and **do not grow with
the level** (the owner's call), so the number on the body's card is the number
that lands. A shield stops one whole hit whatever its size (§3.2), so this level
only bites once the shields are gone. Bosses take it too. It was two steps of
×1.5, rounded up, at 2 and 9, until 17 October 2026; one ×2 is about what the
pair came to (9 → 21 against 9 → 18 on an Insane boss) without the rounding.

**DROPPED: +1 hop at the start.** This was Fracture 9 first: every start one game
farther from the Amulet (the path band 4–8 moved to 5–9). It did not break the
router, but it left Amulets out, and the owner scrapped it on 16 October 2026 in
favour of a second damage step (since folded into the single ×2). The measurements stay here so the idea is not
re-proposed without them.

**A flat 5–9 leaves Amulets out (measured 15 October 2026).** A game can be
the Amulet only if starts in three genres sit inside the band on a road that
clears the floor (`RunGraph.panel_genres`, §19.3.2). Counted for every game on
the map, rifts on:

| Catalogue | On the map | Amulets at 4–8 | Amulets at 5–9 | Lost |
|---|---|---|---|---|
| Full | 845 | 845 | 815 | 30 |
| Owned | 524 | 522 | 373 | **150** (1 gained) |

The owned losses cluster where the other genres' starts are all close:
Deckbuilder 62 of 96 (Balatro, Backpack Hero, Across the Obelisk, …), Action
60 of 241 (Brotato, Atomicrops, …), Strategy 26 of 82, Traditional 2 of 103.

**Rifts cannot rescue them.** The count above already includes the path-rift
rescue (the 4–8 column refuses exactly the two games rifts §5 refuses with rifts
on). Of the 150, **149 have no starts in three genres 5+ hops away at all**;
only one is short on route quality alone. A rift never lengthens a path, so
there is nothing for one to fix.

**Two genres instead of three, at Fracture 9 (asked by the owner, measured):**
same rift-aware rule, the panel allowed to show only two genres.

| Catalogue | Lost at 5–9 | Back with 2 genres | Still lost |
|---|---|---|---|
| Full | 30 | 24 | 6 (Chess Survivors, Cluckmech Oasis, Hades, Magicraft, Slay the Spire, The Binding of Isaac) |
| Owned | 150 | 120 | 30 (among them Hades, The Binding of Isaac, Dead Cells, Enter the Gungeon, Nuclear Throne, Darkest Dungeon, Cult of the Lamb, NetHack, Spelunky Classic, Diablo) |

The ones still lost are mostly the big hubs: everything that cites them sits
close, so few genres reach 5+ hops. Two genres alone therefore does not keep
every Amulet.

The only version that kept every Amulet was a fallback (5–9 with three genres,
else 5–9 with two, else 4–8), which makes the level do nothing at all for the
biggest hubs. That is what tipped it.

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

**"Skip won amulets"** (`Settings.exclude_beaten_amulets`) skips only games
already beaten as the Amulet **at the current Fracture or higher**, so a player
can go back for a higher number on a game they have won before.

**The unlock is shown on the winning screen**: "Fracture N unlocked for
<character>". Beating Fracture 10 gives the 🏆 with a 10 and nothing more, for
now.

**Custom runs** (filters, seed, a named target, a moved band): still give game
and character XP, as now. They **do not unlock Fractures and do not award
trophies**. This is a change from today, where an Amulet win is recorded
whatever the run was (`Overworld2.gd`, the two `record_amulet_win` calls).
Trophies already earned in custom runs cannot be told apart and stay.

**A custom run may be played at any Fracture that character has unlocked in
ordinary runs**, through the same picker row. It is practice: nothing it does
unlocks the next one.

## 6. Display

- **The header**: a **shard** glyph and the Fracture level, to the left of the
  player icon at the top of the screen. Nothing on Fracture 0. The shard is a new
  UI glyph, so `tools/build_glyph_font.py` is re-run for it, then
  `godot --headless --editor --quit` (CLAUDE.md, *A new UI glyph*).
- **Run history** shows the Fracture each past run was played at.
- **Character stats** split the character's wins by Fracture.
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
2. **Every game played this run fractures**: a rift-like fractal
   transformation, in the same visual language as rift cards (the domain-warped,
   drifting swirl of rifts §9, in the rift colour), washes over each played game
   in turn and leaves it **transmuted** into a game the player has not played.
   The start is the one game that is not.
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
- **Teleports measure from the start** on the way home: Scroll of Teleportation
  and the Telepills read "distance from the Amulet" today, and read distance
  from the start instead, so a Horse Telepill lands 1–3 games from home. It is
  an item the player found; that is what it is for.
- **Dying on the way home is an ordinary loss**: no trophy, no unlock.

### 7.5a As built (16 October 2026)

- **One goal, asked everywhere.** `GameState.goal_game_id()` is the Amulet, or the
  start while `carrying_amulet`. Every route, distance, pressure reading, goal
  card ("🏠 HOME" on the way back), teleport and map reads it; `amulet_game_id`
  is left meaning the game the run was a search for (its trophy, its name).
- **Arriving home wins, however you arrive**: a card, a Dash, a teleport, a
  travel or an event that sends you there all go through
  `Overworld2._arrive_home_if_due`.
- **The Amulet game charges the doorstep** in a Collapse. It owes nothing in an
  ordinary run because nothing follows it; here the walk home does.
- **When the off-map pool runs dry** the last resort is any unplayed game in the
  whole catalogue: off-map games are the only ones in the run's filter not
  already on the map, so there is nowhere else to look, and holding one game in
  two places would be worse than stepping outside the filter.
- **The route map shows what stands on a node now** (`GameLoop2.game_at`), for
  every transmute and not only the Collapse's — it used to show the game a
  transmute had replaced.
- **The screen** opens when the haul screen after the Amulet is left, before the
  event or shop behind it. The dev panel's "Collapse now" runs the same
  turnaround from wherever the run stands.

### 7.6 When the run is recorded

- Beating the Amulet game is a **win for that game** (its XP, its goals) at the
  moment it happens, like any game beaten.
- The **Amulet win** (the trophy, its number and the Amulet XP) and the
  character's win are recorded **when the player reaches the start**, because
  that is when the run is won.

## 8. Old saves

- Every character starts at Fracture 0. **A win already on record** from before
  Fractures existed counts as the Fracture-0 win, so a character who has won
  opens with Fracture 1 unlocked; one who never has, opens with nothing past 0.
- A run saved before this is built loads as Fracture 0.
- The run's Fracture is saved with the run, so a Continue resumes at the same
  level.

## 9. Dev tools

A Fracture setting in the dev panel (`DevTools.gd`), so any level, the Collapse
included, can be tested without climbing to it. The Collapse also wants a "beat
the Amulet now" button.

## 10. Still open

- **What a Fracture-0 player sees of the ladder** before their first win: the
  greyed row (§4), with every level locked, is the current answer.

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
   and its fractal transformation (reusing the rift swirl shader), and the
   end-of-run record at the start.
5. **How to play**: a Fractures page in `HowToPlayText.gd` listing every level
   and explaining the Collapse. The picker row's hover shows the same list.
