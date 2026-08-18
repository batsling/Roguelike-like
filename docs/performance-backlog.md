# Performance & streamlining backlog

Findings from a read-only efficiency pass over the whole codebase (2026-08-18).

**Fixed since, and out of this file:** the four measured *atlas* findings (see the
CHANGELOG entry "The star chart stopped doing the same work twice"), and then the
star-chart double sweep, the uncached route DAG, and the three dead functions
(see "Two hot paths that were doing the work twice"). What is left is here,
ranked by value for effort, with everything needed to pick each one up cold.

Each item states what is wrong, why it is wrong, what the fix looks like, and how
to know it worked. Neither remaining item has been started.

**One measurement worth keeping** from the pass that removed items 1, 2 and 4:
the quadratic `Array.has()` edge loop in `RunGraph.shortest_path_dag` — the
second half of what was item 2 — measured **flat**. A/B'd against the same route
in the same process it was 0.322 ms with `Array.has()` and 0.308 ms with a
`Dictionary` set per layer, which is noise. The layers of a real route are two or
three games wide, not the 15+ the degree curve suggested, so the linear scan was
never scanning anything. The set went in anyway (it is strictly better and
measured no worse) but it bought nothing, and **the memo was the entire win**.
Worth remembering before optimising another loop on its shape rather than on a
measurement.

---

## 1. `Overworld2._refresh()` is a full-page rebuild on every loop signal

**Where** `scripts/redesign2/Overworld2.gd:2430`, wired at lines 299 and 338:

```gdscript
GameLoop2.loop_changed.connect(_refresh)              # 22 emit sites
GameState.player_statuses_changed.connect(_refresh)
```

**What happens.** One `_refresh()` tears down and rebuilds the pack strip
(`_refresh_items`), the header's route strip (`_refresh_route_strip`), the board
(`_board.refresh()`), the offering cards, the standing checklist and the charge
chips — every one of them `_clear()`ing its container and `queue_free()`ing its
children. `GameLoop2` emits `loop_changed` from 22 places, several of them inside
a resolve.

**The fix, in order of value:**
- Split the signal, or the handler. Most `loop_changed` emits move *the board*
  and nothing else; they do not need the offering, the route strip or the pack
  rebuilt. A `_refresh_board_only()` on the hot paths would cut the majority.
- Make `_refresh_route_strip` idempotent — it draws `GameState.walked_path()`,
  which changes only when the run *moves*. Rebuild it on arrival, not on every
  signal.
- Same for `_refresh_items`: rebuild on `inventory_changed`, not on
  `loop_changed`.

**Careful.** The comments on `_refresh_stats` (line ~3999) record a real bug this
fixed once: signals used to land on a HUD strip that repainted immediately while
the board waited for the next full refresh, so a Hollow Heart off a kill-drop
raised Max Health with nothing on screen saying so. Any split has to keep the
board's hero repainting on `stats_changed`.

**Verify.** The whole of `test/test_overworld2.gd` is the net — it drives the real
screen through every phase. Watch particularly the `_assert_fits` tests and
`test_the_verb_chips_follow_a_gain_without_a_loop_resolve`, which exists exactly
because a chip once failed to repaint without a full resolve.

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
