# CLAUDE.md

Godot 4.6 project at the repository root (`project.godot` is here, so `res://x`
is `./x`). A roguelike played on a graph of real video games: each node is a real
game, and the "combat" is you going off and actually playing it, reported back on
the honour system.

## Orientation — read in this order

| you need | read |
|---|---|
| how the current build works | `docs/games-first-redesign.md` — **the canonical spec**, referenced from 25 places |
| repo layout, autoloads, screen flow | `README.md` (~20 KB, all of it current) |
| what changed and why | `CHANGELOG.md` — narrative history, not needed to make a change |
| what is known-slow and not yet fixed | `docs/performance-backlog.md` — measured findings with the fix for each. Two left: the ~2 ms every emoji glyph costs to shape (no font is shipped), and splitting `Overworld2.gd` |
| combat-era designs | `docs/archive/` — **describes systems that no longer exist**; see its README before trusting a path or class name |

## The shape of it

- **Two scenes only.** `scenes/menu/MainMenu.tscn` boots, `scenes/redesign2/Overworld2.tscn`
  *is* the game. Every screen is built in code, so `.tscn` files hold a root node
  and a script and nothing else — don't go looking for UI in them.
- **15 autoloads** in `scripts/autoload/`, registered in `project.godot`. The ones
  that matter most: `GameState` (run-persistent state), `Data` (loads every
  `.tres` and serves it by id), `GameLoop2` (the run loop — `Overworld2` is a view
  over it), `EffectSystem` + `TriggerBus` (effect dispatch and the signal hub).
  README's "Autoload singletons" table covers all 15.
- **Content is data, never code.** Everything lives as typed `.tres` under `data/`,
  with schemas in `scripts/resources/`. Gameplay code asks `Data` for content
  rather than hardcoding it.
- **The spreadsheet is upstream of `data/`.** `tools/Roguelikes.xlsx` drives the
  `tools/generate_*.py` and `tools/import-*.py` generators. Edit the sheet and
  regenerate; don't hand-edit generated `.tres` in bulk. If you change the shape
  a `.tres` is written in, **update the generator in the same commit** or the next
  regeneration silently reverts you.

## Working here

```bash
godot --headless -s addons/gut/gut_cmdln.gd     # GUT suite: 25 scripts, ~1010 tests, ~5 min
```

- Godot is at `/root/.local/godot/godot` and on `PATH` (installed by
  `.claude/hooks/session-start.sh` in remote sessions).
- **A new `class_name` needs an editor rescan before the suite can see it.**
  `.godot/global_script_class_cache.cfg` is gitignored and only regenerates when
  the editor scans, so a headless test run against a fresh `class_name` fails
  with "Could not find type X" — in hundreds of unrelated tests, because the
  script that referenced it failed to parse and its scene fell back to a bare
  Control. Run `godot --headless --editor --quit` once after adding one.
- **A GUT run should be all green, with no Risky / "Did not assert".** It used to
  report one or two, varying between runs, because a couple of tests early-
  `return`ed when the run's random graph didn't reach the case they were about.
  Both are fixed: `test_atlas.gd::test_path_taken_follows_the_order_the_games_were_visited`
  now walks the graph's own edges (revisits included) so a history always exists,
  and `test_run_map.gd::test_the_route_fits_the_window_it_opens_in` asserts the
  *other* branch — the fit bottoming out at the legibility floor — rather than
  asserting nothing. If a Risky turns up, it is a new one; find out which case
  stopped being reachable rather than assuming it is noise.
- **The same goes for a FAILURE that comes and goes.** `test_atlas.gd::test_the_route_set_is_rebuilt_when_the_run_moves`
  failed on roughly one run in four, on any tree, because it asserted that
  `AtlasView.route_stars()` DIFFERS after the run moves. It doesn't always:
  that set is the union of the road ahead and the road walked, so stepping along
  the optimal path moves the game you left from one half into the other and
  leaves the union identical — a correct rebuild that reads exactly like a stale
  cache. It now checks the cache against a fresh build instead, which is what
  "rebuilt" meant and is true either way. Before blaming a random graph for a
  varying failure, work out which assertion is only *usually* true.
- The leaked-RID / orphan warnings at the end of a GUT run are also pre-existing
  noise from UI tests that build Controls.
- To see a change on screen rather than in assertions, use the `verify` skill
  (`.claude/skills/verify/`) — Xvfb + a temporary driver scene.

## Things that will bite you

- **`project.godot` comments are `;`, not `#`.** A `#` line is parsed as part of
  the NEXT key. This already silently renamed the `backpack` input action once;
  `test/test_collection.gd` now guards against it.
- **Game covers load lazily.** `GameData.cover_path` holds the path and
  `GameData.cover_image` loads it on first read. Do **not** turn `cover_image`
  back into an `@export var ... : Texture2D` — `Data` loads all 852 games at
  startup and an ExtResource resolves eagerly, which meant decoding ~206 MB of
  PNG on every boot and every headless test run (~5.2s of a ~5.7s startup).
- **`data/games/` has 852 files.** Never glob or read it wholesale to answer a
  question; query it with `grep` for the field you care about.
- **The repo tracks source only.** `.godot/`, `*.import`, `*.uid` and
  `export_presets.cfg` are gitignored and regenerate. They show up in local file
  listings and are not part of the project.
- Art filenames are **PascalCase**, matched to content ids by convention.
