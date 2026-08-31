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
| what is known-slow and not yet fixed | `docs/performance-backlog.md` — measured findings with the fix for each. One left: splitting `Overworld2.gd` |
| combat-era designs | `docs/archive/` — **describes systems that no longer exist**; see its README before trusting a path or class name |

## The shape of it

- **Two scenes only.** `scenes/menu/MainMenu.tscn` boots, `scenes/redesign2/Overworld2.tscn`
  *is* the game. Every screen is built in code, so `.tscn` files hold a root node
  and a script and nothing else — don't go looking for UI in them.
- **25 autoloads** in `scripts/autoload/`, registered in `project.godot`. The ones
  that matter most: `GameState` (run-persistent state), `Data` (loads every
  `.tres` and serves it by id), `GameLoop2` (the run loop — `Overworld2` is a view
  over it), `EffectSystem` + `TriggerBus` (effect dispatch and the signal hub).
  README's "Autoload singletons" table covers all 25.
- **Content is data, never code.** Everything lives as typed `.tres` under `data/`,
  with schemas in `scripts/resources/`. Gameplay code asks `Data` for content
  rather than hardcoding it.
- **The spreadsheet is upstream of `data/`.** `tools/Roguelikes.xlsx` drives the
  `tools/generate_*.py` and `tools/import-*.py` generators. Edit the sheet and
  regenerate; don't hand-edit generated `.tres` in bulk. If you change the shape
  a `.tres` is written in, **update the generator in the same commit** or the next
  regeneration silently reverts you.
  **Never edit the workbook with openpyxl** — a round-trip drops its eight charts.
  `tools/_xlsx_surgery.py` rewrites one sheet's XML and copies every other zip
  entry through byte-for-byte; the `_*_setup.py` one-shots beside it are the
  worked examples. Note the sheet names lost their `2.0` suffixes (`enemies2.0` →
  `enemies`, and so on); the output folders did not move.

## Working here

```bash
godot --headless -s addons/gut/gut_cmdln.gd     # GUT suite: 36 scripts, ~1920 tests, ~8 min
```

- Godot is at `/root/.local/godot/godot` and on `PATH` (installed by
  `.claude/hooks/session-start.sh` in remote sessions).
- **A new `class_name` needs an editor rescan before the suite can see it.**
  `.godot/global_script_class_cache.cfg` is gitignored and only regenerates when
  the editor scans, so a headless test run against a fresh `class_name` fails
  with "Could not find type X" — in hundreds of unrelated tests, because the
  script that referenced it failed to parse and its scene fell back to a bare
  Control. Run `godot --headless --editor --quit` once after adding one.
- **A GUT run should be all green, with no Risky / "Did not assert"** — with the
  two known seed-dependent exceptions listed below. It used to
  report one or two, varying between runs, because a couple of tests early-
  `return`ed when the run's random graph didn't reach the case they were about.
  Both are fixed: `test_atlas.gd::test_path_taken_follows_the_order_the_games_were_visited`
  now walks the graph's own edges (revisits included) so a history always exists,
  and `test_run_map.gd::test_the_route_fits_the_window_it_opens_in` asserts the
  *other* branch — the fit bottoming out at the legibility floor — rather than
  asserting nothing. If a Risky turns up, it is a new one; find out which case
  stopped being reachable rather than assuming it is noise.
- **A test that stands a body on the front line and expects a swing is a flake
  waiting to happen.** The offering rolls a RANDOM enemy, and since §7.6 an
  ability can spend a body's whole turn on something other than you (Ritual,
  Defensive Stance, either spawner, a thief's getaway) or add a body to the board
  mid-turn. `test_overworld2` has `_disarm_board()` / `_front_line()` for exactly
  this, and `test_statuses` does it inline. Tests about the SCREEN should disarm;
  `test_enemy_abilities.gd` is where abilities are the subject.
- **The same goes for a FAILURE that comes and goes.** `test_atlas.gd::test_the_route_set_is_rebuilt_when_the_run_moves`
  failed on roughly one run in four, on any tree, because it asserted that
  `AtlasView.route_stars()` DIFFERS after the run moves. It doesn't always:
  that set is the union of the road ahead and the road walked, so stepping along
  the optimal path moves the game you left from one half into the other and
  leaves the union identical — a correct rebuild that reads exactly like a stale
  cache. It now checks the cache against a fresh build instead, which is what
  "rebuilt" meant and is true either way. Before blaming a random graph for a
  varying failure, work out which assertion is only *usually* true.
