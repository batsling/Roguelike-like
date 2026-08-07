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
| combat-era designs | `docs/archive/` — **describes systems that no longer exist**; see its README before trusting a path or class name |

## The shape of it

- **Two scenes only.** `scenes/menu/MainMenu.tscn` boots, `scenes/redesign2/Overworld2.tscn`
  *is* the game. Every screen is built in code, so `.tscn` files hold a root node
  and a script and nothing else — don't go looking for UI in them.
- **14 autoloads** in `scripts/autoload/`, registered in `project.godot`. The ones
  that matter most: `GameState` (run-persistent state), `Data` (loads every
  `.tres` and serves it by id), `GameLoop2` (the run loop — `Overworld2` is a view
  over it), `EffectSystem` + `TriggerBus` (effect dispatch and the signal hub).
  README's "Autoload singletons" table covers all 14.
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
godot --headless -s addons/gut/gut_cmdln.gd     # GUT suite: 17 scripts, ~612 tests, ~3.5 min
```

- Godot is at `/root/.local/godot/godot` and on `PATH` (installed by
  `.claude/hooks/session-start.sh` in remote sessions).
- `test/test_run_map.gd::test_the_route_fits_the_window_it_opens_in` reports
  **Risky / "Did not assert"**. That is pre-existing: the test early-`return`s
  when the route is too big to fit. Not a regression you introduced.
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
  back into an `@export var ... : Texture2D` — `Data` loads all 818 games at
  startup and an ExtResource resolves eagerly, which meant decoding ~206 MB of
  PNG on every boot and every headless test run (~5.2s of a ~5.7s startup).
- **`data/games/` has 818 files.** Never glob or read it wholesale to answer a
  question; query it with `grep` for the field you care about.
- **The repo tracks source only.** `.godot/`, `*.import`, `*.uid` and
  `export_presets.cfg` are gitignored and regenerate. They show up in local file
  listings and are not part of the project.
- Art filenames are **PascalCase**, matched to content ids by convention.
