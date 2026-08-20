# Performance & streamlining backlog

Findings from a read-only efficiency pass over the whole codebase (2026-08-18).

**Fixed since, and out of this file:** the four measured *atlas* findings (see the
CHANGELOG entry "The star chart stopped doing the same work twice"); then the
star-chart double sweep, the uncached route DAG and the three dead functions
("Two hot paths that were doing the work twice"); then the overworld's full-page
`_refresh` ("The page stopped redrawing things that had not changed"); and then
the glyph shaping cost that one uncovered, by shipping the fonts ("The UI stopped
asking the host what a ⚔ looks like").

**One item is left**, below, and it has not been started. It states what is wrong,
why it is wrong, what the fix looks like, and how to know it worked.

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

## 1. `Overworld2.gd` is 4707 lines

Down from 5573. Still the biggest file in the repo (`AtlasView.gd` is 2764) — it
holds the run-loop view, the pinned header, the map plumbing, the shop and
machine mounting, the offering cards, and the save/load view state.

**Not urgent, and not a mechanical job.** This file used to guess at the seams;
they are measured now. The number that matters is **genuinely shared state** —
vars the region touches that are also touched from outside it, which is the real
cost of cutting there. Half of what looks shared is state that merely happens to
be *declared* at the top of the file and is used nowhere but the one region, so
it moves for free.

| seam | lines | genuinely shared state | test refs |
|---|---|---|---|
| ~~item strip + charge chips~~ | ~~293~~ | ~~`_items_box`, `_phase`~~ | **done — `PackStrip.gd`** |
| ~~report checklist~~ | ~~776~~ | ~~`_board`, `_chosen`~~ | **done — `ReportChecklist.gd`** |
| header proper | 79 | `_scroll`, `_toasts` | 11 |
| kill-drops + run-over | 230 | `_banner`, `_drop_queue`, `_rng`, `_resolving` | 32 |
| offering cards + preview | 558 | `_choices`, `_chosen`, `_start_options`, `_phase` | 24 |
| save/restore view state | 251 | *16 shared vars* | — |
| `_build_ui` | 409 | *32 vars, 16 funcs* | — |

**Next: the offering cards** (`_make_choice_card`, `_make_start_card`,
`_render_choices`, `_render_start_choices`, `_show_preview`, `_hover_line`) at
558 lines, then **kill-drops** at 230 and **the header** at 79. None of the three
is urgent; the offering is the only one big enough to be worth the disturbance.

**Two of these should NOT be split.** `capture_view_state` / `restore_view_state`
touches 16 shared vars because touching everything *is* its job, and `_build_ui`
is the assembler — extracting it moves the tangle behind a node dictionary and
buys nothing.

**The constraint that shapes all of it.** `test/test_overworld2.gd` is 4476 lines
and reads privates straight off the instance — `_ui._verify_box` ×17,
`_ui._items_box` ×16, `_ui._drop_queue` ×16, `_ui._fulfil_checks` ×8. The
extracted piece therefore **cannot take those names with it**: they stay declared
on `Overworld2`, with the page owning the container and the extracted class
filling it. Each wants to keep going through the overworld's public verbs
(`pick`, `report`, `bash_choice`, …) rather than reaching into `GameLoop2`, which
is what makes the current tests keep working through the move.

**The pattern the two done splits established**, for the next one to copy:

- A `RefCounted` holding the page, constructed in `_build_ui` beside the
  containers it fills. The repo's other extraction, `AtlasLayoutBuilder`, is
  static-only because layout is pure computation; a UI builder needs the page
  back, for the verbs its widgets call.
- **Type the back-reference as `Node`, not `Overworld2`.** Overworld2 names both
  classes, and two `class_name`s that name each other are a cyclic reference
  Godot resolves badly.
- **Pass phase in, don't read it out.** `PackStrip.rebuild(reporting: bool)`
  rather than reaching for `_phase`, which is what let the strip depend on
  nothing about the page except three public verbs.
- Leave the old entry points as one-line forwards (`_refresh_items`,
  `_populate_play_panel`, `_ticked_fulfilments`, …). Zero call-site churn, in the
  page or in the tests. Some forwards end up with no caller left in the page and
  exist only for the tests, which is fine and worth a comment saying so.
- **For state the tests read, leave a read-only property behind**, not a copy:

  ```gdscript
  var _fulfil_checks: Array:
      get: return _checklist.fulfil_checks if _checklist != null else []
  ```

  The extracted class owns the state under a public name; the page publishes a
  view of it under the name the tests already use. This works because no test
  ever *reassigns* one of these — they read the array and then tick the CheckBox
  it points at, which is what a player does to the same object. Check that before
  reaching for it: a getter-only property cannot be assigned to.
- **A new `class_name` needs `godot --headless --editor --quit`** before the
  suite can see it, per `CLAUDE.md`. Both splits hit this; it reads as
  "Could not find type X" and takes the whole page down with it.

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
