# The systems graph — design notes

**Status: the table is real; the renderer is not.** The `chart` sheet now
carries 151 node rows and 206 arrows — every item, card, pill, potion, scroll
and wand in the game, all 30 enemy abilities, both tiles, and four structural
rules. There is still no generator and no rendered
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
| C | `Node Type` | `Item`, `Card`, `Pill`, `Potion`, `Scroll`, `Wand`, `Object`, `Event`, `Unit`, `Enemy Ability`, `Resource`. See §4.4 — `Resource` is the structural-rule type, and since the review it is a Node Type *only*, never a System. |
| D/H/L/P | `System n` | Target system — the coarse node. |
| E/I/M/Q | `Subsystem n` | Target subsystem — the fine node, what actually moves. |
| F/J/N/R | `Trigger n` | *When* the arrow fires. See §4.2 — this is the important one. |
| G/K/O/S | `Dir n` | `Up` or `Down`. **Magnitude only, never valence.** See §4.1. |

Two lookup blocks sit to the right of the main table. **They have moved** — the
fourth arrow block pushed them two columns right, which is why a parser must
find them by header text and not by letter:

| Cols | Contents |
|---|---|
| U–V | `Subsystem` → `Good Dir` (`Up`/`Down`). The colour table, 60 keys, no duplicates. See §4.1. |
| W | `Groups` — a containment tree over the System vocabulary. See §4.3. |

