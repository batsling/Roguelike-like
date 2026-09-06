# Performance & streamlining backlog

Findings from a read-only efficiency pass over the whole codebase (2026-08-18).

**Fixed since, and out of this file:** the four measured *atlas* findings (see the
CHANGELOG entry "The star chart stopped doing the same work twice"); then the
star-chart double sweep, the uncached route DAG and the three dead functions
("Two hot paths that were doing the work twice"); then the overworld's full-page
`_refresh` ("The page stopped redrawing things that had not changed"); and then
the glyph shaping cost that one uncovered, by shipping the fonts ("The UI stopped
asking the host what a ⚔ looks like").

**Two items are left**, below. §1 is in progress — a fourth split has landed and
the seam table has been re-measured, because the old one had gone badly stale;
§2 is fixed and kept for the shape of it. Each states what is wrong, why it is
wrong, what the fix looks like, and how to know it worked.

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
