# The systems graph — design notes

**Status: design in progress. Nothing is built yet.** There is no generator, no
renderer, and no output. This document is the accumulated design thinking for a
signed graph of how the game's mechanics feed each other, so a session picking
this up doesn't re-derive it or re-litigate decisions already made.

---

## 1. What it is, and where the idea came from

The inspiration is a genre of YouTube explainer diagram — the Project Zomboid
one specifically — where a game's systems are nodes and the arrows between them
are coloured by sign: green when the source pushes the target in a good
direction, red when it pushes against. Happiness feeds into boredom feeds into
panic; inventory weight feeds into health, negatively.

The goal here is the same picture, **but derived rather than asserted.** The
Zomboid chart is hand-drawn opinion. Ours is generated from a table where every
piece of content in the game declares the arrows it creates, so each arrow is
backed by the specific items, events and rules that make it true, and its
thickness says how many.

The target audience is twofold: it is a **design instrument** (which systems are
starved, which are saturated, where the feedback loops are) and eventually a
**presentation artifact**.

### The one thing that makes it worth building

A fan diagram is not interesting. If the graph only ever runs
`content → system`, you get 200 items on the left, 20 systems on the right,
everything flowing one way, and it tells you nothing a sorted column wouldn't.

**The Zomboid chart is interesting because it has cycles.** Panic hurts
accuracy → worse accuracy leaves more zombies alive → more zombies means more
panic. Every design decision below exists to make cycles appear in our graph.
If a change to the schema would flatten the graph back into a fan, it is the
wrong change.

---

## 2. Where the data lives, and a warning

The table is the **`chart` sheet** of `tools/Roguelikes.xlsx` (sheet 49,
`xl/worksheets/sheet20.xml`).

> **⚠️ The committed workbook is behind the working copy.** As of this writing
> the `chart` sheet on `main` still has the *original* header — `Name, Type,
> Subtype, System 1, Subsystem 1, Preference 1, …` — with only rows 2–4 filled
> in and 55 bare item names below. Every schema decision in this document
> post-dates that. The current shape has been seen only in screenshots the user
> shared in conversation; **the edits were never pushed.**
>
> **Before doing any work here, check whether the workbook now carries the
> schema described in §3, and if it doesn't, ask the user to push it.** Do not
> build a generator against the committed sheet — you would be targeting a
> schema that has been superseded three times.

Everything in §3–§6 is transcribed from those screenshots. Treat it as an
accurate record of the *design*, and the workbook as the authority on the
*data*.

---

## 3. The schema as it currently stands

One row per node. Columns A–C identify it, then a repeating four-column block
declares its outgoing arrows, up to three so far (the block is designed to
extend).

| Col | Header | Meaning |
|---|---|---|
| A | `Node` | The thing. `Alien Baby`, `Blood Donation Machine`, `Bombs`. |
| B | `Otainable` *(sic)* | Where it enters the run — see §4.5, this column is overloaded. |
| C | `Node Type` | `Item`, `Object`, `Event`, `Unit`, `Loot`, `Stat`. See §4.4. |
| D/H/L | `System n` | Target system — the coarse node. |
| E/I/M | `Subsystem n` | Target subsystem — the fine node, what actually moves. |
| F/J/N | `Trigger n` | *When* the arrow fires. See §4.2 — this is the important one. |
| G/K/O | `Dir n` | `Up` or `Down`. **Magnitude only, never valence.** See §4.1. |

Two lookup blocks sit to the right of the main table:

| Cols | Contents |
|---|---|
| Q–R | `Subsystem` → `Good Direction` (`Up`/`Down`). The colour table. See §4.1. |
| T | `Groups` — a nested containment tree over the System vocabulary. See §4.3. |

### Vocabulary observed so far

**Systems:** Health, Shield, Stats, Bomb, Item, Goal, Potion, Enemy, Loot,
Pill, Grid, Tile, Object

**Subsystems** (those with a Good Direction declared): Bash, Bomb Amount, Bomb
Size, Curse ↓, Enemy Max Health ↓, Health Amount, Item Amount, Level Up, Luck,
Max Health, Pill Amount, Potion Amount, Speed, Temporary Shield, Enemy Variety,
Fire Tile, Gold, Friendly Unit Spawn, Enemy Damage Taken, Loot Copy, Loot
Amount, Object Spawn

