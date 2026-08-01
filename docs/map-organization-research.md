# Map Organization — research note

Status: **research / no code changes.** Answers the question "is there a clearer
way to organize the map, and what can be done with a graph this connected?"
Recommendations are ranked but none are decided — this is input to a decision,
not a spec.

An interactive companion renders all five layouts below against the real
catalog: <https://claude.ai/code/artifact/a1955a75-bd47-44b9-a39b-47392693caeb>

---

## 1. The premise, corrected

**The map is not densely connected.** That framing drives you toward techniques
(edge bundling, matrix views, 3D) that solve a problem this graph doesn't have.
Measured over all 751 `data/games/*.tres`, treating `games_influenced` as
undirected exactly as `RunGraph._build_adj()` does:

| Property | Value |
| --- | --- |
| Nodes | 751 |
| Undirected edges | 988 |
| Average degree | 2.63 |
| **Median degree** | **1** |
| Degree-1 games (leaves) | 301 (40%) |
| Degree-0 games (isolated) | 89 (12%) |
| Largest hub | Slay the Spire, 124 |
| Components | 97 — one of 648, the rest are pairs and singletons |
| Giant component | 648 nodes / 981 edges → **334 independent cycles** |

A spanning tree of the giant component needs 647 edges and it has 981, so only
334 edges create a loop at all. **Two thirds of the map is tree structure**,
which is the single most layout-friendly shape a graph can have.

What makes a naive drawing unreadable is not overall density — it is that five
nodes hold 344 of the 1,976 edge endpoints:

| Game | Degree | Leaves hanging off it |
| --- | ---: | ---: |
| Slay the Spire | 124 | 36 |
| Vampire Survivors | 79 | 48 |
| The Binding of Isaac | 62 | 12 |
| Hades | 40 | 10 |
| Balatro | 39 | 16 |

A force-directed layout collapses those five neighbourhoods into solid discs of
ink and pushes the 89 isolated games out as a debris ring. That is the *whole*
visual problem, and it is concentrated in five places rather than spread across
the map.

---

## 2. Four properties the data already has

None of these need new content, new fields on `GameData`, or a re-import. They
are true of the authored catalog today and the current layout ignores all four.

### A — Time is a total order

Of the 988 authored directed edges, **981 point from an older game to a newer
one, 7 join same-year games, and zero point backwards.** Release year is a
global coordinate that no edge violates.

This holds because of a specific authoring rule: **`year` is earliest public
availability, not 1.0.** An early-access date, or a demo where that is when the
game began influencing others — Balatro is dated 2023 for its demo rather than
its 2024 release. The rule is load-bearing, not cosmetic. Balatro influences
Schism, also 2023; under a 1.0 date Balatro would become 2024 and that edge
would run backwards, breaking the acyclicity the entire chronological layout
depends on. `tools/check_map_sync.py` fails loudly on any backward edge.

This is the most valuable fact in this document. It means the influence graph is
a DAG in time, that year can be an axis with no edge ever doubling back, and
that Sugiyama-style layering is essentially free — the hard part of layered
graph drawing (cycle removal) is already done by the data.

Caveat worth stating precisely: years increase monotonically **along any single
route**, but a BFS layer taken as a whole can span decades — a real hop-3 layer
in the companion spans 1980–2016. Per-layer year *ranges* are truthful; a single
year per layer is not.

### B — Genre is cohesive

**80% of edge endpoints join two games of the same `GameType`.** Genre is a
near-partition, which makes it a legitimate swimlane axis: most edges stay inside
a lane and stay short, and the 20% that cross lanes are the interesting
cross-pollination events rather than noise.

### C — The core is tiny

k-core peeling leaves **312 games in the 2-core and 91 in the 3-core.** The other
439 are pendant fringe. 91 labelled nodes is comfortably drawable at a readable
size, and it is exactly the part of the map runs actually travel through.

### D — Runs are small

