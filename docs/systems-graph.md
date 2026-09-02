# The systems graph — design notes

**Status: the table is real; the renderer is not.** The `chart` sheet now
carries 116 node rows and 159 arrows covering every item, card, pill, potion,
scroll and wand in the game. There is still no generator and no rendered
output. What exists is `tools/audit_systems_graph.py` — read-only, run it any
time — which checks the sheet's hygiene, reports coverage against the content
sheets, and performs the §4.2 collapse to show the signed system→system graph,
its cycles, and its sinks. **Every count in this document comes from that
script; re-run it rather than trusting the numbers here.**

This document is the accumulated design thinking, so a session picking it up
doesn't re-derive it or re-litigate decisions already made.

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

## 2. Where the data lives

The table is the **`chart` sheet** of `tools/Roguelikes.xlsx` (sheet 49,
`xl/worksheets/sheet21.xml` — it was sheet20 before the `wands` sheet was
inserted; resolve it through `xl/_rels/workbook.xml.rels` rather than hardcoding
the number).

> **The warning that used to stand here is resolved.** Earlier revisions of this
> document described a schema that existed only in screenshots, because the
> workbook on `main` still carried the original `Name / Type / Subtype /
> Preference` header. The workbook was pushed in d619afd and **now carries the
> schema in §3**, plus a fourth arrow block the design had not anticipated.
> §3 and §6 below were re-derived from the pushed file, not transcribed.

Read the sheet with `_xlsx_surgery.Workbook.read_grid`, never openpyxl — see
CLAUDE.md and §8.

---

## 3. The schema as it currently stands

One row per node. Columns A–C identify it, then a repeating four-column block
declares its outgoing arrows. **There are four blocks now, not three** — Fysh
Oil in row 87 uses all four. The block is designed to extend further; a parser
should walk them by stride rather than naming D/H/L/P.

| Col | Header | Meaning |
|---|---|---|
| A | `Node` | The thing. `Alien Baby`, `Blood Donation Machine`, `Bombs`. |
| B | `Otainable` *(sic)* | Where it enters the run — see §4.5, this column is overloaded. |
| C | `Node Type` | `Item`, `Card`, `Pill`, `Potion`, `Scroll`, `Wand`, `Object`, `Event`, `Unit`, `Resource`. See §4.4. |
| D/H/L/P | `System n` | Target system — the coarse node. |
| E/I/M/Q | `Subsystem n` | Target subsystem — the fine node, what actually moves. |
| F/J/N/R | `Trigger n` | *When* the arrow fires. See §4.2 — this is the important one. |
| G/K/O/S | `Dir n` | `Up` or `Down`. **Magnitude only, never valence.** See §4.1. |

Two lookup blocks sit to the right of the main table. **They have moved** — the
fourth arrow block pushed them two columns right, which is why a parser must
find them by header text and not by letter:

| Cols | Contents |
|---|---|
| U–V | `Subsystem` → `Good Dir` (`Up`/`Down`). The colour table, 52 entries. See §4.1. |
| W | `Groups` — a containment tree over the System vocabulary. See §4.3. |

