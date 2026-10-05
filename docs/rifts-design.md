# Rifts — design

**Status: designed, not built.** Agreed with the owner in October 2026. Nothing
here exists in code yet; the build order is at the end. Section numbers (§19.3,
§7.4, …) refer to `docs/games-first-redesign.md`.

## 1. What a rift is

The dungeon is a map of real influences: every line between two games is one game
naming another, with proof. **Rifts are where dimensions have merged.** Each run,
a handful of games that have *no* influence connections at all are pulled into
the map through rifts, which gives them a place to be played and gives the routes
the run offers more room to choose in.

Rifts are deliberately a **supporting** mechanic. The game is about influence
connections; rifts fill gaps and strengthen weak routes, and are never the main
thing a player chases.

A rift is a **rift game** (a game from the off-map pool) joined to **two games
already on the map**. It is per-run world state: rolled at run start, saved with
the run, and never written to the sheet or to `data/`. A rift line is not an
influence and is never presented as one.

## 2. The one rule: a rift never shortens anything

**A rift game may only join two games that are already exactly 2 hops apart.**

The path through a rift is always 2 hops (A → rift game → B), so a rift between
two games 2 apart offers a second road of the *same* length and can never be a
shortcut. That makes rifts invisible to every distance the run reads:

- the start band (4–8 hops, §19.3.2) is measured the same with or without rifts;
- Amulet pressure (§7.4) counts hops, so it is unchanged;
- Teleport destinations, which are chosen by distance from the Amulet, are unchanged.

What a rift *does* change is the **width** of a route. The route-quality floor
(§19.3, `ROUTE_SLACK_FLOOR`) counts the games on the shortest-path routes beyond a
single corridor. A rift placed on a start→Amulet route adds one such game, so
**each rift on a route raises its slack by exactly 1.**

Two games are 2 apart when they share a neighbour, so the most common rift is
between two dead ends hanging off the same hub.

## 3. Two kinds of rift per run

### 3.1 Path rifts — 1 to 2 per run

Placed on the **optimal paths of the three start cards**, at most **one rift per
start path**. The three paths all end at the Amulet and usually overlap near it,
so one rift often lies on two or three paths at once, which is why a run needs
only 1–2.

Placement, in order:

1. **Rescue.** If a genre's best start misses the route floor by one game, its
   rift goes on that path. This is what makes formerly refused Amulets usable (§5).
2. **Upgrade.** Otherwise place the rift where it lies on the most start paths at
   once, preferring the thinnest path.
3. Stop when every start path has its rift, or at 2 rifts.

### 3.2 World rifts — about 10 per run