- **TWO varying failures are currently UNFIXED, and both PREDATE the cards work**
  — measured against a clean worktree of the same commit, not assumed. A full run
  is all-green most of the time and drops one or two of these when the global RNG
  stream lands badly, so a red run is worth re-running *once* before believing it.
  - `test_overworld2.gd::test_the_page_still_fits_the_window_with_machines_standing_on_it`
    is a **real thin margin, not a bad assertion**: the page with three machines
    under the board measures **616px of the 625px a 720p window leaves**, so nine
    pixels is the whole budget — and the left column's height rides on the run's
    random offering and checklist, whose goal text wraps differently game to game.
    One extra wrapped line overflows it. Fixing it means giving the page back some
    room (the checklist, the offering rows, the panel's own chrome), not widening
    the assertion, which is measuring something true.
  - `test_enemy_abilities.gd` drops **one test, and which one depends on the
    seed** — three have been seen (`test_a_spawner_puts_a_body_in_front_of_it_and_never_moves`,
    `test_a_summoned_body_is_an_ordinary_body_and_pays_out`,
    `test_an_illusionist_makes_copies_that_die_with_it`). Run this script alone
    and it fails deterministically — on the baseline too, because nothing has
    consumed the global stream ahead of it; run it inside a full suite and it
    usually passes.
    **The cause is the FOOTPRINT, not the board being full.** All three author
    their ability as `tier:low`, so `GameLoop2.roll_ability_enemy` draws a RANDOM
    low-tier body — and `_brood_cell` asks `fits_at`, which is about the body's
    footprint (§7.3). A rolled body wider than one cell does not fit the single
    square in front of the spawner, `_brood_cell` answers OFF_FIELD, and nothing
    is laid. That is correct behaviour ("a spawner with no space simply does not
    spawn this turn") and an assertion that is only *usually* true.
    The fix is to name the body — `enemy:<id>` on a known 1x1 — in the tests whose
    subject is the PAYOUT rather than the roll, and to assert the "nowhere to lay
    it" case in its own test. `_disarm_board()` is not the answer here: this file
    is where abilities ARE the subject.
- The leaked-RID / orphan warnings at the end of a GUT run are also pre-existing
  noise from UI tests that build Controls.
- To see a change on screen rather than in assertions, use the `verify` skill
  (`.claude/skills/verify/`) — Xvfb + a temporary driver scene.

## Things that will bite you

- **`project.godot` comments are `;`, not `#`.** A `#` line is parsed as part of
  the NEXT key. This already silently renamed the `backpack` input action once;
  `test/test_collection.gd` now guards against it.
- **A `class_name` that shadows a NATIVE Godot class is a parse error**, and it
  takes down every `.tres` that names the script — `Data` then loads that whole
  folder as zero rows and the failure surfaces hundreds of tests away as missing
  content. `tiles2.0`'s resource is `TileEffectData` for exactly this reason:
  Godot already ships a `TileData` for TileMaps. Check a new name with
  `godot --headless --check-only --script scripts/resources/<New>.gd` before
  wiring it up — it says "hides a native class" in one line.
- **Game covers load lazily.** `GameData.cover_path` holds the path and
  `GameData.cover_image` loads it on first read. Do **not** turn `cover_image`
  back into an `@export var ... : Texture2D` — `Data` loads all 854 games at
  startup and an ExtResource resolves eagerly, which meant decoding ~206 MB of
  PNG on every boot and every headless test run (~5.2s of a ~5.7s startup).
- **`data/games/` has 854 files.** Never glob or read it wholesale to answer a
  question; query it with `grep` for the field you care about.
- **The repo tracks source only.** `.godot/`, `*.import`, `*.uid` and
  `export_presets.cfg` are gitignored and regenerate. They show up in local file
  listings and are not part of the project.
- Art filenames are **PascalCase**, matched to content ids by convention. **Pill
  capsules are the exception**: `images2.0/pills/` is matched to pills by the RUN
  (`PillSystem.COLORS` deals 10 of the 13 per run and leaves 3 meaning nothing),
  so a new colour has to be added to that const list as well as to the folder, in
  both `<Colour>.png` and `<Colour>Horse.png`. `test_pill_system.gd` checks the
  list against the folder in one direction only — art that ships without being
  listed is art no run can ever show.
- **A new UI glyph needs `tools/build_glyph_font.py` re-run.** The UI is drawn out
  of ~70 symbols (⚔ ☠ ⚡ 🏆 …) and Godot's built-in font has two of them; the rest
  are shipped as subsetted Noto fonts in `fonts/`, chained onto the theme font by
  `UITheme.glyph_font`. A glyph that isn't in them still renders — the chain ends
  in a system-searching font — but it costs ~2 ms of host font search every time
  a Label carrying it is created, which is what shipping them was for.
  `test_display_settings.gd` fails if the source uses one the fonts don't have.
  **Rebuilding is two steps**: run the script, then `godot --headless --editor --quit`
  so Godot re-imports the changed `.ttf`s — until it does, the new glyph is on disk
  and the test still fails, which reads exactly like the script not having worked.
  It also needs `pip install fonttools brotli` and network access to fontsource.
  If you ever swap a font in there, its **vertical metrics must stay on the base
  font's em grid** (4096 upem, ascender 4378, descender 1200): Godot takes a
  font's height as the max over the whole fallback chain, so a taller subset makes
  every line in the game taller and the 720p fit tests fail 63px over.