A row whose `System 1` is `N/A` declares a node with no arrows at all — Potion
of Uselessness and Wand of Nothing. That is deliberate content ("it does
nothing"), not a gap, and the parser must not treat `N/A` as a system name.

### Vocabulary as it actually stands

**Systems** — 22 distinct strings, but only **19 systems**, because three
singular/plural pairs collide (§6): Health, Statuses, Stats, Enemies, Item,
Shields, Loot, Goals, Grid, Movement, Pills, Potions, Cards, Chest, Charges,
Game Choices, and the colliding `Bomb`/`Bombs`, `Tile`/`Tiles`,
`Object`/`Objects`.

**Subsystems:** 52 have a Good Direction; three used by rows do not (§6).

**Triggers** (25): Item Pickup, Item Use, Card Use, Pill Use, Potion Quaff,
Potion Throw, Scroll Use, Wand Use, Loot Use, Bomb Use, Object Use, Gold Use,
Shop Purchase, Passive, Combat Start, Combat End, Enemy Defeat, Damage Taken,
Health Lost, Enemy Spawn, Enemy Movement, On Level Up, On Transmute Gain,
Game Completion, Game Loss.

Note `Potion Quaff` vs `Potion Throw`: the same potion pointed at yourself or at
a body, and the two get *opposite colours* on the same subsystem. That split is
the schema working exactly as §4.1 intended, and it is where a third of the
graph's red currently lives.

---

## 4. Decisions already made, and why

These were worked out in conversation and are settled. Each one exists for a
reason that is not obvious from the column headers alone — please read the
rationale before changing any of them.

### 4.1 Colour is computed, never hand-entered

**The rule:** `Dir` records only which way the number moves. Colour comes from
`Dir × Good Direction`, looked up per subsystem in U–V (§3).

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
| Item Pickup / Loot Use | Loot |
| Card Use | Cards |
| Pill Use | Pills |
| Potion Quaff / Potion Throw | Potions |
| Scroll Use | Scrolls |
| Wand Use | Wands |
| Item Use | Items |
| Bomb Use | Bombs |
| Object Use | Objects |
| Gold Use / Shop Purchase / On Transmute Gain | Stats |
| Combat Start / Combat End / Enemy Defeat / Damage Taken / Enemy Spawn / Enemy Movement | Enemies |
| Health Lost | Health |
| Game Completion / Game Loss / On Level Up | Goals |
| Passive | *(the `Otainable` source — see below)* |

— and you have a pure signed **system → system** graph *with cycles*, derived
entirely from rows already typed. Health keeps you alive → you defeat more
enemies → Enemy Defeat fires Charm of the Vampire → Health. That is a Zomboid
loop, and it fell out of the data rather than out of anyone's head.

**This lookup now exists**, as `EMITTED_BY` in `tools/audit_systems_graph.py`.
It is the single place the trigger vocabulary is interpreted; a new trigger
string that is not in it is reported rather than silently dropping its arrows.
Running the collapse over the current sheet produces **160 system→system edges
and 14 cycles**, so the central bet of the design is confirmed: the two-hop
reading does generate loops out of rows nobody authored as loops.

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

**How the tree is actually stored, and why that is fragile.** Column W holds a
flat list of 15 strings with blank cells between blocks and *no indentation*
(checked: no cell carries an `indent` alignment). The convention appears to be
*first cell of a block is the parent, the rest are its children*, blank row
between blocks:

```
Resource | Stats, Health, Bombs, Collectables, Shields
Collectables | Items, Loot
Loot | Pills, Scrolls, Potions, Cards, Wands
```

That decodes, but a blank row is the only delimiter, so inserting one row
silently reparents a branch and nothing errors. Before a generator depends on
it, either give W a real `Parent | Child` two-column shape or indent it and read
the indent level. Note also that `Loot` appears twice — as a leaf of
Collectables and as a parent — which is correct as a tree but will trip a parser
that assumes each name appears once.

### 4.4 A structural row is a node type of its own — now `Resource`

Row 96 is `Bombs` — Node Type **`Resource`** (this was `Stat` in an earlier
revision; the sheet is the authority), arrow `Enemies · Enemy Health / Bomb Use
/ Down`, obtained from `Item: Blood Bombs, Brimstone Bombs, Hot Bombs, Sticky
Bombs; Character Start: Isaac`.

Bombs are not content. You cannot pick up a "Bombs". That row states a **rule**:
spending a bomb damages an enemy. It also shows the pattern at its best — the
four bomb items feed the resource, and the resource is what actually acts, so
the items stop being four parallel arrows into Enemies and become a supply
chain into one.

An earlier proposal in this design was a second worksheet for hand-authored
structural edges. **That proposal is superseded.** A structural node type is
cleaner: same grammar, same columns, one table, one vocabulary that cannot
drift, and the renderer can still style rule-edges differently. Every structural
edge belongs here as a `Resource`-typed row.

**There is exactly one such row today.** That is the graph's largest structural
gap, and §6A says what the others should be.

### 4.5 `Otainable` is a foreign key, and it is what makes this a graph

It holds `Type: Name` references to other rows — `Object: Blood Donation
Machine`, `Event: Golden Idol`, `Item: Landmines` — with commas for multiples
(`Starter, Chest`). That means **content chains to content**, and the graph can
be walked across node types. See §5.2.

**The "make comma-splitting universal" proposal is now wrong, and the sheet is
what killed it.** Two separators are in use and they mean different things:

```
Item: Blood Bombs, Brimstone Bombs, Hot Bombs; Character Start: Isaac
└──────────── one reference, three names ────┘  └── second reference ──┘
```

So **`;` separates references, `,` separates names inside one**. Split on commas
universally and `Character Start: Isaac` becomes a place called
`Character Start: Isaac` and the four bombs become four unqualified strings.
`tools/audit_systems_graph.py` implements the two-level rule in `split_cell()`.

The catch: `Starter, Chest` (D6) and `Enemy Defeat; Game Completion` (every
loot row) both mean "two places", one with each separator. Bare place names are
unambiguous either way so both parse, but the sheet should settle on `;` for
consistency, and one row is genuinely broken by the mixture — see §6.

Trigger cells take commas too (`Object Use, Bomb Use`), fanning one row into two
edges. There the comma is unambiguous because trigger names never contain one.

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

**Re-derived from the pushed workbook, and reproduced by
`python3 tools/audit_systems_graph.py`.** The list is much shorter than it was —
most of what stood here got fixed by the revisions that filled the sheet out.

| Problem | Detail |
|---|---|
| **Three subsystems have no Good Direction** | `Identification` (3 arrows: Amnesia, Scroll of Amnesia, Scroll of Identify), `Enemy Ability` (2: Wand of Cancellation, Wand of Invisibility), `Pill Preference` (1: Lucky Foot). §4.1 makes this a hard error — six arrows currently cannot be coloured. `Enemy Ability` is the interesting one: Cancellation removes an ability and Invisibility grants one, so its Good Direction is `Down`. |
| **Three Good Direction entries are dead** | `Dash`, `Loot Amount`, `Preference` — no row targets them. `Preference` is probably a stale near-miss for `Pill Preference` above; renaming it fixes a dead entry and an uncoloured arrow at once. |
| **Singular/plural collisions** | `Bomb`/`Bombs`, `Tile`/`Tiles`, `Object`/`Objects` all appear in the System column. A naive group-by **will not error** — it silently renders each as two systems. The audit script folds them via `CANON`; the sheet should pick one and enforce it with data validation. (The `Item` vs Groups-leaf `Items` mismatch is the same problem across the two vocabularies.) |
| **`Speed on Player` is filed under two systems** | `Stats` on Caffeine Pill, Bionic Face Plating and The Mark; `Statuses` on Potion of Haste Self. It is a status; the three item rows should say `Statuses`. Unlike the collisions above this one is not mechanical — a subsystem genuinely belongs to one system, so this is a data fix, not a canonicaliser entry. |
| **One `Otainable` cell cannot be parsed** | Blood Donation Machine reads `Event: Arcade, Loot: XIV - Temperance` — two qualified references joined by a comma, where comma means "another name in the same reference" (§4.5). It needs a `;`. |
| **`Event: Golden Idol` resolves to nothing** | The `events` sheet has a Golden Idol, but the chart has no node row for it, so the reference dangles. Ten other events are in the same position — see §6A. |
| **`Arcade` vs `Arcade Room`** | The chart's one Event node is `Arcade`; the `events` sheet calls it `Arcade Room`. The foreign key between the two sheets is the name, so it must match exactly. |
| **`Alien Baby` — still worth confirming** | Reads `Enemies · Enemy Max Health / Enemy Spawn / Up` against a Good Direction of `Down`, i.e. an unambiguous **red** arrow: Alien Baby *raises* enemy max health as the cost of its two health buffs. This is the row that exposed the §4.1 ambiguity, so confirm rather than assume. |

*Resolved since the last revision:* `Scramble` now has a Good Direction. Echo
Chamber's self-loop is gone (`Loot Copy`). `Dir` case is uniform — 159 arrows,
every one `Up` or `Down`. `XIV - Temperance` is typed `Card`, not `Loot`, so
Node Type is at leaf granularity throughout. And `Otainable` no longer holds
bare untyped plurals.

---

## 6A. Where the graph stands, and what to add next

All figures from `python3 tools/audit_systems_graph.py`.

### Coverage: the loot half is done, the pressure half is empty

| Covered | | Not covered | |
|---|---|---|---|
| Items | 52/52 | Enemies | 0/54 |
| Potions | 15/15 | Bosses | 0/40 |
| Cards | 14/14 | Abilities | 0/30 |
| Wands | 12/12 | Characters | 0/11 |
| Pills | 10/10 | Events | 1/11 |
| Scrolls | 8/8 | Statuses | 0/7 |
| Objects | 2/2 | Curses | 0/3 |
| Units | 1/1 | Amulets, Locations, Tiles | 0 |

That split is the whole diagnosis. **118 of the 160 edges are green and 36 are
red**, and the red is not where you would expect: two-thirds of it is a player
pointing a consumable the wrong way (`Potion Throw` of Strength Potion buffs the
enemy). The *game pushing back* — enemies dealing damage, statuses burning you,
curses, difficulty scaling, amulet pressure — contributes essentially nothing,
because none of those things has a node row.

The sharpest single number: **there is no `Enemies → Health` red edge at all.**
Enemies currently appear in the graph as a *benefit* — they fire Enemy Defeat
and Combat End, which is what gates Charm of the Vampire and Burning Blood. The
chart says fighting is good for you. §5.1's warning about the bomb cluster
reading as "four green arrows and a lie" applies to the entire opposition side.

### Sinks: eight systems receive arrows and emit none

This is the more actionable finding, and it is cheaper to fix than the coverage
table suggests. A sink is a system that things point *at* and that never points
anywhere — which is precisely a cycle that failed to close.

| Sink | Inbound edges |
|---|---|
| **Statuses** | **27** |
| Tiles | 7 |
| Shields | 6 |
| Movement | 5 |
| Grid | 5 |
| Game Choices / Charges / Chest | 1 each |

Statuses is the prize. Twenty-seven arrows set Burn, Strength, Dexterity, Speed
and Stun on somebody, and then the graph stops — nothing says what having Burn
*does*. Seven rows would fix it, and the `statuses` sheet already contains both
halves of each answer:

- a **combat** effect (`Burn`: half damage dealt; `Stun`: skip their turn;
  `Strength`: +X damage dealt; `Speed`: +X tile movement; `Marked`: damage taken
  ×2, ignores shields)
- a **goal** condition — the status makes the real game you go off and play
  harder ("beat a run while skipping X items", "beat it in under N hours")

That second half is worth dwelling on. It is §7 question 6's "layer no other roguelike
chart has", already authored, sitting in a sheet, one node type away from being
in the graph. `Burn → Goals · Goal Difficulty (Up)` is an arrow no other game's
systems chart could draw.

Tiles is the same shape and cheaper still: two rows. Five items set Fire Tile
and nothing happens; the `tiles` sheet says Fire applies +1 Burn to whoever
stands on it, which is `Tiles → Statuses`, which then reaches Health once
Statuses exists. Fire → Burn → Health is a three-hop return leg for the price of
nine rows total.

### Recommended order

Cheapest-first, and deliberately not the order the coverage table implies.

1. **Fix the six uncoloured arrows and the two broken references** (§6). Half an
   hour, and until it is done every downstream count is provisional.
2. **7 status rows + 2 tile rows.** Closes the largest sink, adds the goal-
   difficulty layer, and turns 34 dead-end arrows into paths. Highest ratio of
   loops-gained to rows-typed in the whole backlog by a wide margin.
3. **~6 `Resource` rows** (§4.4). Structural rules, not content, and each one
   closes a loop no item can: `Enemies → Health` (bodies deal damage),
   `Enemy Defeat → Stats · Gold` and `→ Loot` (the +1 gold and the drop that
   §5.1 says bombing severs), `Health → Goals` (dying ends the run),
   `Hops to Amulet → Enemies` (§5.4's two-coloured arrowhead),
   `Goals · Level Up → Enemies` (difficulty scaling). Six rows, and they are
   what turns the fan into the Zomboid picture — more signal than all 54
   enemies would add.
4. **10 event rows.** Events are already the graph's best chains (§5.2) and one
   dangling reference is waiting on them.
5. **3 curse rows.** Small, and pure red — the only pure-red content in the
   game.
6. **Enemies and abilities last.** 84 near-identical rows for a diagram that
   collapses them all onto one `Enemies` node anyway. The abilities are the
   interesting subset — Ritual, Necromancy, Split, Theft and Entry Summon are
   genuinely different arrows — so if this tier gets done at all, do the 30
   abilities and skip the 94 bodies.

Your instinct that "events and enemy abilities could be added later" is right,
with one amendment: **statuses and tiles should not wait**, and they are not
what you listed. Nine rows there beat everything else on the list combined.

### Not in the graph at all: the run itself

`games` (858) and `connections` (1241) are the actual map the run is played on,
and no node row references them. Neither do `locations`, `amulets` or
`characters`. §7 question 6 argues the top row of the chart should be the player's real
free time; the honest version of that is a small handful of `Resource` rows —
game length, do you own it, how good are you at it — feeding `Goals`. That is a
design decision, not a data-entry one, which is why it stays in §7 rather
than in the order above.

---

## 7. Open questions — do not decide these alone

1. **The Groups tree still needs at least three more top-level branches.** Only
   things you *accumulate* are grouped today: the tree covers Resource and its
   descendants and nothing else, leaving `Enemies`, `Statuses`, `Goals`, `Grid`,
   `Tiles`, `Objects`, `Movement`, `Chest`, `Charges` and `Game Choices`
   ungrouped — ten of the nineteen systems, and the supersystem view (§4.3)
   cannot be rendered without them. (`Scrolls` and `Wands` have the opposite
   problem: they are in the tree but never appear in the System column, because
   scrolls and wands only ever *emit*.) A proposed shape, **offered but not accepted by the
   user** — check before implementing:

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

4. ~~**Trigger → emitting-system lookup** (§4.2)~~ — **done.** Authored as
   `EMITTED_BY` in `tools/audit_systems_graph.py`, 25 triggers. It lives in code
   rather than on the sheet, which is a decision worth revisiting: on the sheet
   it would be visible and editable without a code change, but in code it
   errors loudly on an unknown trigger. Move it to a lookup block beside U–W if
   the vocabulary starts changing often.

5. **Scope.** The stated intent is *every* event, loot, item and mechanic. This
   was a prediction and it is now measured: the chart runs **118 green to 36
   red**, and two-thirds of the red is a player misusing a consumable rather
   than the game pushing back. Until statuses, curses, enemy damage and amulet
   pressure are in, the chart flatters the game, because items are buffs by
   nature. §6A puts numbers and an order on this.

6. **The layer no other roguelike chart has.** Combat here is *going and actually
   playing a real game*. There are nodes above the ones listed: game length,
   whether you own it, how good you are at it, how much evening you have. If the
   chart stops at Health and Bombs it is a chart of any roguelike; if the top row
   is the player's real free time, it is a chart of this one.

---

## 8. When it comes time to build

**`tools/audit_systems_graph.py` exists** and is the reference implementation of
every parsing rule in §3–§4.5 — the four-block stride, the two-level `Otainable`
separator, `N/A` rows, the singular/plural canonicaliser, the colour rule, and
the trigger collapse. A generator should import from it or move that logic to a
shared module rather than re-deriving it; the parsing rules are the part of this
design that took the longest to get right.

The renderer is still unbuilt. The intended shape:

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
rows depend on the strings. Then §6A's content order. The renderer is last, and
it should be built against a sheet that already has its sinks closed, or the
first picture it draws will be the flattering one.