Placed on **weak spots around the board, away from the start paths** (so "one per
start path" holds). Their job is to thin out dead ends and give detours more room.

- Prefer pairs of dead ends hanging off the same hub (each such rift removes two
  dead ends and adds none).
- **At most 2 world rifts per hub.** Unweighted, they would pile up around Slay
  the Spire (32 owned dead ends) and Vampire Survivors (29).
- The same never-shorter rule applies.

### 3.3 Which game goes in a rift

- **Any off-map game, regardless of genre.**
- **Unseen games first.** A rotation favours games that have not appeared in a
  rift before, recorded per game in the same stats that track Amulet wins
  (`GameStats`). Never last run's rift games.
- The game must pass the run's filter (owned / downloaded / custom run). Rift
  games may never be the Amulet or a start.

## 4. The quality floor: the split rule

With one rift per start path, a start qualifies when its route's slack is at
least *floor − 1*. The floor is set per Amulet:

- **Floor 6** for every Amulet that can field three genres at slack 6 with its
  path rifts in place. **This raises the route standard for most runs.**
- **Floor 5**, falling back only for Amulets that can't reach 6. These are the
  formerly refused ones that the rescue rift makes usable.

Either way, every offered path also carries its rift, so the road a player
actually walks is one game wider than its guarantee.

## 5. What this does to the Amulet pool (measured)

Measured October 2026 against the start rules (4–8 band, three genres, slack
floor), owned catalogue: 504 games on the map, 47 off it, 229 dead ends.

| | Refused as Amulet today | Usable with one rift per path |
|---|---|---|
| Owned | 14 | **12 rescued**, 2 still refused |
| Full catalogue | 1 (Slay the Spire) | **rescued** (1 rift) |

- **The 12 rescued (owned)** are the deckbuilder/tactics cluster around Slay the
  Spire: Roguebook, Slice & Dice, Pawnbarian, Fights in Tight Spaces, The Last
  Spell, Breachway, Star Renegades, For The Warp, Arcanium, Alina of the Arena,
  Tower Tactics and BroomSweeper. Each has in-band Strategy starts whose route was
  exactly one game short of the floor.
- **Still refused, by decision:**
  - **Slay the Spire (owned).** No Strategy or Deckbuilder start sits 4+ hops
    away; they are all too close. Adding links can never lengthen a path, so no
    rift can fix it.
  - **Shiren the Wanderer: The Mystery Dungeon of Serpentcoil Island.** It has a
    single connection, and two of its genres would need 2 rifts on the same path,
    which breaks the one-per-path rule. Left unusable for now.
- Today 54% of in-band start→Amulet routes (owned) are below the floor, so path
  rifts have plenty to improve.

These figures come from a Python replica of the start rules. The build re-measures
them with the game's own `RunGraph` before shipping (§10, step 1).

## 6. Rift games when you get there

- **Always an Enemies node.** In the node-kind budget (§19.3) a rift counts toward
  the Enemies share, so the Event and the Shop a route promises are never placed
  in a rift.
- **Rift enemies deal ×2 damage and drop ×2 loot**, including **×2 chest value**
  toward the report's chest (§8.2). A rift body that follows you off the rift
  keeps its double damage for as long as it stands. This is the risk and the payout.
- Not a Dash target, and Teleport never lands on one.

## 7. Verbs on a rift game

| Verb | On a rift game |
|---|---|
| **Bash** | The rift stays; the game inside it is replaced by another rift game from the pool. The route keeps the width its card promised. If the pool is empty, the rift closes like an ordinary bash. |
| **Transmute** | Same as Bash: another random rift game. |
| **Dash** | Rift games are not listed. |
| **Teleport** | Never lands on a rift game. |

## 8. Rift Keys

Keys already exist as a character stat, reserved by the spec for exactly this
("unlock a blocked edge / unconnected wild game", §4) and deferred until now.

- **Where keys come from:** items and loot. The owner places them in the reward system.
- **Where they show up: in the offering, not on a screen of their own.** The
  offering shows up to `offer_count()` cards (3 plus any `game_choice_bonus`),
  drawn from every connection of the current game, including the one you came
  from. A game with only one or two connections leaves slots empty. **While the
  player holds at least one key, each empty slot is filled with a rift card.**
  With no key, nothing changes.
- **A rift card is a specific rift game and where it leads:** a game exactly 2
  away on a neighbouring branch. That makes it obey §2 automatically: it never
  shortens anything. The card shows the destination and its distance to the Amulet,
  because the offering is a routing decision.
- **Picking a rift card spends one key.** Picking an ordinary card spends nothing.
  Each slot is a separate card, so holding fewer keys than empty slots still shows
  every slot; only one card is taken per step anyway.
- **Scramble rerolls rift cards completely: a new rift game AND a new
  destination.** Where the current game has only one game 2 away, the destination
  repeats and only the rift game changes. **Bash** on a rift card swaps the game
  inside it, as for any rift (§7).
- **The rift game is a rift game** (§6: Enemies, ×2 damage, ×2 loot), drawn from
  the same rotation (§3.3).
- **It closes once entered.** The link back to where you came from disappears, so
  the rift is a one-way passage into the new branch.

## 9. Presentation

- **Naming: deferred.** Rifts are just "rifts" for now. Themed names (a game's tag
  making a "Mecha Rift") are kept for later, when the owner adds more specific
  kinds of rift.
- **Rift cards in the offering** get a **fractal, swirly, distorted background**:
  a canvas shader on the card's backing panel (domain-warped noise in the rift
  colour, drifting slowly), with a dark band behind the card's text so the goal and
  the distance stay readable. Judge its colours by sampling the rendered pixel, not
  by eye (see `docs/layout-review-backlog.md`).
- **Map:** a distinct rift line style (shimmering or dashed, its own colour) on the
  run map and the route ladder. Rift games carry a rift badge.
- **Proof slot:** a rift game's card shows *"Rift: no known influence"* with
  merged-dimensions flavour text where the proof screenshot would be.
- **OBS overlay:** a rift flag, with a CSS version of the swirl, when the current
  game is a rift (`tools/check_overlay.js` re-run when the payload changes).
- **Atlas / Collection:** stays the real influence graph. Rifts are per-run state,
  shown at most as a faint overlay of the current run's rifts.

## 10. Rules of thumb for the build

- **Seeded and saved.** Rifts are rolled from the run's RNG before the Amulet and
  starts are picked, and written to the save. An older save loads with no rifts.
- **Settings toggle**, on by default, so a pure-influence run is still possible.
- **Running out of rift games.** Under a tight filter the off-map pool can be small.
  World rifts shrink first. If a rescued Amulet can't get its path rift, it is
  refused for that run, never offered under relaxed rules.
- **Transmute's pool.** Transmute already draws from the off-map pool. About 12
  rifts per run leaves 35 of 47 owned off-map games for it.
- **Tests.** Existing tests assume the map is exactly the influence graph
  (`test/test_amulet_pool.gd` asserts every map game can be the goal). Those need
  rifts off, or updated expectations. Rift tests must seed the RNG, not hope for
  the case (see CLAUDE.md on random-state flakes).

### Build order

1. **Generation:** path rifts, world rifts and the split floor in `RunGraph`,
   saved with the run. Verify §5 with the real Amulet measurement before going on.
2. **Visuals:** the swirl background on rift cards, map line, badge, proof slot,
   overlay flag.
3. **Rift enemies:** Enemies-only nodes, ×2 damage, ×2 loot and chest value; Bash
   and Transmute swap; excluded from Dash and Teleport.
4. **Rift Keys:** rift cards in empty offering slots; Scramble rerolls both the
   rift game and the destination.
5. **Later (owner):** key sources in items and loot; items and events that
   interact with rifts; themed rift names for specific kinds of rift.