Across 300 simulated start/amulet pairs at the shipped `MIN_PATH_LENGTH`..
`MAX_PATH_LENGTH` = 5..7 (eligible starts filtered at degree ≥ 3, matching
`pick_amulet_and_starts`), the shortest-path DAG held:

| Measure | Median | p90 | Worst |
| --- | ---: | ---: | ---: |
| Nodes in DAG | 9 | 19 | 38 |
| Widest layer | 2 | 8 | 16 |
| Edges in DAG | 10 | 28 | 65 |

Only 1% of runs produce a layer wider than 12, and none exceeded 40 nodes total.
**`RunMapModal` is not straining.** Its zoom controls are solving a problem that
occurs in roughly one run in a hundred.

Runs also concentrate heavily: Slay the Spire sits on 59% of all run corridors,
The Binding of Isaac on 48%, Spelunky Classic on 37%.

---

## 2a. The hand-drawn map already solves this

`tools/RoguelikeMap.svg` is a draw.io canvas with **750 labelled nodes and 1,038
edges** — against 751 games and 988 connections in the sheet. The draw.io XML
model is embedded in the SVG's `content` attribute, so it is fully
machine-readable — geometry, styles and all. Run `tools/check_map_sync.py` to
parse it. (`Roguelikes.drawio6.svg` is an older export of the same map, kept for
comparison; it had 491 nodes and 663 edges.)

**Its Y axis is release year.** A column of 48 year labels runs down the left
edge at x = -10460, from 1978 to 2026, at a near-exact **196 px per year**. And
the placement is disciplined: of the 741 nodes that match a game in the sheet,
**728 (98%) sit within 0.75 years of their recorded release year.**

That is section 2A of this document, built by hand, years before this research
note. The recommendation to put year on an axis is not a new idea to import —
it is the existing practice, and the thing to do is stop throwing it away when
the data reaches Godot.

Two further things the hand map knows that `GameData` does not:

**It distinguishes three kinds of relationship**, per its own legend, encoded as
stroke colour:

| Legend | Stroke | Count |
| --- | --- | ---: |
| Inspired / Was Iterated Upon By | default | 868 |
| Sequel / Same Devs & Inspired | `#0000FF` | 119 |
| Neither creators knew about the other | `#C8C8C8` | 51 |

`games_influenced` is a single flat `Array[StringName]`, so all of this
collapses to one undifferentiated edge type. The distinction already exists in
`Roguelikes.xlsx` too — the `connections` sheet has a **`Dev/Series Relation`**
column with 109 rows marked, and `import-games-godot.py` drops it.

The third category matters most: "neither creators knew about the other" is
explicitly *not* an influence, and a run must not be able to travel along it.
The good news is that it is clean today — **none of the 50 convergent links have
leaked into the `connections` sheet.** That is an invariant worth keeping, and
`check_map_sync.py` asserts it.

**The `Source` column is 89% populated.** 875 of the 988 connections already
carry a URL or note backing the claim. The README lists "Connection proof" as an
unbuilt roadmap item; the data is largely gathered already and simply is not
imported. `GameData` has nowhere to put it.

### Drift between the map and the sheet

The two are maintained separately and have drifted **in both directions**,
though the current map is close:

| | Count |
| --- | ---: |
| Games matched by name | 741 |
| Games in the sheet, not drawn | 10 |
| Games drawn, not in the sheet | 1 (plus 5 legend / era text boxes) |
| Connections in the sheet, not drawn | 20 |
| Connections drawn, not in the sheet | 14 |
| Nodes whose Y disagrees with the sheet's Year | 13 |
| Labels drawn more than once | 3 |

Most of the remainder is a handful of specific, fixable discrepancies rather
than broad drift:

- **`Gunlocked` is drawn twice**, at ~2022 and ~2025. The second one is almost
  certainly *Gunlocked 2* left unrelabelled — which explains three separate
  symptoms at once: the phantom self-loop `Gunlocked -> Gunlocked`, the year
  conflict (drawn ~2025, sheet says 2022), and `Gunlocked 2` appearing as
  missing from the map.