A row whose `System 1` is `N/A` declares a node with no arrows at all — Potion
of Uselessness and Wand of Nothing. That is deliberate content ("it does
nothing"), not a gap, and the parser must not treat `N/A` as a system name.

### Vocabulary as it actually stands

**Systems** (21, one string each — the singular/plural split is gone): Bombs,
Cards, Charges, Chest, Economy, Enemies, Game Choices, Goals, Grid, Health,
Items, Loot, Movement, Objects, Pills, Potions, Run, Shields, Stats, Statuses,
Tiles. `Economy` holds Gold; `Resource` is a Node Type only (§4.4), never a
system.

**Subsystems:** 60 keys carry a Good Direction, each appearing once, and every
arrow resolves to one.

**Triggers** (30): Item Pickup, Item Use, Card Use, Pill Use, Potion Quaff,
Potion Throw, Scroll Use, Wand Use, Loot Use, Bomb Use, Object Use, Gold Use,
Shop Purchase, Passive, Combat Start, Combat End, Enemy Defeat, Damage Taken,
Health Lost, Enemy Spawn, Enemy Movement, On Level Up, On Transmute Gain,
Game Completion, Game Loss — plus, from the ability rows and the review that
followed: Enemy Passive, Enemy Turn, Enemy Attack, On Player Debuff, and
Shield Absorb. (`Enemy Clog` was folded into `Enemy Turn`.)

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

**Reproduced by `python3 tools/audit_systems_graph.py`, which now EXITS
NON-ZERO** on the faults that are silently wrong rather than loudly wrong — a
contradictory Good Direction, a singular/plural collision, a subsystem filed
under two systems, an unparseable `Otainable`, an unknown trigger, stray
whitespace. **The audit is currently green**, and nothing in the table below is
a fault it can prove — treat a red audit as a regression, not as normal.

| Problem | Detail |
|---|---|
| **`Dash` is a dead Good Direction entry** | No row targets it. Harmless, and the last of the three that used to sit here. |
| **`Event: Golden Idol` resolves to nothing** | The `events` sheet has a Golden Idol; the chart has no node row for it, so the reference dangles. Nine other events are in the same position — see §6A. |
| **`Alien Baby` — still worth confirming** | Reads `Enemies · Enemy Max Health / Enemy Spawn / Up` against a Good Direction of `Down`, i.e. an unambiguous **red** arrow: Alien Baby *raises* enemy max health as the cost of its two health buffs. This is the row that exposed the §4.1 ambiguity, so confirm rather than assume. |

Everything else §6A raises about the ability rows is a *judgement* call — a
missing arrow, a duplicated trigger name, a modelling choice — rather than a
fault the audit can prove. They are listed there, not here.

*Resolved since the last revision.* Worth reading before assuming a fault is
new, because several of these looked like different problems than they were:

- **The singular/plural collisions are gone.** `Bomb`/`Bombs`, `Tile`/`Tiles`,
  `Object`/`Objects` and `Pill`/`Pills` were folded onto plural, and `Item` went
  with them so the System column and the Groups tree finally use one spelling.
  `tools/_chart_system_vocabulary.py` did it and is idempotent; `CANON` in the
  audit is now a regression detector rather than a fixer.
- **`Teleport Start Game ` carried a trailing space on BOTH sides** — the arrow
  (E3) and the Good Dir lookup (U50) — so the join worked and nothing complained.
  Tidying either cell alone would have silently uncoloured the arrow. Both were
  trimmed together, and the audit now refuses to strip before comparing so it can
  see this class of fault at all.
- **Every arrow can be coloured.** `Identification`, `Enemy Ability` and
  `Pill Preference` were the three subsystems missing a Good Direction; all three
  are in the table now.
- **`Speed on Player` is filed under `Statuses` everywhere**, not split between
  `Stats` and `Statuses`.
- **`Otainable` parses.** Blood Donation Machine's two qualified references are
  separated with `;` rather than a comma (§4.5).
- **`Arcade` is now `Arcade Room`**, matching the `events` sheet, so its three
  inbound references resolve.
- **`Loot Amount` no longer has two Good Directions.** It was in the table twice
  — `Up` on U29 and `Down` on U58 — and because a repeated key does not error,
  iteration order picked one and picked the wrong one: Degradation and Theft
  coloured GREEN, "an enemy burning your loot is good for you". The `Down` row is
  deleted and the audit now fails on a contradictory duplicate.
- `Scramble` has a Good Direction, Echo Chamber's self-loop is gone (`Loot
  Copy`), `Dir` is uniformly `Up`/`Down` across all 194 arrows, and
  `XIV - Temperance` is typed `Card` rather than `Loot`.

---

## 6A. Where the graph stands, and what to add next

All figures from `python3 tools/audit_systems_graph.py`. **Re-run it rather than
trusting these** — they have already moved once, sharply, since this section was
written.

### The ability rows changed the diagnosis

The 30 `Enemy Ability` rows are the single biggest thing to happen to this sheet,
and they fixed the problem this section was originally written to describe.
Before and after:

| | before | after the rows | after the fixes |
|---|---|---|---|
| node rows | 116 | 146 | **149** |
| system→system edges | 160 | 190 | **195** |
| red edges | 36 (23%) | 63 (33%) | **68 (35%)** |
| cycles (len 2–4) | 14 | 25 | **30** |
| sinks | 8 | 7 | **7** |
| `Enemies → Health` red | **none** | present | present |

The old diagnosis — "the chart says fighting is good for you", because enemies
only ever appeared as the thing that fires Enemy Defeat — is **resolved**. Bodies
now take health, max health, loot, items, gold and turns off you, and the graph
says so.

Two structural wins worth naming, because neither was obvious in advance:

- **Statuses stopped being a sink.** It was the worst one at 27 inbound arrows
  and none out. It now emits, entirely because of **Predatory Scent**, whose
  trigger is `Debuff on Player` — the player carrying an unmet status goal is
  what fires it. That closes `Enemies → Statuses → Enemies`, a real Zomboid loop,
  and it is the only row in the sheet where a *status* is the gate.
- **Theft is the model row.** One ability, three arrows (`Items`, `Loot`,
  `Resource · Gold`), because it really does take three different things. Most
  rows in the batch have one arrow where the mechanic has two or three; see below.

### Coverage

| Covered | | Not covered | |
|---|---|---|---|
| Items | 52/52 | Enemies | 0/54 |
| **Abilities** | **30/30** | Bosses | 0/40 |
| Potions | 15/15 | Characters | 0/11 |
| Cards | 14/14 | Events | 1/11 |
| Wands | 12/12 | Statuses | 0/7 |
| Pills | 10/10 | Curses | 0/3 |
| Scrolls | 8/8 | Tiles | 0/2 |
| Objects 2/2, Units 1/1 | | Amulets, Locations | 0 |

### Sinks: seven systems receive arrows and emit none

A sink is a system that things point *at* and that never points anywhere — which
is precisely a cycle that failed to close.

| Sink | Inbound edges |
|---|---|
| Grid / Movement | 5 each |
| Run | 1 — **deliberate**, see below |
| Chest / Game Choices / Charges | 1 each |

Three systems have left this list in order: Statuses when the ability rows
landed, Shields when `Shield Absorb` was added, and **Tiles** with the two tile
rows. `Run` is a sink on purpose — the run ending is where everything stops.

**The tiles were the last big one**, and they took two rows. Eight arrows set a
tile and nothing happened afterwards; the `tiles` sheet says Fire applies +1 Burn
and Web +1 Stun **to enemies standing on them**, so both are green arrows into
`Statuses`. The trigger is `Tile Step`, emitted by **Tiles** — that is the load-
bearing part. Route it through Enemies (whoever walked on) and the arrow leaves
from the wrong place and Tiles stays a sink.

The seven status rows are still worth authoring even though Statuses is no longer
a sink: it emits through exactly one ability today. The `statuses` sheet holds
each status's combat effect *and* its goal condition — the second half being the
layer no other roguelike chart has (§7 question 6).

### The review fixes, applied

All ten items from the review are in the sheet, via
`tools/_chart_abilities_review_fixes.py` (idempotent). What they bought:

| | before abilities | after abilities | after fixes | + summoners & tiles |
|---|---|---|---|---|
| node rows | 116 | 146 | 149 | **151** |
| edges | 160 | 190 | 195 | **207** |
| red | 36 (23%) | 63 (33%) | 68 (35%) | **68 (33%)** |
| cycles | 14 | 25 | 30 | **32** |
| sinks | 8 | 7 | 7 | **6** |

**Fixed:** the duplicate `Loot Amount` Good Direction is gone (Degradation and
Theft now read red, as they should). Haste points at `Speed on Enemy`. The Gold
system is **`Economy`**, freeing `Resource` to mean one thing — a Node Type for
structural rules. Triggers renamed to `Enemy Attack`, `Enemy Passive` and
`On Player Debuff`, with `Enemy Clog` folded into `Enemy Turn`; that also
un-collides `Debuff on Player`, which stays a *subsystem* name only.

**Three structural rules were added** (§4.4 `Resource` rows — things no item can
express):

| Row | Arrows |
|---|---|
| **Enemy Damage** | `Health · Health Amount / Enemy Attack / Down`, `Shields · Shield Amount / Enemy Attack / Down` |
| **Shield Absorption** | `Health · Health Amount / Shield Absorb / Up` |
| **Lost Game** | `Enemies · Enemy Turn / Game Loss / Up` |

`Shield Absorb` is emitted by Shields and `On Player Debuff` by Statuses. Those
two mappings are why **Shields and Statuses are no longer sinks** — between them
they were 33 inbound arrows and nothing coming back.

The loop that matters most is new and only two hops:

```
Enemies ──red──▸ Goals ──red──▸ Enemies
   (a body curses you)   (a lost game hands the board a turn)
```

An enemy makes the real game harder → you fail the report → the board gets a
free turn → it hits you again. That is the Zomboid shape the whole exercise was
for, and it is derived, not asserted.

**Devour Whole** now points at `Run · End Run` rather than reading as ordinary
damage. `Run` is a sink at 1 inbound — and unlike the others that is **correct**:
the run ending is where everything stops. It is the one terminal node in the
graph, not a cycle that failed to close.

#### Two things deliberately not changed

- **`Immobile` is `Enemy Position / Up`, not `Down`.** The review asked for
  `Down` on the strength of "Immobile is the opposite of Agile, which is Up" —
  but Agile is `Down`. `Enemy Position` reads as distance from you, so Up is
  good for the player: Wand of Teleportation is `Up` (green, it throws a body
  away), Agile is `Down` (red, it closes). A body that cannot close is `Up`.
  One cell to flip if the literal `Down` was meant.
- **`Trample` is `Enemy Position / Up` and looks wrong** for the same reason: it
  shoves a blocker aside in order to *advance*, so it should be `Down` / red.
  Not part of the review, so left for a decision.

### The summoners, and the half the sheet still cannot say

The five summoners — Illusionist, Necromancy, Nested Spawner, Entry Summon and
Split — now carry the payout §7.6 says a summoned body owes: it is an **ordinary
body**, so clearing it pays its loot and its gold. Each has
`Loot · Loot Amount / Enemy Defeat / Up` and `Economy · Gold / Enemy Defeat / Up`
alongside its original red `Enemies · Enemy Amount / Up`.

**That leaves them reading 10 green to 5 red, and that is too kind.** A summoned
body is also an enemy: it has a goal you must go and play, and it can hit you.
Neither cost lands on the summoner's own row, for two different reasons — and
they are worth separating, because only one of them is fixable by typing.

1. **The damage is a §5.3 modifier edge.** `Enemies → Health` already exists once,
   from the `Enemy Damage` rule. A summoner does not *create* that flow, it
   **thickens** it — more bodies, more swings. §5.3 flags exactly this as an
   unsolved schema problem: there is no way to mark a row as multiplying an
   existing edge rather than making a new one, so writing a Health arrow onto
   each summoner would double-count the same swing.
2. **The goal has no subsystem at all.** `Enemy Amount` counts bodies, not the
   evenings they demand, and using it for both would say one thing twice. This
   is the more interesting gap: a goal is *a real video game you have to go and
   play*, which is the cost this game has and no other roguelike chart does.

Adding **`Goals · Goal Amount`** (Good Direction `Down`) would fix the second
one — every summoner, and every `Enemy Spawn`, could then carry the cost of the
game it puts on your evening. It is the first real foothold for §7 question 6,
where the top of the chart is the player's actual free time. It is a **vocabulary
decision, not a fix**, so it has deliberately not been made.

Until one of those lands, read the summoner cluster knowing its red is
structurally under-weighted — the same way §5.1 warns the bomb cluster reads as
four green arrows and a lie.

### Still open on the ability rows

- **`Ranged` stops at `Enemy Range / Up`** — no arrow for reaching you sooner.
- **`Fading → Enemy Health / Down`** models a timer as damage; `Enemy Amount /
  Down` is truer.
- **All 30 rows have `Otainable = Enemy Spawn`**, so abilities hang off one
  generic node rather than chaining to the bodies that carry them
  (`Enemy: Sharky`). Only 39 of 94 bodies carry one, so the chain would say
  something. §5.2 is the argument.
- **`Bolster` / `Melee Ally Buff` point at a generic `Buff on Enemy`**, so a
  Bishop's Dexterity aura and a thrown Dexterity Potion never meet at a node.
- **`Aftermath → Tiles · Fire Tile`** hardcodes its only current argument — and
  now that `Web` is a node too, the second tile it could name actually exists.

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
