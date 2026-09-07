# Performance & streamlining backlog

Findings from a read-only efficiency pass over the whole codebase (2026-08-18).

**Fixed since, and out of this file:** the four measured *atlas* findings (see the
CHANGELOG entry "The star chart stopped doing the same work twice"); then the
star-chart double sweep, the uncached route DAG and the three dead functions
("Two hot paths that were doing the work twice"); then the overworld's full-page
`_refresh` ("The page stopped redrawing things that had not changed"); and then
the glyph shaping cost that one uncovered, by shipping the fonts ("The UI stopped
asking the host what a ⚔ looks like").

**A second pass (2026-09-07)** measured the screens rather than the code, booting
the real scenes headless (script time, no rendering) and under Xvfb. It found the
catalog-sized screens paying for the whole catalog and the run screens in good
shape — `Overworld2` is 154 nodes, `BattlefieldView.refresh()` is 4.5 ms, and
every screen idles at the loop floor with nothing redrawing per frame. **All six
of its findings are fixed** — the compendium's three in §3, the run graph's in §4,
and the screen-fit pair in §5. What that pass left behind is in §6.

**Two items are left from the first pass**, below. §1 is in progress — a fourth
split has landed and the seam table has been re-measured, because the old one had
gone badly stale; §2 is fixed and kept for the shape of it. Each states what is
wrong, why it is wrong, what the fix looks like, and how to know it worked.

**Two measurements worth keeping** from the passes that emptied the rest of this
file, both because they say something about where to look next:

*The quadratic loop that wasn't.* The `Array.has()` edge loop in
`RunGraph.shortest_path_dag` measured **flat** — A/B'd against the same route in
the same process it was 0.322 ms with `Array.has()` and 0.308 ms with a
`Dictionary` set per layer, which is noise. The layers of a real route are two or
three games wide, not the 15+ the degree curve suggested, so the linear scan was
never scanning anything. The set went in anyway (strictly better, measured no
worse) but the memo beside it was the entire win.

*Where the time in a rebuild actually went.* Not, as this file had assumed, in
the offering cards or the pack strip — those are ~1.5 ms and ~0.3 ms. It was in
**five small verb chips, at 10.9 ms**, because every Label carrying one of the
UI's symbol glyphs was making Godot search the host's fonts for it, uncached.
Both times the thing that looked expensive was cheap and something unremarkable
next to it was not. Measure first.

*And the fix for that was not where it looked either.* Declaring the shipped
subsets as theme fallbacks only took 15.4 ms to 12.4 — because the BASE font runs
its own system search on a miss, and runs it BEFORE the fallbacks. Turning that
off and putting a system font at the END of the chain got 4.5 ms with nothing
lost. Then the subsets' own vertical metrics grew every line in the game by 9px,
because Godot takes a font's height as the max over the whole chain; they are
rescaled onto the base font's exact em grid now, which `test_display_settings.gd`
checks at every size the UI uses. Three separate traps in one two-line change.

---

## 1. `Overworld2.gd` is 5826 lines

**This entry said 4260 and had said so for a while.** The file was 5623 when that
number was last true enough to write down, and 6114 by the time anyone re-measured
— so the three splits below did their 24% and then accretion put it all back and
more. That is the finding, not the line count: **a seam table goes stale the
moment it stops being re-run**, and this one was quoted as current for months
while the file grew past its own pre-split size.

Down to 5826 with the drop queue out (`DropQueue.gd`, below). Still the biggest
file in the repo — `AtlasView.gd` is 2764 — holding the run loop, the routing
notes, the map plumbing, the save/restore of view state, and `_build_ui`.

**Where the growth actually went**, measured against the last commit this file was
re-read at: +405 lines of a region that did not exist then (*arriving somewhere you
did not choose* — card teleports, detours, the stay-or-return question, item
aiming) and +138 of card/item actions, against a diffuse +30 or so spread over
everything else. A new mechanic landed in the page rather than beside it. That is
the pattern worth watching: this file does not creep, it absorbs.

**The seam table, re-measured.** *Genuinely shared state* is vars the region
touches that are also touched outside it, ignoring `_build_ui` (the assembler
touches everything and stays behind either way). *Forwards* is how many of the
region's functions are called from the rest of the page or straight off `_ui` in
`test_overworld2.gd`, which is the boilerplate a split leaves behind.

| seam | lines | funcs | genuinely shared state | forwards |
|---|---|---|---|---|
| ~~item strip + charge chips~~ | ~~293~~ | | ~~2~~ | **done — `PackStrip.gd`** |
| ~~report checklist~~ | ~~776~~ | | ~~2~~ | **done — `ReportChecklist.gd`** |
| ~~offering cards + preview~~ | ~~506~~ | | ~~3~~ | **done — `OfferingCards.gd`** |
| ~~kill-drops + floor loot~~ | ~~498~~ | ~~22~~ | ~~11~~ | **done — `DropQueue.gd`** |
| routing + the report verb | 606 | 11 | 17 | 8 |
| `_build_ui` | 519 | 1 | 36 | 1 |
| save/restore view state | 467 | 14 | 22 | 8 |
| arriving somewhere you did not choose | 405 | 16 | 17 | 6 |
| the header, pinned to the screen | 328 | 16 | 12 | 7 |
| the stats that moved out of the HUD | 280 | 12 | 13 | 7 |
| the road walked, across the top | 231 | 7 | 16 | 5 |
| escaping a game you can't beat | 185 | 7 | 4 | 6 |
| throwing a potion at the board | 183 | 8 | 6 | 3 |

**The next cut is `arriving somewhere you did not choose`** (405 lines, 16 funcs) —
it is the region that grew, it is a mechanic rather than a layout, and its 17
shared vars are mostly the modal handles it puts up and takes down again. After
that, *the header* — but read the warning below first.

**Three of these should NOT be split, for three different reasons.**
`capture_view_state`/`restore_view_state` touches 22 shared vars because touching
everything *is* its job. `_build_ui` is the assembler; extracting it moves the
tangle behind a node dictionary and buys nothing. And *routing + the report verb*
is not one seam at all — the banner says routing, but everything under it as far as
the next banner is the run loop (`report` alone is 284 lines), which is what this
file is FOR. Splitting on a banner rather than on a mechanic is how you get a class
called `Routing` that owns `report()`.

**The header is the same trap, smaller.** Its 328 lines are three unrelated things
under one banner — mounting the bar, the shop pointer, the attempt tracker — plus
four page-wide helpers (`_section`, `_panel_label`, `_clear`, `_mini_button`) that
merely happen to sit at the bottom of the file. Cut it as a mechanic, not as a
region, or don't cut it.

**The constraint that shapes all of it.** `test/test_overworld2.gd` is 8695 lines
and reads privates straight off the instance. The extracted piece therefore
**cannot take those names with it**: they stay declared on `Overworld2`, with the
class owning the state under a public name and the page publishing a view of it.

**The pattern the four splits established**, for anything that follows:

- A `RefCounted` holding the page, constructed in `_build_ui` beside the
  containers it fills — or in `_init`, if it owns state the page publishes and a
  test could reach for that state before `_ready` has run (`DropQueue` does).
- **Type the back-reference as `Node`, not `Overworld2`.** Overworld2 names both
  classes, and two `class_name`s that name each other are a cyclic reference
  Godot resolves badly.
- **Pass phase in, don't read it out.** `PackStrip.rebuild(reporting: bool)`
  rather than reaching for `_phase`. `DropQueue` does the same thing a third way:
  the page answers four small questions for it (`drops_are_done`,
  `drops_are_held`, `offer_loot_to_open_screen`, `drag_pack_anchor`) so the class
  needs to know nothing about `Phase`, `_resolving`, or which screens are up.
- **A const the page still uses moves with the class**, and the page names it.
- Leave the old entry points as one-line forwards. Zero call-site churn, in the
  page or in the tests. Some forwards end up with no caller left in the page and
  exist only for the tests, which is fine and worth a comment saying so.
- **A Godot virtual cannot move.** `_notification` stays on the Node and hands
  both ends of the drag to the extracted class.
- **For state the tests read, leave a read-only property behind**, not a copy:

  ```gdscript
  var _drop_queue: Array:
      get: return _drops.queue if _drops != null else []
  ```

  The extracted class owns the state under a public name; the page publishes a
  view of it under the name the tests already use. **Check for assignment first:**
  a getter-only property cannot be assigned to, and `_drop_modal` needed a setter
  because the tests stand a modal up by hand (`_ui._drop_modal = modal`) where they
  only ever *mutate* the queue array.
- **A new `class_name` needs `godot --headless --editor --quit`** before the
  suite can see it, per `CLAUDE.md`. Every split has hit this; it reads as
  "Could not find type X" and takes the whole page down with it.

**Re-run the measurement before trusting this table.** The script is in the
CHANGELOG entry that produced it; it takes seconds and it is the only thing that
keeps this section from going stale again.

---

## 2. Tests that skip in silence

Fixed, and left here because the shape of it generalises. ~250 tests guard
themselves against a run that did not reach their case — `if pin == &"": return`,
`if _ui._fulfil_checks.is_empty(): return` — and GUT only reports **Risky** when a
test asserts *nothing at all*. A test that asserted once and then bailed reported
green, so there was no way to tell "2092 passing" from "1997 passing and 95
shrugging", and `CLAUDE.md` claimed the Risky problem was solved while the pattern
that produces it was alive in twelve files.

Every one of those guards now calls `pending("why")` before returning, which GUT
counts separately and prints as **Risky/Pending** in the totals. The skips are a
number you can watch. Treat it as a budget: a guard that fires often is a case the
suite has stopped covering, and the fix is to ARRANGE the state rather than hope
for it.

---

## 3. The Collection was paying for the whole catalog — fixed

Three findings from the 2026-09-07 pass, all in the compendium, all fixed
together because they are the same screen and the first two are the same bug seen
from two ends. Kept here for the numbers and for what they say about where to
look next.

### 3.1 A decoded cover was held for the life of the process

`GameData.cover_path` → `cover_image` (§ the lazy-load note in that file) fixed
**startup** and moved the cost to *the first time you browse*. `_cover` was then
held forever, and nothing bounded how many were held.

| | |
|---|---|
| reading all 857 `cover_image` | **7.35 s**, and texture memory 316 MB → **1304 MB** |
| scrolling the Games tab top to bottom | 16.9 s, and every one of the 857 read |
| after the fix, same scroll | texture memory 316 MB → **614 MB**, i.e. exactly the 256-cover budget |

Fixed with a shared, bounded, least-recently-used set on `GameData`
(`COVER_BUDGET`, `_cover_lru`). **The budget is sized off what a screen can
actually want at once, and that was measured rather than guessed**: the star
chart never draws more than **19** covers at any zoom (swept over the whole
range), and the Collection's grid keeps a few dozen cells near the viewport. So
the cap only bites on a walk across the catalog, which is the case it exists for,
and nothing thrashes.

**Evicting drops a reference, not a picture** — a cover still mounted in a
`TextureRect` stays alive until that node is freed. That is what makes it safe to
evict art that is on screen, and it is why 3.2 below is the half that actually
releases the memory.

### 3.2 The Games tab built 6,896 nodes

857 cells at eight nodes each. **3.29 s to open the tab headless**, with no
rendering in the way at all.

**The cost is entering the tree, not the flow container sorting.** A/B'd three
ways in the same process, adding the same 857 cells:

| where | |
|---|---|
| into a `Control` **outside** the tree | 2.3 ms |
| into a bare **mounted** `Control` (no sorting) | 1,091 ms |
| into the real `HFlowContainer` | 1,097 ms |

So "fill it detached and re-attach", the usual trick, buys nothing — measured at
1,104 ms vs 1,136 ms end to end. The only fix is not to make them.

The flow now holds all 857 cells as **empty panels of exactly the size they will
be filled at**, and only the ones near the viewport carry their contents
(`_cell_slots`, `_stream_cells`, `_fill_cell` / `_empty_cell`). The scrollbar and
the scroll position are the full catalog's either way.

| | before | after |
|---|---|---|
| Collection subtree | 6,896 nodes | **2,024** |
| open the Games tab (headless) | 3,290 ms | **1,011 ms** |
| `_populate_games()` alone | 1,425 ms | **138 ms** |
| cells carrying contents at once | 857 | **~20** |

**What it cost, and it is a real cost**: a cell can only be sized before it is
filled if every cell is the same height, so the name is clamped to `NAME_LINES`
(2) with an ellipsis past it. The median game name is 13 characters and fits one
line; about one in twenty runs past two and is now trimmed. The full name is on
the cell's tooltip, and the grid gains even rows in exchange for a ragged flow
that never lined up.

### 3.3 Every keystroke rebuilt the tab

`_search_box` wired `text_changed` straight to `_populate()`. Typing `bala` cost
**688 ms** across its four keystrokes and clearing the box back to 857 games cost
**1,347 ms** in `_populate` alone — every rebuild but the last thrown away by the
next letter.

One `Timer` at the single connect site (`SEARCH_DEBOUNCE`, `_populate_soon`)
covers all eight tabs. **The text is still stored on the keystroke and only the
rebuild is deferred**, so a sort button, a filter or a test reading `_search` in
between sees what has actually been typed.

| | before | after |
|---|---|---|
| typing `bala` (4 keystrokes) | 688 ms | **293 ms**, one rebuild |
| clearing the box back to 857 | 1,347 ms | **103 ms** |

---

## 4. The run graph stopped running a BFS per candidate — fixed

`pick_amulet_and_starts` scores every game in the band as a possible Amulet, and
then every eligible game as a possible start. Both loops asked their question one
candidate at a time, and the question needed a whole-catalog BFS each.

| | before | after |
|---|---|---|
| `pick_amulet_and_starts`, graph warm | 764 ms | **29 ms** |
| `Overworld2` add_child, cold (median of 3) | 2,188 ms | **1,301 ms** |
| `Overworld2` add_child, warm | 442 ms | **175 ms** |
| BFS memo after one boot | 669 origins / 509,778 entries | **4 / 3,048** |

**The obvious inversion does not work, and this is the part worth keeping.** The
score only looks at nodes within `EARLY_LAYERS_FOR_SCORE` (3) hops of the
reference, so "one BFS per early node instead of one per candidate" looks like the
fix. Measured on the shipping catalog it is **1.29x**: this graph is small-world,
the ball within 3 hops is 184–415 games, and the band shell it would replace is
343–562. An hour of writing for nothing. Measure the two set sizes before
believing a swap like that.

**What works is not doing the traversals at all.** The condition the score counts
— `d_from[n] + d(n, A) == d_from[A]` — is exactly "n reaches A in the
shortest-path DAG rooted at the start", because every DAG edge steps the depth by
one, so any DAG path from n to A has length `d[A] - d[n]` and that is therefore
the true distance. Both directions hold, and the graph is undirected. So every
candidate's score falls out of **one sweep in BFS order**, carrying down each node
the set of early-layer ancestors that can reach it — capped at two, which is all
the score can read, so what a node carries never grows with the graph.

The start half is the mirror image (`dag_branch_scores_to`): hold the Amulet
still, and a node counted at layer j out of the start is an ancestor of that start
exactly j levels above it in the Amulet-rooted DAG. So that sweep carries
**relative** depths where the first carries absolute ones. It also removed a BFS
that was never needed at all — `bfs_distances(start)[amulet]` is just
`d_to_amulet[start]` on an undirected graph.

Both are equivalences argued rather than refactors, so `test_run_graph_scoring.gd`
checks each against the per-candidate function **over every reachable game**, and
checks the two sweeps against each other. That test is what lets the fast paths be
trusted; if it fails, they are wrong and the slow one is the answer.

**And the memo is bounded now** (`BFS_CACHE_MAX`, emptied wholesale over the cap,
the rule `DAG_CACHE_MAX` beside it already used). The sweeps took the growth away
on their own, but "small in practice" is not a bound and what made it grow was a
call site nobody had noticed.

---

## 5. Every screen is measured against its canvas — fixed

**The Constellations view laid out at 1291×720 in a 1280 canvas**, which put the
header's own `✕ Close` a pixel off the right edge.

**The first diagnosis was wrong, and the way it was wrong is the point.** It read
as the legend: that row grows with what is on the sky, and the catalog view draws
two chips the run view does not. The legend was made an `HFlowContainer` and the
page was **still 1291**. Measuring the rows' minimum widths directly named the
real culprit — the **filter bar**, at 1275, because it carries a Region dropdown
and an `OptionButton` is as wide as its widest item, which here are the full
display names of the baked sky's capitals. So the page's width was a fact about
which games happen to be hubs. Both rows are flows now; the legend change was
right for the wrong reason and is kept, since it is the row that grows next.

`test_screens_fit.gd` is the general guard: walk a screen, compare every visible
Control's global rect to the canvas, skip `ScrollContainer`s. It measures against
**`Settings.canvas_width`, not a literal 1280**, because `request_canvas_width`
lets a screen that needs room ask for it — a screen that asks is fitting, not
overflowing.

**It found a broken harness before it found a broken screen.** A headless GUT run
gives the root window **1280×1280**, so every screen laid itself out 560px taller
than it ships and the first run reported 560px of overflow on all fourteen — with
the one real finding buried in it. The file pins the window to `CANVAS_BASE` and
asserts that the pinning took, so that failure can only happen once.

Covered: MainMenu, the character picker, the custom-run screen, the manual, the
tier list, run history, settings, all eight Collection tabs, and the star chart in
both its views. All fit.

---

## 6. Still open

**The Events tab is 909 ms** for sixteen events. With the Games tab fixed it is
the slowest thing in the compendium, it is not a node-count problem at that size,
and it was not chased.

**Compiling `Overworld2.gd` costs ~1.05 s, and it is now the largest single
number in starting a run** — bigger than everything else in the boot together.
Split out, on a cold process:

| | |
|---|---|
| `load("res://scripts/redesign2/Overworld2.gd")` | **1,019–1,092 ms** |
| the `.tscn` around it, once that is compiled | ~1 ms |
| `instantiate()` + `add_child()` (build the UI, roll the run) | 148–171 ms |

**This is the runtime number §1 never had.** That entry argues the file's size on
maintainability alone; this is what it costs the player, once, on the way into
every run.

**It is not simply the line count, and that matters for the fix.** Pre-compiling
`BattlefieldView.gd` + `ReportChecklist.gd` (5,136 lines between them) takes
205 ms; `Overworld2.gd` alone is 5,825 lines and takes ~950 ms with its
dependencies already compiled — four to five times the cost for a similar number
of lines. It is not the lambdas either (`Collection.gd` has 68 to this file's 27
and compiles in ~225 ms). Something about this file specifically is superlinear
and I did not find what. **So do not assume a split banks the second**: moving
1,000 lines into a class `Overworld2` still names leaves both compiling at the
same moment. The win, if it is there, comes from *deferring* — a modal reached
through `load()` at first use rather than through a `class_name` the page
mentions — and from whatever the superlinearity turns out to be. Measure a split
against this number rather than assuming it.

**A methodology note, because it cost an hour.** An earlier draft of this file
claimed wall-clock here swings 70%, on the evidence of "identical code measuring
1,194 ms and 2,019 ms". That was wrong and the fault was mine: the two drivers
timed different things — one called `instantiate()` *before* starting the clock
and the other inside it, so the second was carrying the ~1.05 s script compile
above and the first was not. Repeated properly, the same measurement lands within
about 7%. **When two runs of "the same thing" disagree by that much, suspect the
harness before the machine**: read what is inside the timed region first.

---


## The dead-code scan

Three functions were found unreferenced and deleted (`GameLoop2._pull_from_stack`,
`Collection._item_rarity_color`, `Collection._all_enemies`). The scan that found
them is worth re-running after any large change — a private function whose name
appears exactly once in its own file and nowhere else in `scripts/` or `test/`.
It caught a fourth last time that a refactor had just orphaned. A heuristic, not
a proof: Godot's virtuals (`_ready`, `_draw`, …) fall out only because they also
appear in other files, and a name reached through `call()` would be a false
positive — so read what it prints before deleting. It is clean as of this
commit:

```bash
for f in $(git ls-files '*.gd' | grep -v addons/); do
  grep -oP '^func \K_\w+' "$f" | while read -r fn; do
    [ "$(grep -c "\b$fn\b" "$f")" -eq 1 ] \
      && ! grep -rqF "$fn" --include='*.gd' scripts test --exclude="$(basename "$f")" \
      && echo "$f: $fn"
  done
done
```

---

## How to measure any of this

`.claude/skills/verify/` is the recipe: a temporary `test/_verify_driver.gd` +
`.tscn`, run headless (or under `xvfb-run` if you need frames), printing
`Time.get_ticks_usec()` deltas. Delete both files before committing. The atlas
numbers in the CHANGELOG were taken that way — 10 passes over the whole sky,
divided out — and that is enough resolution for everything here.