**Triggers:** Pickup, Passive, Combat Start, Combat End, Damage Taken, Enemy
Defeat, Enemy Spawn, Enemy Movement, Bomb Use, Item Use, Loot Use, Object Use,
Gold Use, On Level Up

---

## 4. Decisions already made, and why

These were worked out in conversation and are settled. Each one exists for a
reason that is not obvious from the column headers alone — please read the
rationale before changing any of them.

### 4.1 Colour is computed, never hand-entered

**The rule:** `Dir` records only which way the number moves. Colour comes from
`Dir × Good Direction`, looked up per subsystem in Q–R.

**Why it matters.** The sheet's first version had a single `Preference` column
holding `Positive`/`Negative`, and within three rows it already meant two
incompatible things:

- **Alien Baby** → `Enemy.EnemyHealth : Negative` — read as *decreases enemy
  health*, a direction of magnitude, and good for the player.
- **Calling Bell** → `Goal.Curse : Negative` — read as *bad for the player*,
  while the curse it gives you is a magnitude that goes **up**.

Green into Enemy Health and green into Health would have meant opposite things.
A reader — including the author in six months — could not have told which. The
split fixes it structurally: valence is declared once per subsystem instead of
being re-judged on every one of several hundred rows, so it cannot contradict
itself.

**Free bonus:** flipping the renderer to plain Up/Down gives you the *mechanical*
graph, while the computed colour gives you the *player-experience* graph. Two
readings, one table.

**Consequence for the generator:** a subsystem with no Good Direction is a hard
error. Do not default it to grey — a missing entry is exactly how a wrong colour
gets in.

### 4.2 `Trigger` is the return leg — it is what creates the cycles

This is the single most important structural idea in the schema.

A trigger is not a property of the content. It is *the world reaching back and
firing it*. So every row is a two-hop path, not a one-hop arrow:

```
Enemy Defeat ──gates──▸ [Charm of the Vampire] ──+──▸ Health.HealthAmount
Damage Taken ──gates──▸ [Bionic Face Plating]  ──−──▸ Item.ItemAmount
Bomb Use     ──gates──▸ [Blood Bombs]          ──+──▸ Health.HealthAmount
```

Collapse the content out of the middle and you have `Trigger → Subsystem`,
signed. Add a small lookup mapping each trigger to the system that *emits* it —

| Trigger | Emitted by |
|---|---|
| Pickup | Loot |
| Combat Start / Combat End / Enemy Defeat | Combat |
| Damage Taken / Enemy Spawn / Enemy Movement | Enemy |
| Bomb Use | Bomb |
| Item Use / Loot Use / Object Use / Gold Use | *(player action — see below)* |

— and you have a pure signed **system → system** graph *with cycles*, derived
entirely from rows already typed. Health keeps you alive → you defeat more
enemies → Enemy Defeat fires Charm of the Vampire → Health. That is a Zomboid
loop, and it fell out of the data rather than out of anyone's head.

**This lookup does not exist yet.** It is small (~14 rows) and it is the highest-
value missing piece.

**`Passive` is the exception, and a useful one.** No gate means the arrow's
source is wherever the content *entered the run* — which is what `Otainable`
already says. So `Chest → Clover → +Stats.Luck`, and Luck feeds loot quality,
which feeds what Chests contain. Another loop, and the reason `Otainable` earns
its column.

**Proposed, not yet decided:** distinguish player-fired triggers (`Item Use`,
`Bomb Use`, `Loot Use`, `Gold Use`, `Pickup`) from world-fired ones (`Damage
Taken`, `Enemy Spawn`, `Enemy Movement`) by node shape or outline. The finished
chart would then split visually into agency and pressure.

### 4.3 One graph, three rendered views

The instinct to put "bigger systems" — goals vs enemies, gold vs shops — on a
separate chart is **right about the output and wrong about the storage.**

Split the picture, never the table. The structural edges are precisely the
return legs that close the content loops, and separating them breaks the graph's
ability to tell the truth. The worked example is in §5.1.

Render three zoom levels off the one graph:

