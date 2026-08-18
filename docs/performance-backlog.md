# Performance & streamlining backlog

Findings from a read-only efficiency pass over the whole codebase (2026-08-18).

**Fixed since, and out of this file:** the four measured *atlas* findings (see the
CHANGELOG entry "The star chart stopped doing the same work twice"); then the
star-chart double sweep, the uncached route DAG and the three dead functions
("Two hot paths that were doing the work twice"); then the overworld's full-page
`_refresh` ("The page stopped redrawing things that had not changed"). What is
left is here, with everything needed to pick each one up cold.

Each item states what is wrong, why it is wrong, what the fix looks like, and how
to know it worked. Neither remaining item has been started.

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
**five small verb chips, at 10.9 ms**, for the reason that is now item 1 below.
Both times the thing that looked expensive was cheap and something unremarkable
next to it was not. Measure first.

---

## 1. Every emoji glyph on the page costs ~2 ms to draw, every time

**Where** everywhere. `scripts/ui/UITheme.gd` sets `default_font_size` and no
font; the project ships no font file at all (`find . -iname '*.ttf' -o -iname
'*.otf'` outside `addons/` returns nothing), so the whole UI renders in Godot's
built-in font.

**What happens.** That font has no coverage for the glyphs the UI is built out of
— `⛏ ⚡ ⚗ 🎲 🍀 🏆 🛒 ☠ ★ ✦ ⚔` and the rest — so every time a `Label` or `Button`
carrying one is *created*, the TextServer runs a system-font fallback search for
it. Measured on the verb chips, building five of them into the live tree:

| five chips | |
|---|---|
| plain ASCII text | **0.613 ms** |
| one emoji each | **10.876 ms** |
| ASCII, long multi-line tooltip | 0.460 ms |

So roughly **2 ms per Label that contains one**, paid on every rebuild, and the
tooltips (the other suspect) cost nothing. This was 10 of the 19 ms a full page
`_refresh` used to take; the repaint guards now skip most of those rebuilds, so
what is left is the cost of a rebuild that genuinely has to happen — a verb
moving, a body arriving — plus every *first* build of every screen.

**The fix**, in order of how much it asks for:
- **Ship a font with the coverage** and set it as the theme's `default_font`, or
  add it to the built-in font's `fallbacks`. One asset, one line in `UITheme`,
  and every glyph on every screen gets cheap at once. It is also the only one of
  these that improves how the game *looks* — the built-in font is rendering these
  as whatever the host system offers, which is why they differ between machines.
- **Cache the shaped Controls** rather than rebuilding them: keep the five chips
  and set `.text` on them, since Godot no-ops a `text` assignment that doesn't
  change. Narrower, and only helps the sections that get rewritten.
- **Drop the glyphs.** Cheapest, and the worst of the three — they are most of
  how the page reads at a glance.

**Careful.** This is measured on Linux/fontconfig under `xvfb`. Confirm the same
cost on the platform that matters before spending an asset on it; a host with a
fast fallback path may not show it.

**Verify.** Build N Labels with and without a glyph and time it — the numbers
above came from a driver doing exactly that (`.claude/skills/verify/`). The whole
of `test/test_overworld2.gd` is the net for anything that changes the theme.

---

## 2. `Overworld2.gd` is 5309 lines

More than double the next-biggest file (`AtlasView.gd`, 2764). It currently holds
the run-loop view, the report checklist, the pinned header, the map plumbing, the
shop and machine mounting, the charge chips, the offering cards, and the
save/load view state.

**Not urgent, and not a mechanical job.** The obvious seams, roughly in order of
how cleanly they come out:

- **The header** (`_mount_header`, `_fit_page_under_header`, `_publish_header_strip`,
  `_build_health_chip`, `_build_gold_chip`, `_refresh_route_strip`, `HEADER_LAYER`)
  — self-contained, talks to the page only through `ModalScaffold.reserved_top`
  and the scroll's `offset_top`. ~250 lines.
- **The report checklist** (`_populate_play_panel`, `_verify_row`,
  `_add_bonus_rows`, `_add_event_goal_rows`, `_ticked_*`, `_reset_checklist_state`)
  — one input (the board's bodies plus the standing goals), one output (the ticked
  instances). ~400 lines.
- **The offering** (`_make_choice_card`, `_make_start_card`, `_render_choices`,
  `_render_start_choices`, `_show_preview`, `_hover_line`) — ~350 lines.

Each wants to keep going through the overworld's public verbs (`pick`,
`report`, `bash_choice`, …) rather than reaching into `GameLoop2`, which is what
makes the current tests keep working through the move.

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
