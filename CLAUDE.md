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
godot --headless -s addons/gut/gut_cmdln.gd     # GUT suite: 35 scripts, ~1970 tests, ~9 min
```

- Godot is at `/root/.local/godot/godot` and on `PATH` (installed by
  `.claude/hooks/session-start.sh` in remote sessions).
- **A new `class_name` needs an editor rescan before the suite can see it.**
  `.godot/global_script_class_cache.cfg` is gitignored and only regenerates when
  the editor scans, so a headless test run against a fresh `class_name` fails
  with "Could not find type X" — in hundreds of unrelated tests, because the
  script that referenced it failed to parse and its scene fell back to a bare
  Control. Run `godot --headless --editor --quit` once after adding one.
- **A skipped case is `pending("why")`, never a bare `return`.** ~250 tests guard
  themselves against a run that did not reach their case (`if pin == &"":`,
  `if _ui._fulfil_checks.is_empty():`, `if not view.has_layout():`). They used to
  bail in silence — and GUT only reports Risky when a test asserts **nothing at
  all**, so a test that asserted once and then bailed reported green while testing
  nothing it was written for. There was no way to tell "2092 passing" from "1997
  passing and 95 shrugging". Every one of those guards now calls `pending()` with
  the reason first, which GUT counts separately and prints as **Risky/Pending** in
  the totals: the skips are a number you can watch. Read it as a budget, not as
  noise — a guard that fires often is a case the suite has stopped covering, and
  the fix is to ARRANGE the state (`_stand_at_hops`, `_reboot`, `_disarm_board`)
  rather than to hope for it.
- **A GUT run should be all green, with no Risky / "Did not assert"** — with no
  known exceptions any more. It used to
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
- **The varying failures that used to live here are FIXED.** All were
  assertions that were only *usually* true, and they are worth reading before
  blaming a seed for a new one.
  - `test_overworld2.gd::test_leaving_the_haul_screen_lands_the_shelf_under_the_board`
    failed roughly one full-suite run in six, and only in a FULL run, which is
    what made it look like cross-file leakage. It isn't: `before_each` →
    `_open_at_first_offering` takes `choose_start(0)`, the first of a **random**
    offering, and once in a while that opening game is one of the ten hubs — at
    which point walking off its haul screen mounts that hub's shelf, exactly as
    it should. The test then asserted `_shop_panel` was null "while the haul is
    up" and found the OPENING game's shop sitting there. The behaviour was never
    wrong; the test now calls `_ui._clear_shop()` first so it starts from the
    state it is actually about, whatever the opening rolled.
  - `test_overworld2.gd::test_the_page_still_fits_the_window_with_machines_standing_on_it`
    was a **real thin margin, not a bad assertion**: the page with three machines
    under the board measured 616px of the 625px a 720p window leaves, and the
    left column's height rides on the run's random offering and checklist, whose
    goal text wraps differently game to game — so one extra wrapped line
    overflowed it. The page got 26px back out of its own CHROME (both left
    panels' content margin 12->8, the gap between them 10->8, the four gaps
    inside the select panel 8->6), which also widens their text so fewer lines
    wrap at all. The left column now measures 590 and the binding column is the
    RIGHT one at 594 — the board and the pack, which do not wrap.
  - `test_enemy_abilities.gd` dropped **one test, and which one depended on the
    seed** — the spawner, the illusionist and the summoned-body payout.
    **The cause was the FOOTPRINT, not the board being full.** All three authored
    their ability as `tier:low`, so `GameLoop2.roll_ability_enemy` drew a RANDOM
    low-tier body — and `_brood_cell` asks `fits_at`, which is about the body's
    footprint (§7.3). A rolled body wider than one cell does not fit the single
    square in front of the spawner, `_brood_cell` answers OFF_FIELD, and nothing
    is laid: correct behaviour ("a spawner with no space simply does not spawn
    this turn"). Those three now name a one-cell body through `_one_cell_selector()`
    (`enemy:<id>`, picked out of the roster by shape rather than hardcoded), and
    `test_a_spawner_with_nowhere_to_lay_a_body_lays_nothing` asserts the other
    half on purpose. If a spawner test starts varying again, look at what the
    selector rolls before anything else.
- The leaked-RID / orphan warnings at the end of a GUT run are also pre-existing
  noise from UI tests that build Controls.
- To see a change on screen rather than in assertions, use the `verify` skill
  (`.claude/skills/verify/`) — Xvfb + a temporary driver scene.
- **GUT cannot see the OBS overlay, because the overlay is a browser page.**
  `test_obs_companion.gd` pins the payload and stops at the file; everything past
  it — whether `hidden` hides, whether the road actually scrolls, whether a burst
  of toasts stays inside the browser source, how tall the page really is — needs
  `node tools/check_overlay.js`, which renders `obs/overlay.html` in headless
  Chromium and asserts all of it. Run it whenever anything under `obs/` changes;
  every check in it is a regression that shipped once. It needs
  `npm install playwright-core` and a Chromium (`--browser=` or `$CHROMIUM_PATH`
  if it cannot find one).

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