- **`Disfigure` is drawn twice** eight pixels apart — an accidental duplicate.
- **`Ragnarok` is drawn twice**, at ~1992 and ~1993. Possibly two real games of
  that name, possibly a duplicate; worth a look.
- **`Crafty Survival` (map) vs `Crafty Survivors` (sheet)** — a one-letter
  difference that makes one game look absent from both sides at once.
- Several pairs disagree on *which* title is the parent. The map draws
  `Cataclysm -> Cataclysm: The Last Generation` while the sheet records
  `Cataclysm: Dark Days Ahead -> Cataclysm: The Last Generation`, and the two
  swap roles on the Bright Nights link. Same for
  `FTL -> Fights in Tight Spaces` (map) against
  `Into the Breach -> Fights in Tight Spaces` (sheet).

The 13 year disagreements are an early-access / 1.0 distinction. Under the
earliest-availability rule (§2A) the checker splits them by direction:

- **9 drawn later than the sheet** — a 1.0 date most likely crept onto the map.
  Knock on the Coffin Lid is drawn at 2024 and recorded as 2020; We Need To Go
  Deeper 2019 vs 2017; Terraformers 2023 vs 2022. The sheet is probably right in
  each of these and the node should move up.
- **4 drawn earlier than the sheet** — here the *sheet* may be carrying the 1.0
  date. Buckshot Roulette is the clearest: drawn ~2023, recorded 2024, and its
  itch.io release preceded the Steam one. Beat Blast, Elin and Quest of Dungeons
  differ by a single year and could go either way.

Only the second group can actually break anything, since moving a game later is
what creates a backward edge. Neither group does today.

Re-run the checker after either side changes:

```
python3 tools/check_map_sync.py tools/RoguelikeMap.svg --full
```

---

## 3. The reframe

There are two different maps here with opposite problems:

- **The run corridor** is *too small to feel like a map*. Nine boxes and some
  arrows, with no context for what was passed up.
- **The full atlas** is *too big to lay out* naively — but only because of five
  supernodes and 390 dead-end games.

Serving both with one view is why neither reads clearly. Every recommendation
below follows from splitting them.

---

## 4. Recommendations, ranked

### 1. Layer the run map by year, not just by BFS depth

`shortest_path_dag()` already returns layers indexed by hop count. Keep the DAG;
label each layer with the release-year range it spans and sort within a layer
chronologically.

Roughly 40 lines in `RunMapModal.gd`, view-only, no model change — the existing
`test_run_map.gd` assertions all still hold. It turns six anonymous boxes into a
legible lineage, which is the fantasy the whole project is built on and is
currently invisible on the one screen meant to show it.

### 2. Give the corridor a shoulder

The map draws only games on a shortest path, so a detour looks like it leads
nowhere — the map literally does not draw it. Add the games one hop *off* the
DAG, dimmer and unlabelled, with a count of what lies beyond.

The median run DAG is 9 nodes; adding the one-hop shoulder brings a real 6-hop
run to ~87 nodes, still small. Needs a new `RunGraph` helper plus modal drawing.
This is what makes Dash, Scramble, Scroll of Teleportation and Winged Boots read
as choices with a visible cost rather than dice rolls.

### 3. A separate Atlas screen: year × genre swimlanes

A new view, not a change to the run map. Release year on X, the four `GameType`s
as four horizontal lanes, one dot per game, edges as thin left-to-right lines.
(The hand map uses year on **Y** — either orientation works; match whichever
reads better in-engine, but keep the axis.)
Pan and zoom; label on hover and above a zoom threshold.

It is the only layout that shows all 751 games at once and stays readable,
because it spends no effort on positioning — both coordinates are read straight
off `GameData`, so it is deterministic and stable across runs forever. Doubles as
the Collection backdrop and as the Run History post-mortem surface.

