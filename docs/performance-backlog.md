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
every screen idles at the loop floor with nothing redrawing per frame. Three of
its findings are **fixed and written up in §3 below**; three are open and listed
in §4.

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

## 4. Open, from the same pass

**`RunGraph.pick_amulet_and_starts` is most of the boot, and leaks a BFS memo.**
868 ms on the first roll, still 302–426 ms warm; `Overworld2` add_child (build +
`start_run`, no frames) is 1,194 ms cold. The cause is one omitted argument —
`RunGraph.gd:862` calls `dag_branch_score_early(d_ref, g.id)` without the
`d_to_amulet_cache` the function already takes, so **every band candidate runs a
full-graph `bfs_distances`**. The memo is unbounded: 669 origins / 509,778
distance entries after one roll, 762 after four, growing every run for the life of
the process. The fix inverts the traversal — the score only asks about nodes
within `EARLY_LAYERS_FOR_SCORE` hops of the reference, so run one BFS per *early
node* (a small ball) instead of one per *candidate amulet* (the 5–7-hop shell,
which in a small-world graph is most of the catalog), then score every candidate
in one sweep. Exact, not sampled.

**The Constellations view is 11 px too wide for the 1280 canvas.** The
pure-catalog `AtlasView` lays out at **1291×720**: the header's `✕ Close` ends at
x=1281 and the legend's "Star size = connections" note at x=1283, both clipped off
the right edge. `_fill_legend` is a plain `HBoxContainer`, and in `pure_catalog`
it gains two chips the run view does not have (`⚔ Beaten`, `👑 Amulet won`); that
row's minimum width sets the whole page's. **Opened from a run it measures exactly
1280 and fits**, which is why nothing has caught it. An `HFlowContainer` for the
legend row — the container the Collection grid already uses — wraps the key
instead of widening the page.

**The 720p fit test only covers the overworld.** `test_overworld2.gd::_assert_fits`
is the suite's only fit guard, and the finding above is precisely what it cannot
see. The audit that found it is ~30 lines — walk the tree, compare each
`Control`'s global rect to the viewport, skip `ScrollContainer`s — and every other
screen passes it today: MainMenu, the character picker, all eight Collection tabs,
HowToPlay, TierList, RunHistory, Settings and the overworld page.

**And one observation worth a look.** With the Games tab fixed, the slowest thing
in the compendium is the **Events tab at 909 ms** for sixteen events, which is not
a node-count problem at that size and was not chased.

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
