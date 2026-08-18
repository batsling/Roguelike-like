# Performance & streamlining backlog

Findings from a read-only efficiency pass over the whole codebase (2026-08-18).
The four *measured atlas* findings from that pass are **already fixed** — see the
CHANGELOG entry "The star chart stopped doing the same work twice". What is left
is here, ranked by value for effort, with everything needed to pick each one up
cold.

Nothing in this file has been started. Each item states what is wrong, why it is
wrong, what the fix looks like, and how to know it worked.

---

## 1. The star chart walks the whole sky twice whenever a route is on it

**Where** `scripts/ui/AtlasView.gd` — `draw_layers()` (~line 450) and
`StarCanvas._draw_stars()` (~line 2394).

**What happens.** With a route drawn, `draw_layers()` returns three layers:

```gdscript
return [LAYER_STARS_OFF_ROUTE, LAYER_ROADS, LAYER_STARS_ON_ROUTE]
```

`_draw_stars` is then called once per star layer, and each call iterates *all*
852 stars, skipping the ones that belong to the other half:

```gdscript
for i in range(lay.star_count()):
    if layer == AtlasView.LAYER_STARS_OFF_ROUTE and view.on_route(i):
        continue
    if layer == AtlasView.LAYER_STARS_ON_ROUTE and not view.on_route(i):
        continue
```

So 1704 iterations and 1704 `on_route()` dictionary hits to draw 852 stars. The
split itself is right and worth keeping — it is what puts the roads *between* the
scenery and the corridor, so a route is not chopped into dashes by the 700 stars
it passes behind. Only the double sweep is waste.

**The fix.** Partition once per redraw into two `PackedInt32Array`s (off-route,
on-route) and have `_draw_stars` walk the array for its layer. Build the
partition in `StarCanvas._draw` alongside `visible_rect`, or cache it on the view
beside `_route_stars` and wipe it wherever that is wiped (`route_stars()`,
`_build_trail`, `_build_history`, `_relayout`).

**Worth.** ~2 ms a redraw on the in-run chart at 852 stars, plus the allocation
churn. Note the measured record/filter costs do **not** apply here —
`star_record_color` and `passes_filter` early-out when `pure_catalog` is false —
so this is the main remaining cost on the *run's* chart specifically.

**Verify.** `test/test_atlas.gd` covers route membership and draw layering
already; add one asserting the two partitions are disjoint and their union is
every star. Then measure with a driver (`.claude/skills/verify/`) that builds a
run chart and times 20 `_draw` passes before and after.

---

## 2. `RunMapModal.map_data()` is uncached and rebuilds the whole DAG per caller

**Where** `scripts/redesign2/RunMapModal.gd:164`, and
`scripts/runtime/RunGraph.gd:376` (`shortest_path_dag`).

**What happens.** `map_data()` calls `RunGraph.route_dag_via(...)` every time,
and five places call it per interaction:

| line | caller |
|---|---|
| 187 | `shortest_distance()` |
| 484 | `_refresh_distance_label()` |
| 502 | `_ladder_cfg()` → the ladder build |
| 703 | the legend |

`shortest_distance()` is itself called from `open_node_card()` (line 567), so
clicking a rung rebuilds the DAG twice more. `bfs_distances` is memoized
(`RunGraph._bfs_cache`) so the BFS is cheap, but the DAG assembly on top of it is
not cached at all.

**And the assembly has a quadratic edge loop:**

```gdscript
for d in range(0, amulet_dist):
    for a in layers[d]:
        for b in neighbors(a):
            if (layers[d + 1] as Array).has(b):     # linear scan
```

`Array.has()` is O(n) against the next layer, inside a loop over each node's
neighbours. Mean degree on the full catalog is ~28 and a layer can be 15+ wide.

**The fix.** Two independent changes, either worth doing alone:
- Memoize `map_data()` on `RunMapModal` against `(current, waypoint, amulet)`,
  invalidated in `_reroute()` and wherever the pin moves.
- In `shortest_path_dag`, build a `Dictionary` set per layer once
  (`{id: true}`) and test membership against that instead of `Array.has()`.

**Verify.** `test/test_run_map.gd` has thorough DAG-shape coverage
(`test_map_edges_only_step_forward_one_layer`,
`test_every_edge_of_a_forced_route_advances_one_layer`) — those are the
regression net. The win is felt opening the map on a 7-hop route.

---

## 3. `Overworld2._refresh()` is a full-page rebuild on every loop signal

**Where** `scripts/redesign2/Overworld2.gd:2404`, wired at lines 295 and 334:

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

**Careful.** The comments on `_refresh_stats` (line ~3877) record a real bug this
fixed once: signals used to land on a HUD strip that repainted immediately while
the board waited for the next full refresh, so a Hollow Heart off a kill-drop
raised Max Health with nothing on screen saying so. Any split has to keep the
board's hero repainting on `stats_changed`.

**Verify.** The whole of `test/test_overworld2.gd` is the net — it drives the real
screen through every phase. Watch particularly the `_assert_fits` tests and
`test_the_verb_chips_follow_a_gain_without_a_loop_resolve`, which exists exactly
because a chip once failed to repaint without a full resolve.

---

## 4. Dead code

Confirmed unreferenced anywhere in `scripts/` or `test/`:

| file | function |
|---|---|
| `scripts/autoload/GameLoop2.gd:1619` | `_pull_from_stack()` |
| `scripts/ui/Collection.gd:1121` | `_item_rarity_color()` |
| `scripts/ui/Collection.gd:1328` | `_all_enemies()` |

Delete on sight. (Scan that found them: a regex over `^func _name(` versus
in-file references, excluding Godot's own virtuals. Worth re-running after any
large change — it caught a fourth that a refactor had just orphaned.)

---

## 5. `Overworld2.gd` is 5218 lines

More than double the next-biggest file (`AtlasView.gd`, 2687). It currently holds
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

## How to measure any of this

`.claude/skills/verify/` is the recipe: a temporary `test/_verify_driver.gd` +
`.tscn`, run headless (or under `xvfb-run` if you need frames), printing
`Time.get_ticks_usec()` deltas. Delete both files before committing. The atlas
numbers in the CHANGELOG were taken that way — 10 passes over the whole sky,
divided out — and that is enough resolution for everything here.