Known cost: the catalog is heavily modern (330 games in 2020–24, 194 in 2025+,
about 90 before 2010), so a linear year axis leaves the left third sparse and
crowds the right. Honest, but it needs zoom to be usable. Within one (lane, year)
cell the games must wrap into a second column or a dense year bleeds into the
neighbouring lane.

### 4. Collapse the fringe into its parent

In any atlas view, don't draw degree-1 games as nodes — draw them as a count on
the hub they hang off, expandable on click. This removes 301 nodes and 301 edges,
40% of the map, while losing no reachability information: a leaf's only route is
back through its parent. The five supernodes that create the hairball are exactly
the five that shed the most ink.

Cost: a player's owned or beaten game can end up hidden inside a fold, which
matters if the atlas doubles as the Collection. Folds would need to auto-expand
around owned/beaten games.

### 5. Name the regions after their capitals

Assign every game to its nearest hub by BFS and treat that as a named region.
One cached BFS per capital. It gives players vocabulary for where they are, and
it is honest about the data — the map already *has* capitals.

Cost: regions are wildly uneven; the Slay the Spire reach dwarfs the rest.

### 6. An index, not a picture

A sortable, filterable table of all 751 games — year, genre, degree, hops to the
amulet, beaten, owned. No layout at all. For the questions players actually ask
of a 751-item set ("have I beaten this", "what's near the amulet", "what do I
own"), a table beats every node-link diagram and needs no zoom. Worth building
precisely because it is unglamorous: it is the fallback that always works.

---

## 5. Considered and rejected

| Technique | Why it's usually right | Why not here |
| --- | --- | --- |
| Force-directed | Default for arbitrary graphs | Five degree-40+ hubs collapse into ink; layout unstable between runs |
| Hierarchical edge bundling | Tames dense cross-links | 988 edges over 751 nodes is already sparse — nothing to bundle |
| Adjacency matrix | Scales past node-link limits | 751² grid that is 99.65% empty; paths become unreadable |
| Treemap / sunburst | Great for containment | Influence is a network, not a hierarchy; loses the 334 loop edges |
| Hex / tile world map | Genre-appropriate, familiar | Forces a planar embedding the graph doesn't have; fakes adjacency |
| 3D graph | More room for hubs | Occlusion and camera control cost more than the extra dimension pays |

---

## 6. Interaction with the roadmap

Three roadmap items in the README change shape in light of the above:

- **"Connection proof"** — listed as unbuilt, but the `connections` sheet's
  `Source` column is already 89% populated. The work is not gathering evidence;
  it is adding a field to `GameData`, carrying the column through
  `import-games-godot.py`, and surfacing it when inspecting a connection. Adding
  the `Dev/Series Relation` column at the same time would give edges a type,
  which is a prerequisite for anything that wants to treat a sequel link
  differently from an influence link.

- **"Unconnected games"** — the 89 isolated games are 12% of the catalog and can
  never appear on a route. An atlas view makes their absence visible, which
  raises the priority of giving them a purpose (transmute already pulls one
  off-graph).
- **"Tags and path requirements (§6.2)"** — gating edges behind a type or tag
  requirement would add the first real *routing* decisions to a graph that is
  currently 66% tree. It would also be the first thing to break the
  "all edges point forward in time" property if a requirement ever implies
  backtracking, so the year axis and that feature should be designed together.

---

## 7. How the numbers were produced

All figures come from parsing `data/games/*.tres` directly and rebuilding the
undirected adjacency the same way `RunGraph._build_adj()` does (forward and
reverse edge per `games_influenced` entry, deduped, references to absent games
skipped, no `Settings.game_filter` applied). Run-corridor statistics are 300
sampled start/amulet pairs drawn from the giant component at distance 5..7 with
eligible starts filtered at degree ≥ 3.

Measured 31 Jul 2026 at 751 games / 988 undirected edges. Re-run after any
catalog import — the hub degrees in particular move.