| View | Nodes | For |
|---|---|---|
| Supersystem | ~10 | The presentation picture. Where red is legible. |
| System | ~20 | The working map. |
| Subsystem + content | all | The balance audit. Ugly, useful. |

The supersystem view matters more than it looks: at subsystem granularity red
arrows are scattered noise, but at `Opposition → Resource` versus
`Resource → Opposition` the whole story is two arrows.

### 4.4 `Node Type = Stat` marks a rule, not a thing

Row 29 is `Bombs` — Node Type `Stat`, arrow `Enemy · Enemy Damage Taken /
Bomb Use / Up`.

Bombs are not content. You cannot pick up a "Bombs". That row states a **rule**:
spending a bomb damages an enemy.

An earlier proposal in this design was a second worksheet for hand-authored
structural edges. **That proposal is superseded.** `Node Type = Stat` is
cleaner: same grammar, same columns, one table, one vocabulary that cannot
drift, and the renderer can still style rule-edges differently. Every structural
edge belongs here as a `Stat`-typed row.

### 4.5 `Otainable` is a foreign key, and it is what makes this a graph

It holds `Type: Name` references to other rows — `Object: Blood Donation
Machine`, `Event: Golden Idol`, `Item: Landmines` — with commas for multiples
(`Starter, Chest`). That means **content chains to content**, and the graph can
be walked across node types. See §5.2.

Commas now appear in `Trigger` cells too (`Object Use, Bomb Use` on Blood
Donation Machine), fanning one row into two edges. **Make comma-splitting
universal across columns rather than per-column.**

---

## 5. Worked examples — why the design is the way it is

### 5.1 Bombs: why the structural edges cannot live on a separate chart

Three bomb items are in the sheet — Blood Bombs, Brimstone Bombs, Hot Bombs —
and in the content rows *every single arrow is green*. Bomb Amount up, Bomb Size
up, Health Amount up. Bombs read as a pure buff.

They are not. From the spec, §14.1:

> a **bombed** enemy **pays nothing** … it is an escape from a goal you couldn't
> or wouldn't do, and letting it mint currency would make bombing the cheapest
> way to farm the shops.

A bomb drops no item and mints no gold, so bombing **severs** `Enemy Defeat →
Gold` and `Enemy Defeat → Loot` — the run's main economic artery.

That red arrow can never appear in the content rows, because it is not a
property of any item. It is a rule. Put gold-and-shops on a different chart and
the bomb cluster renders as four green arrows and a lie. Keep one graph and
`Bomb Use ──▸ Gold (Down)` sits right there, and the bomb items read correctly
as *escape hatches with a price*.

### 5.2 A chain across four node types

```
Game Completion ──▸ Arcade (Event)
                └─ Object Spawn / Gold Use ──▸ Blood Donation Machine (Object)
                     ├── + Stats · Gold          (Object Use, Bomb Use)
                     ├── − Health · Health Amount (Object Use)
                     └── + Health · Health Amount (Bomb Use)
```

Four node types, three hops, a cost and a payout. **This path does not exist in
any single sheet of the game's data** — it only exists in this graph. That is
the proof the whole exercise is worth doing.

### 5.3 Golden Idol: modifiers vs. creators

Golden Idol's row says `Stats.Gold / Enemy Defeat / Up`. But per §14.1 enemies
already pay +1 gold — the Idol pays **+1 more**. It does not *create* that flow,
it **thickens** it.

**This is an unsolved schema problem.** Without a way to mark a row as modifying
an existing edge rather than creating one, edge-thickness weights will
double-count every relic that is really a multiplier.

### 5.4 Hops to the Amulet: one node, two colours

From §7.4, closing on the Amulet hands the board extra turns at the end of every
reported game (5+ hops: 0 turns, 3–4: 1, 2–0: 2). So closing in is *good*
(progress toward the win) and *bad* (more enemy turns, and a turn is when things
hit you) from the same arrowhead.

That is the most Zomboid-shaped mechanic in the game, and it only appears as a
`Stat`-typed structural row. It is not derivable from any content.

---

## 6. Known problems in the data

Live at last look — verify against the pushed workbook before acting.

| Problem | Detail |
|---|---|
| **`Scramble` has no Good Direction** | D6 targets `Stats · Scramble`; Q–R has no entry. Outstanding across three revisions. Its arrow cannot be coloured. |
| **Singular/plural join failure** | Groups leaves say `Bombs, Shields, Items, Pills, Potions`; the System column says `Bomb, Shield, Item, Pill, Potion`. Five will not match, and a naive group-by **will not error** — it will silently drop those systems from the supersystem view. Pick one convention, enforce with data validation. |
| **Five systems ungrouped** | `Enemy`, `Goal`, `Grid`, `Tile`, `Object` appear in the System column and nowhere in the Groups tree. See §7. |
| **`Node Type` mixes tiers** | `XIV - Temperance` has Node Type `Loot`, but Loot is a *branch* in the Groups tree containing Cards, while `Item` is a leaf. If Temperance is a card its type is `Card`. Keep Node Type at leaf granularity and let the tree group. |
| **`Otainable` does two jobs** | It holds places (`Chest`, `Boss Chest`, `Starter`), triggers (`Game Completion`, `Enemy Defeat`), qualified refs (`Event: Arcade`), and bare types with no name (`Items`). Proposed fix in §7. |
| **Case inconsistency in `Dir`** | Hot Bombs had a lowercase `up`. A naive group-by makes that a distinct value. Validate, or use dropdowns. |
| **Alien Baby — confirm intent** | Now reads `Enemy Max Health / Up` against a Good Direction of `Down`, i.e. an unambiguous **red** arrow: Alien Baby *raises* enemy max health as the cost of its two health buffs. This is the row that exposed the §4.1 ambiguity, so it is worth confirming with the user rather than assuming. |

*Resolved:* Echo Chamber was a self-loop (`Loot / Loot Use / Loot Use`); its
target became `Loot Copy` and the loop is gone.

---

## 7. Open questions — do not decide these alone

1. **The Groups tree needs at least three more top-level branches.** Only things
   you *accumulate* are grouped today. A proposed shape, **offered but not
   accepted by the user** — check before implementing:

   ```
   Resource     Stats · Health · Shields · Bombs · Collectables ▸ Items, Loot ▸ Pills, Scrolls, Potions, Cards
   Opposition   Enemy · Goal
   Board        Grid · Tile · Object
   Progress     Level · Curse · Hops to Amulet
   ```

2. **How to mark a modifier edge** vs. an edge-creating one (§5.3).

3. **Should `Otainable` split into `Source` + `Source Trigger`?** An inbound edge
   has the same anatomy as an outbound one, so giving it the same two columns
   would leave the parser one grammar instead of four string shapes to guess
   between. Proposed, not decided.

4. **Trigger → emitting-system lookup** (§4.2) — needs authoring, ~14 rows.

5. **Scope.** The stated intent is *every* event, loot, item and mechanic. The
   red arrows overwhelmingly live in `enemies2.0`, `statuses2.0`, `curses2.0`,
   difficulty scaling and amulet pressure — until those are in, the chart
   flatters the game, because items are buffs by nature.

6. **The layer no other roguelike chart has.** Combat here is *going and actually
   playing a real game*. There are nodes above the ones listed: game length,
   whether you own it, how good you are at it, how much evening you have. If the
   chart stops at Health and Bombs it is a chart of any roguelike; if the top row
   is the player's real free time, it is a chart of this one.

---

## 8. When it comes time to build

Nothing here is built. The intended shape:

- **`tools/build_systems_graph.py`**, following the conventions of
  `tools/build_map_charts.py` — read the sheet, emit the trigger map as
  SVG/drawio with computed colours and content-count thickness, plus an audit
  block written back onto the sheet.
- **Writing back to the workbook goes through `tools/_xlsx_surgery.py`, never
  openpyxl** — a round-trip drops the workbook's eight charts. The `_*_setup.py`
  one-shots are the worked examples. (See `CLAUDE.md`.)
- Existing map-diagram assets that may be worth reusing for layout or styling:
  `tools/Roguelikes.drawio`, `tools/map_layout.py`, `tools/map_declutter.py`.

Recommended order of work: settle the vocabulary questions in §7 **first** —
renaming things is cheap now and expensive once a renderer and several hundred
rows depend on the strings.
